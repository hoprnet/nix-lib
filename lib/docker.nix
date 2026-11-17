# docker.nix - Docker image builder utility
#
# Creates layered Docker images with optimized caching and minimal size.
# Provides a consistent base for all container images.
#
# This builder automatically selects between buildImage (for macOS) and
# buildLayeredImage (for Linux) to work around fakeroot issues on recent macOS.

{
  pkgs, # Nixpkgs package set (should be Linux packages for Docker images)
  name, # Name of the Docker image
  Entrypoint, # Container entrypoint script or binary
  Cmd ? [ ], # Default command to run in container
  env ? [ ], # Additional environment variables for the container
  extraContents ? [ ], # Additional packages to include in image
  basePackages ? null, # Override base packages (default: bash, cacert, coreutils, etc.)
  tag ? "latest", # Docker image tag
  pathsToLink ? [ "/bin" ],
}:
let
  # Library path for essential system libraries
  libPath = pkgs.lib.makeLibraryPath [ pkgs.openssl ];

  # Roots removed from the CA bundle under GHSA-6q48-6c7w-9gw2. The advisory
  # covers eight compromised eMudhra intermediates, all of which chain to
  # emSign ECC Root CA - G3. The other emSign roots stay: Mozilla removed only
  # G3 from certdata.txt in NSS 3.128, and certifi 2026.10.18 removed every
  # emSign root but restored G1, C1, and ECC-C3 in 2026.10.19 because they are
  # not affected. Values are SHA256 fingerprints in lowercase hex without
  # separators; the flake checks and the CI job read this list.
  affectedEmsignRoots = {
    "emSign ECC Root CA - G3" = "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b";
  };

  # CA bundle for SSL verification.
  # Older nixpkgs pins (before nss-cacert 3.128) still ship G3. There the
  # blacklist removes it from the PEM bundle and marks it x-distrusted in the
  # p11-kit output. Newer pins no longer ship G3, and buildcatrust exits with
  # code 3 when a blacklist entry names a certificate that certdata.txt does
  # not contain, so the blacklist applies only below 3.128. The pinned
  # release-26.05 nixpkgs ships nss-cacert 3.131.1 and takes the stock bundle.
  cacert =
    if builtins.compareVersions (pkgs.cacert.version or "0") "3.128" < 0 then
      pkgs.cacert.override { blacklist = builtins.attrNames affectedEmsignRoots; }
    else
      pkgs.cacert;

  # Default base packages included in all Docker images
  # These provide essential runtime dependencies
  defaultBasePackages = with pkgs; [
    bash
    cacert
    coreutils
    dnsutils
    findutils
    iana-etc
    nettools
    util-linux
  ];

  # Use provided base packages or default
  actualBasePackages = if basePackages != null then basePackages else defaultBasePackages;

  # Base packages included in all Docker images
  # These provide essential runtime dependencies
  copyToRoot = pkgs.buildEnv {
    name = "image-root";
    paths = actualBasePackages ++ extraContents;
    pathsToLink = pathsToLink;
  };

  # Default environment variables
  defaultEnv = [
    "NO_COLOR=true" # suppress colored log output
    "RUST_BACKTRACE=full"
    "LD_LIBRARY_PATH=${libPath}"
    "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
  ];

  Env = defaultEnv ++ env;

  # Use buildImage on macOS to avoid fakeroot issues
  # buildLayeredImage requires fakeroot which doesn't work on recent macOS
  buildImageArgs = {
    inherit name copyToRoot tag;
    created = "now";
    config = { inherit Cmd Entrypoint Env; };
  };

  buildLayeredImageArgs = {
    inherit name tag;
    created = "now";
    contents = copyToRoot;
    config = { inherit Cmd Entrypoint Env; };
  };
in
(
  if pkgs.stdenv.hostPlatform.isDarwin then
    pkgs.dockerTools.buildImage buildImageArgs
  else
    pkgs.dockerTools.buildLayeredImage buildLayeredImageArgs
).overrideAttrs
  (previous: {
    # Expose the CA store so the trust store checks can compare the image
    # environment with the derivation it ships, and inspect the p11-kit output.
    passthru = (previous.passthru or { }) // {
      inherit cacert affectedEmsignRoots;
    };
  })
