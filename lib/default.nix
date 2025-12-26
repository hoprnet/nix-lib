# default.nix - Main library entry point
#
# This file exposes all library functions from the nix-lib package.
# It provides a convenient API for creating Rust build environments,
# development shells, Docker images, and utility applications.
#
# Usage:
#   lib = inputs.nix-lib.lib.${system};
#   builders = lib.mkRustBuilders { ... };
#   shell = lib.mkDevShell { ... };

{
  nixpkgs,
  nixpkgs-unstable,
  rust-overlay,
  crane,
  flake-utils,
  system,
}:

let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [
      rust-overlay.overlays.default
    ];
  };

  pkgsUnstable = import nixpkgs-unstable {
    inherit system;
    overlays = [
      rust-overlay.overlays.default
    ];
  };

  lib = pkgs.lib;
in
rec {
  # Source Filtering
  # ---------------
  # Functions for creating filtered source trees for different build contexts

  # Import source filtering utilities
  sources = import ./sources.nix { inherit lib; };

  # Re-export source utilities at top level for convenience
  inherit (sources) mkDepsSrc mkSrc mkTestSrc;

  # Rust Builders
  # ------------
  # Functions for creating Rust build environments with cross-compilation support

  # Create all Rust builders for different platforms
  # Returns: { local, localNightly, x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin }
  mkRustBuilders =
    {
      localSystem ? system,
      rustToolchainFile ? null,
    }:
    let
      buildersLib = import ./rust-builders.nix {
        inherit
          nixpkgs
          rust-overlay
          crane
          localSystem
          rustToolchainFile
          ;
      };
    in
    buildersLib.mkAllBuilders { };

  # Create a single Rust builder for a specific platform
  # Useful when you only need one specific builder
  mkRustBuilder =
    {
      localSystem ? system,
      crossSystem ? localSystem,
      isCross ? false,
      isStatic ? false,
      useRustNightly ? false,
      rustToolchainFile ? null,
    }:
    import ./rust-builder.nix {
      inherit
        nixpkgs
        rust-overlay
        crane
        localSystem
        crossSystem
        isCross
        isStatic
        useRustNightly
        rustToolchainFile
        ;
    };

  # Rust Package Builder
  # -------------------
  # Low-level function for building Rust packages
  # Most users should use builder.callPackage instead

  mkRustPackage = import ./rust-package.nix;

  # Docker Images
  # ------------
  # Functions for creating Docker container images

  # Create a Docker image with optimized layering
  mkDockerImage =
    {
      name,
      Entrypoint,
      Cmd ? [ ],
      env ? [ ],
      extraContents ? [ ],
      basePackages ? null,
      tag ? "latest",
      pkgsLinux ? null, # Optional Linux pkgs for building on macOS
    }:
    let
      # Use provided Linux packages or create new ones
      actualPkgs =
        if pkgsLinux != null then
          pkgsLinux
        else
          import nixpkgs {
            system = "x86_64-linux";
            overlays = [
              rust-overlay.overlays.default
            ];
          };
    in
    import ./docker.nix {
      pkgs = actualPkgs;
      inherit
        name
        Entrypoint
        Cmd
        env
        extraContents
        basePackages
        tag
        ;
    };

  # Docker Security Utilities
  # ------------------------
  # Functions for scanning images and generating SBOMs

  # Import docker security utilities
  dockerSecurity = import ./docker-security.nix { inherit pkgs; };

  # Re-export security utilities at top level for convenience
  inherit (dockerSecurity) mkTrivyScan mkSBOM;

  # Multi-Architecture Support
  # -------------------------
  # Functions for creating multi-arch Docker manifests

  # Import multi-arch utilities
  multiArch = import ./multi-arch.nix { inherit pkgs; };

  # Re-export multi-arch utilities at top level for convenience
  inherit (multiArch) mkMultiArchManifest;

  # Development Shells
  # -----------------
  # Functions for creating development environments

  # Create a development shell with Rust tooling
  mkDevShell =
    {
      rustToolchain ? null,
      rustToolchainFile ? null,
      extraPackages ? [ ],
      shellName ? "Development",
      shellHook ? "",
      treefmtWrapper ? null,
      treefmtPrograms ? [ ],
      includePostgres ? false,
      postgresPackage ? null,
    }:
    import ./shells.nix {
      inherit
        pkgs
        crane
        rustToolchain
        rustToolchainFile
        extraPackages
        shellName
        shellHook
        treefmtWrapper
        treefmtPrograms
        includePostgres
        postgresPackage
        ;
    };

  # Code Formatting
  # --------------
  # Functions for setting up code formatters

  # Create a treefmt configuration
  mkTreefmtConfig =
    {
      config,
      globalExcludes ? [ ],
      extraFormatters ? { },
    }:
    import ./treefmt.nix {
      inherit
        config
        pkgs
        globalExcludes
        extraFormatters
        ;
    };

  # Documentation
  # -------------
  # Functions for generating documentation

  # Create a manual page from a binary using help2man
  mkManPage =
    {
      pname, # Package name for the manual page
      binary, # Binary executable to generate documentation from
      description, # Brief description of the tool
    }:
    pkgs.stdenv.mkDerivation {
      name = "${pname}-man";

      # Tools needed for generating manual pages
      nativeBuildInputs = [ pkgs.help2man ];
      # Ensure OpenSSL libraries are available for binary execution
      LD_LIBRARY_PATH = "${pkgs.openssl.out}/lib:$LD_LIBRARY_PATH";

      buildCommand = ''
        mkdir -p $out/share/man/man1

        # Generate man page using help2man
        help2man \
          --name="${description}" \
          --no-info \
          --output=$out/share/man/man1/${pname}.1 \
          ${binary}/bin/${pname}

        # Compress the man page
        gzip $out/share/man/man1/${pname}.1
      '';
    };

  # Utility Applications
  # -------------------
  # Functions for creating utility scripts and apps

  apps = import ./apps.nix {
    inherit pkgs pkgsUnstable flake-utils;
  };

  # Re-export app utilities at top level for convenience
  inherit (apps)
    mkDockerUploadScript
    mkDockerUploadApp
    mkMultiArchUploadScript
    mkMultiArchUploadApp
    mkCheckApp
    mkAuditApp
    mkFindPortApp
    mkUpdateGithubLabelsApp
    ;
}
