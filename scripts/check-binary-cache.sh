#!/usr/bin/env bash
#
# check-binary-cache.sh - Verify that critical packages are cached on cache.nixos.org
#
# Prevents Dependabot / flake updates from bumping nixpkgs or nixpkgs-unstable
# to revisions where packages that hoprnet consumers rely on are missing from
# the Nix binary cache.
#
# Checks both x86_64-linux and aarch64-linux store paths.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

CACHE_URL="https://cache.nixos.org"
SYSTEMS=("x86_64-linux" "aarch64-linux")

echo "Evaluating package store paths across systems: ${SYSTEMS[*]}..."

# shellcheck disable=SC2016
EXPR='
let
  f = builtins.getFlake (toString ./.);
  collectForSystem = system:
    let
      lib = f.lib.${system};
      pkgs = f.inputs.nixpkgs.legacyPackages.${system};
      unstable = f.inputs.nixpkgs-unstable.legacyPackages.${system};
      tools = [
        # Unstable tools used by dev shells / CI / release workflows
        [ "unstable.cargo-llvm-cov" unstable.cargo-llvm-cov ]
        [ "unstable.cargo-audit" unstable.cargo-audit ]
        [ "unstable.cargo-deny" unstable.cargo-deny ]
        [ "unstable.cargo-semver-checks" unstable.cargo-semver-checks ]
        [ "unstable.cargo-release" unstable.cargo-release ]
        [ "unstable.cacert" unstable.cacert ]

        # Nixpkgs core tools & libraries
        [ "pkgs.cacert" pkgs.cacert ]
        [ "pkgs.bash" pkgs.bash ]
        [ "pkgs.coreutils" pkgs.coreutils ]
        [ "pkgs.curl" pkgs.curl ]
        [ "pkgs.jq" pkgs.jq ]
        [ "pkgs.just" pkgs.just ]
        [ "pkgs.git" pkgs.git ]
        [ "pkgs.ripgrep" pkgs.ripgrep ]
        [ "pkgs.zizmor" pkgs.zizmor ]
        [ "pkgs.cargo-machete" pkgs.cargo-machete ]
        [ "pkgs.cargo-shear" pkgs.cargo-shear ]
        [ "pkgs.cargo-insta" pkgs.cargo-insta ]
        [ "pkgs.gh" pkgs.gh ]
        [ "pkgs.openssl" pkgs.openssl ]
        [ "pkgs.pkg-config" pkgs.pkg-config ]
        [ "pkgs.patchelf" pkgs.patchelf ]
        [ "pkgs.findutils" pkgs.findutils ]
        [ "pkgs.gnumake" pkgs.gnumake ]
        [ "pkgs.which" pkgs.which ]

        # Docker base image packages
        [ "docker.dnsutils" pkgs.dnsutils ]
        [ "docker.iana-etc" pkgs.iana-etc ]
        [ "docker.nettools" pkgs.nettools ]
        [ "docker.util-linux" pkgs.util-linux ]
      ] ++ (map (name: [ "ciTools.${name}" pkgs.${name} ]) lib.ciTools.names)
        ++ (map (name: [ "qualityTools.${name}" pkgs.${name} ]) lib.qualityTools.names);
    in
      map (t: { name = "${system}:${builtins.elemAt t 0}"; path = toString (builtins.elemAt t 1).outPath; }) tools;
in
  builtins.concatLists (map collectForSystem [ "x86_64-linux" "aarch64-linux" ])
'

JSON_OUTPUT="$(nix eval --json --expr "$EXPR" --impure)"

python3 - <<PY
import json
import subprocess
import sys

raw = '''$JSON_OUTPUT'''
items = json.loads(raw)
cache_url = "$CACHE_URL"

print(f"Checking {len(items)} package store paths against {cache_url}...")

missing = []
for item in items:
    name = item["name"]
    path = item["path"]
    res = subprocess.run(["nix", "path-info", "--store", cache_url, path], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"  ❌ MISSING: {name:42} {path}")
        missing.append((name, path))

if missing:
    print(f"\n❌ FAILED: {len(missing)} package(s) not found on {cache_url}!")
    print("This bump would force downstream repositories to compile these tools from source or fail CI.")
    sys.exit(1)

print(f"\n✅ SUCCESS: All {len(items)} packages are cached on {cache_url}.")
PY
