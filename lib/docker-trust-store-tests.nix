# docker-trust-store-tests.nix - Checks for the Docker image TLS trust store.
#
# GHSA-6q48-6c7w-9gw2: eight compromised eMudhra intermediates chain to
# "emSign ECC Root CA - G3". These checks assert that the root is not trusted
# in the image's SSL_CERT_FILE bundle or in the p11-kit trust source, both on
# the pinned nixpkgs and on the oldest nixpkgs pin the README examples use.
{
  lib,
  pkgs,
  project,
  checkScript,
  system,
}:
let
  # release-25.05 is the oldest pin in the README examples. Its cacert is
  # 3.117, which still ships G3, so it exercises the blacklist branch.
  oldNixpkgsRev = "3e3f3c7f9977dc123c23ee21e8085ed63daf8c37";
  oldNixpkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${oldNixpkgsRev}.tar.gz";
    sha256 = "sha256-jc21hKogFnxU7KXSVTRmxC7u5D4RHwm9BAvDf5/Z1Uo=";
  }) { inherit system; };

  mkImage =
    {
      name,
      pkgsLinux ? pkgs,
    }:
    project.mkDockerImage {
      inherit name;
      Entrypoint = [ "${pkgsLinux.coreutils}/bin/true" ];
      pkgsLinux = pkgsLinux;
    };

  newImage = mkImage { name = "trust-store-new-pin"; };
  oldImage = mkImage {
    name = "trust-store-old-pin";
    pkgsLinux = oldNixpkgs;
  };

  affectedFingerprints = lib.concatStringsSep " " (builtins.attrValues newImage.affectedEmsignRoots);

  # Compare the image environment with the derivations it ships. The bundle
  # must come from the cacert in defaultBasePackages, and the image must not
  # carry a second, unfiltered cacert.
  mkTrustStoreCheck =
    { name, image }:
    let
      trustedP11kit = image.cacert.p11kit;
    in
    pkgs.runCommand "check-${name}"
      {
        nativeBuildInputs = with pkgs; [
          bash
          coreutils
          gawk
          gnugrep
          gnused
          gnutar
          gzip
          jq
          openssl
          checkScript
        ];
        inherit image;
        inherit trustedP11kit;
        AFFECTED_EMSIGN_FINGERPRINTS = affectedFingerprints;
      }
      ''
        set -euo pipefail

        mkdir image root
        tar -xzf "$image" -C image

        config="$(jq -r '.[0].Config' image/manifest.json)"
        ssl_cert_file="$(jq -r '.config.Env[] | select(startswith("SSL_CERT_FILE=")) | sub("^SSL_CERT_FILE="; "")' "image/$config")"
        if [[ -z "$ssl_cert_file" ]]; then
          echo "FAIL: the image has no SSL_CERT_FILE" >&2
          exit 1
        fi
        case "$ssl_cert_file" in
          */etc/ssl/certs/ca-bundle.crt) ;;
          *)
            echo "FAIL: unexpected SSL_CERT_FILE: $ssl_cert_file" >&2
            exit 1
            ;;
        esac

        ssl_store="''${ssl_cert_file%/etc/ssl/certs/ca-bundle.crt}"
        expected_store="$(realpath "${image.cacert}")"
        if [[ "$ssl_store" != "$expected_store" ]]; then
          echo "FAIL: SSL_CERT_FILE points at $ssl_store, expected $expected_store" >&2
          exit 1
        fi

        layer_with_bundle=
        while IFS= read -r layer; do
          if tar -tf "image/$layer" | sed 's|^\./||; s|^/||' | grep -x "''${ssl_cert_file#/}" >/dev/null; then
            layer_with_bundle="$layer"
            break
          fi
        done < <(jq -r '.[0].Layers[]' image/manifest.json)
        if [[ -z "$layer_with_bundle" ]]; then
          echo "FAIL: the image layers do not contain $ssl_cert_file" >&2
          exit 1
        fi
        tar -xf "image/$layer_with_bundle" -C root
        bundle="$PWD/root$ssl_cert_file"
        if [[ ! -f "$bundle" ]]; then
          echo "FAIL: $ssl_cert_file is not a regular file in the image" >&2
          exit 1
        fi

        entries="$PWD/entries.txt"
        : > "$entries"
        while IFS= read -r layer; do
          tar -tf "image/$layer" >> "$entries"
        done < <(jq -r '.[0].Layers[]' image/manifest.json)
        awk '
          {
            entry = $0
            sub(/^\.\//, "", entry)
            sub(/^\//, "", entry)
            count = split(entry, parts, "/")
            if (count >= 3 && parts[1] == "nix" && parts[2] == "store" && parts[3] ~ /-nss-cacert-[0-9]/) {
              print parts[3]
            }
          }
        ' "$entries" | sort -u > "$PWD/stores.txt"
        expected_name="$(basename "$expected_store")"
        if [[ "$(cat "$PWD/stores.txt")" != "$expected_name" ]]; then
          echo "FAIL: the image ships CA store(s) other than $expected_name:" >&2
          cat "$PWD/stores.txt" >&2
          exit 1
        fi

        check-docker-trust-store "$bundle" "${trustedP11kit}/etc/ssl/trust-source/ca-bundle.trust.p11-kit"
        touch "$out"
      '';

  # Exercise the version guard without building the deliberately inconsistent
  # combination (a pre-3.128 version on a certdata.txt that has no G3).
  forcedOldCacert = pkgs.cacert.overrideAttrs (_: {
    version = "3.127";
    __intentionallyOverridingVersion = true;
  });
  oldLikeImage = import ./docker.nix {
    pkgs = pkgs // {
      cacert = forcedOldCacert;
    };
    name = "trust-store-guard-old";
    Entrypoint = [ ];
  };
  guardResults = lib.runTests {
    oldPinAppliesBlacklist = {
      expr = oldLikeImage.cacert.drvPath != forcedOldCacert.drvPath;
      expected = true;
    };
    newPinUsesStockCacert = {
      expr = newImage.cacert.drvPath == pkgs.cacert.drvPath;
      expected = true;
    };
  };
in
{
  dockerTrustStoreNewPin = mkTrustStoreCheck {
    name = "docker-trust-store-new-pin";
    image = newImage;
  };

  dockerTrustStoreOldPin = mkTrustStoreCheck {
    name = "docker-trust-store-old-pin";
    image = oldImage;
  };

  dockerTrustStoreGuard =
    assert lib.assertMsg (guardResults == [ ]) (builtins.toJSON guardResults);
    pkgs.runCommand "check-docker-trust-store-guard" { } ''touch "$out"'';

  # Prove the checker detects an affected root, so a regression in the checker
  # cannot make the other checks pass silently.
  dockerTrustStoreNegative =
    pkgs.runCommand "check-docker-trust-store-negative"
      {
        nativeBuildInputs = with pkgs; [
          bash
          coreutils
          gawk
          gnugrep
          gnused
          openssl
          checkScript
        ];
        AFFECTED_EMSIGN_FINGERPRINTS = affectedFingerprints;
        cleanBundle = "${oldImage.cacert}/etc/ssl/certs/ca-bundle.crt";
        cleanTrustSource = "${oldImage.cacert.p11kit}/etc/ssl/trust-source/ca-bundle.trust.p11-kit";
        blockedBundle = "${oldNixpkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        blockedTrustSource = "${oldNixpkgs.cacert.p11kit}/etc/ssl/trust-source/ca-bundle.trust.p11-kit";
      }
      ''
        set -euo pipefail

        if check-docker-trust-store "$blockedBundle" "$cleanTrustSource"; then
          echo "FAIL: the checker accepted a bundle that contains an affected root" >&2
          exit 1
        fi
        if check-docker-trust-store "$cleanBundle" "$blockedTrustSource"; then
          echo "FAIL: the checker accepted a trust source that trusts an affected root" >&2
          exit 1
        fi
        echo "OK: the checker rejects both affected trust stores"
        touch "$out"
      '';
}
