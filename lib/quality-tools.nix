# quality-tools.nix - Code-quality metric tools
#
# Ships the tools the code-quality `measure` workflow shells out to, so a dev
# shell built with mkDevShell has them on PATH by default (see the
# `includeQualityTools` option in shells.nix). Tools nixpkgs packages are pulled
# by attribute name; the few it does not package are built here from crates.io /
# npm, pinned to versions verified against the skill's metric scripts.
#
# Only aarch64-darwin and x86_64-linux are supported for the built tools (jscpd
# ships prebuilt per-platform binaries) — other systems throw rather than
# silently picking a wrong binary.
rec {
  # Tools present in nixpkgs, pulled by attribute name.
  names = [
    "rust-code-analysis" # cognitive/mi/halstead/loc/nom/hotspots (rust-code-analysis-cli)
    "cargo-public-api" # api surface
    "cargo-modules" # orphans + fan-in/out
    "cargo-machete" # unused dependencies (source/manifest scan)
    "cargo-shear" # unused dependencies (compiler-assisted; sibling of machete)
    "cargo-mutants" # mutation testing
    "cargo-llvm-cov" # coverage for CRAP
    "ripgrep" # unsafe density
    "jq" # JSON plumbing in the metric scripts
    "git" # churn for hotspots
  ];

  # Tools nixpkgs does not package, built from crates.io / npm. cargoHash values
  # are the vendored-dependency hashes (independent of the nixpkgs revision).
  mkCustom =
    pkgs:
    let
      buildCargo =
        {
          pname,
          version,
          srcHash,
          cargoHash,
        }:
        pkgs.rustPlatform.buildRustPackage {
          inherit pname version cargoHash;
          src = pkgs.fetchCrate {
            inherit pname version;
            hash = srcHash;
          };
          doCheck = false;
        };

      # jscpd's crates.io-free release resolves, via npm optionalDependencies, to
      # a prebuilt per-platform binary package with no further deps — fetching
      # that binary sidesteps a Node/rustc toolchain build entirely.
      jscpdByPlatform = {
        "aarch64-darwin" = {
          url = "https://registry.npmjs.org/jscpd-darwin-arm64/-/jscpd-darwin-arm64-5.2.0.tgz";
          hash = "sha512-QnEDfTH2MymizVHiEQpqfYEj63k1DW7QC0QBZoevh+o/iHQrHxKlgrakMysUIwIJlnmvqPB6iP/G3dBpFmnmeQ==";
        };
        "x86_64-linux" = {
          url = "https://registry.npmjs.org/jscpd-linux-x64-gnu/-/jscpd-linux-x64-gnu-5.2.0.tgz";
          hash = "sha512-p88BpA5QzyZzyF8uYeVCz9ZBoZYg8s6AwcDc3NkIDNTbrrF0sKqgGjclGWAoJvYAiGExiFNqV768pVHsE//l0Q==";
        };
      };
      jscpdInfo =
        jscpdByPlatform.${pkgs.stdenv.hostPlatform.system}
          or (throw "jscpd: no prebuilt binary pinned for ${pkgs.stdenv.hostPlatform.system}");
    in
    {
      # Per-function risk = cyclomatic complexity x how untested it is.
      cargo-crap = buildCargo {
        pname = "cargo-crap";
        version = "0.5.0";
        srcHash = "sha256-5RhRFUh1w5/yItkmc3Vk1B6oyrmzKKl6EEZ3v0aBLwk=";
        cargoHash = "sha256-vPdzZIeXsjICz5icPrr2LQ4GrcMSZe2nRa65iyzLH7Q=";
      };
      # Hidden private-implementation bloat behind a file's public surface.
      cargo-iceberg4rust = buildCargo {
        pname = "cargo-iceberg4rust";
        version = "0.3.0";
        srcHash = "sha256-1T5L6qNRT5pczwPRcLw/38mc13s5P/W8VKbuP1IwETM=";
        cargoHash = "sha256-ksZYzvbfoAkKL0TUx2YU+GZg5q3iX5Nm712xyzfC5wU=";
      };
      # Martin's Ca/Ce/I/A/D per crate.
      cargo-anatomy = buildCargo {
        pname = "cargo-anatomy";
        version = "0.7.7";
        srcHash = "sha256-g/QH1QVYW06sM8RvixAMpJw4kRi8qVGu//s2SOAPziE=";
        cargoHash = "sha256-Cdm25jK/5xpMhpQdYtfwkBqyWMK94twX9iGjJGdOlSw=";
      };
      # Near-duplicate code detection.
      jscpd = pkgs.stdenvNoCC.mkDerivation {
        pname = "jscpd";
        version = "5.2.0";
        src = pkgs.fetchurl { inherit (jscpdInfo) url hash; };
        sourceRoot = ".";
        unpackCmd = "tar xzf $curSrc";
        dontBuild = true;
        installPhase = ''
          mkdir -p $out/bin
          install -m755 package/bin/jscpd $out/bin/jscpd
        '';
      };
    };

  # The full package list for a given pkgs: nixpkgs tools by name plus the
  # locally-built ones.
  mkPackages =
    pkgs: (map (n: builtins.getAttr n pkgs) names) ++ (builtins.attrValues (mkCustom pkgs));
}
