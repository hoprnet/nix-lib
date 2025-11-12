# flake.nix - HOPR Nix Library
#
# A reusable library of Nix functions for building Rust projects with
# cross-compilation, Docker images, and development environments.
#
# This library is designed to be used as a flake input in other projects.
#
# Usage in your flake:
#   inputs.nix-lib.url = "github:hoprnet/nix-lib";
#   # or for local development:
#   inputs.nix-lib.url = "path:../nix-lib";
#
# Then in your flake outputs:
#   lib = inputs.nix-lib.lib.${system};
#   builders = lib.mkRustBuilders { ... };

{
  description = "HOPR Nix Library - Reusable Nix functions for Rust projects";

  inputs = {
    # Core Nix ecosystem dependencies
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    flake-utils.url = "github:numtide/flake-utils";

    # Rust toolchain and build system
    rust-overlay.url = "github:oxalica/rust-overlay/master";
    crane.url = "github:ipetkov/crane/v0.21.0";

    # Flake organization and formatting
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    # Input dependency optimization
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
      crane,
      flake-parts,
      treefmt-nix,
      ...
    }:
    let
      # Expose library for all systems
      # This creates a lib attribute for each system that contains all library functions
      libForSystem =
        system:
        import ./lib/default.nix {
          inherit
            nixpkgs
            rust-overlay
            crane
            flake-utils
            system
            ;
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } (
      { flake-parts-lib, ... }:
      let
        inherit (flake-parts-lib) importApply;

        # Create the reusable flake module
        # This wraps treefmt-nix and provides auto-configuration
        flakeModules.default = importApply ./lib/flake-module.nix { inherit inputs; };
      in
      {
        systems = flake-utils.lib.defaultSystems;

        imports = [
          # Import the flakeModules capability
          flake-parts.flakeModules.flakeModules
          # Import treefmt-nix for nix-lib's own formatting (simple config)
          treefmt-nix.flakeModule
        ];

        perSystem =
          {
            config,
            system,
            pkgs,
            ...
          }:
          let
            lib = libForSystem system;
          in
          {
            # Import nixpkgs with overlays
            _module.args.pkgs = import nixpkgs {
              inherit system;
              overlays = [
                rust-overlay.overlays.default
              ];
            };

            # Example packages showing how to use the library
            # packages = {
            #   example-shell = lib.mkDevShell {
            #     shellName = "Example Rust Development";
            #   };
            # };

            # Development shell for working on the library itself
            devShells.default = pkgs.mkShell {
              buildInputs = with pkgs; [
                nixfmt-rfc-style
                nil # Nix language server
                deno # For markdown formatting
              ];

              shellHook = ''
                echo "🔧 HOPR Nix Library Development"
                echo "   This is a development environment for the nix-lib itself"
                echo ""
                echo "Available tools:"
                echo "  - nixfmt: Format Nix files"
                echo "  - deno fmt: Format Markdown files"
                echo "  - nix fmt: Format all files with treefmt"
                echo "  - nil: Nix language server for editors"
                echo ""
              '';
            };

            # Treefmt configuration for formatting
            treefmt = {
              projectRootFile = "flake.nix";
              programs = {
                nixfmt = {
                  enable = true;
                  package = pkgs.nixfmt-rfc-style;
                };
                deno = {
                  enable = true;
                  includes = [ "*.md" ];
                };
                shfmt = {
                  enable = true;
                  indent_size = 2;
                };
                shellcheck = {
                  enable = true;
                };
              };
              settings = {
                global.excludes = [
                  # Nix build outputs
                  "result"
                  "result-*"
                  # Git
                  ".git/**"
                  # Direnv
                  ".direnv/**"
                  # Template files (contain Nix substitution variables)
                  "lib/setup-hook-darwin.sh"
                ];
                formatter = {
                  shfmt = {
                    options = [
                      "-i"
                      "2" # 2 space indentation
                      "-s" # Simplify code
                      "-w" # Write result to file
                    ];
                    includes = [
                      "*.sh"
                      "lib/scripts/*.sh"
                    ];
                  };
                  shellcheck = {
                    includes = [
                      "*.sh"
                      "lib/scripts/*.sh"
                    ];
                  };
                };
              };
            };

            # Formatter is provided by treefmt
            formatter = config.treefmt.build.wrapper;
          };

        flake = {
          # Expose library constructor for all systems
          # This allows users to call: nix-lib.lib.${system}
          lib = flake-utils.lib.eachSystemMap flake-utils.lib.allSystems libForSystem;

          # Export the flake module for use by other flakes
          # Usage: imports = [ inputs.nix-lib.flakeModules.default ];
          inherit flakeModules;
        };
      }
    );
}
