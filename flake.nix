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

    # Input dependency optimization
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
      crane,
      ...
    }:
    let
      # Expose library for all systems
      # This creates a lib attribute for each system that contains all library functions
      libForSystem = system: import ./lib/default.nix {
        inherit nixpkgs rust-overlay crane flake-utils system;
      };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        lib = libForSystem system;
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            rust-overlay.overlays.default
          ];
        };
      in
      {
        # Example packages showing how to use the library
        # These can be used as reference implementations
        packages = {
          # Example: Create a simple dev shell
          example-shell = lib.mkDevShell {
            shellName = "Example Rust Development";
          };
        };

        # Development shell for working on the library itself
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixfmt-rfc-style
            nil # Nix language server
          ];

          shellHook = ''
            echo "🔧 HOPR Nix Library Development"
            echo "   This is a development environment for the nix-lib itself"
            echo ""
            echo "Available tools:"
            echo "  - nixfmt: Format Nix files"
            echo "  - nil: Nix language server for editors"
            echo ""
          '';
        };

        # Formatter for nix-lib itself
        formatter = pkgs.nixfmt-rfc-style;
      }
    )
    // {
      # Expose library constructor for all systems
      # This allows users to call: nix-lib.lib.${system}
      lib = flake-utils.lib.eachSystemMap flake-utils.lib.allSystems libForSystem;
    };
}
