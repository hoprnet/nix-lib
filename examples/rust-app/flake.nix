{
  description = "Example Rust application using HOPR Nix Library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";

    # Use the parent directory (nix-lib) as the library source
    # In a real project, you would use:
    # nix-lib.url = "github:hoprnet/nix-lib";
    nix-lib.url = "path:../..";

    # Optional: Add flake-parts for better flake organization
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-lib,
      flake-parts,
      treefmt-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
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
          # Import the nix-lib for this system
          lib = nix-lib.lib.${system};

          # Create builders for all supported platforms
          builders = lib.mkRustBuilders { };

          # Create filtered source trees
          sources = {
            main = lib.mkSrc {
              root = ./.;
              fs = nixpkgs.lib.fileset;
            };
            deps = lib.mkDepsSrc {
              root = ./.;
              fs = nixpkgs.lib.fileset;
            };
            test = lib.mkTestSrc {
              root = ./.;
              fs = nixpkgs.lib.fileset;
            };
          };

          # Get git revision (or use "dev" for local builds)
          rev = self.rev or "dev";

          # Build the package for different platforms
          mkPackage =
            builder: profile:
            builder.callPackage lib.mkRustPackage {
              src = sources.main;
              depsSrc = sources.deps;
              cargoToml = ./Cargo.toml;
              inherit rev;
              CARGO_PROFILE = profile;
            };

          # Main package (local platform, release build)
          rust-app = mkPackage builders.local "release";

          # Create Docker image for the application
          dockerImage = lib.mkDockerImage {
            name = "rust-app";
            tag = "latest";
            Entrypoint = [ "${rust-app}/bin/rust-app" ];
            Cmd = [ ];
            env = [
              "RUST_LOG=info"
            ];
          };

        in
        {
          # Packages that can be built with `nix build`
          packages = {
            # Default package
            default = rust-app;

            # Development build (faster, includes debug symbols)
            dev = mkPackage builders.local "dev";

            # Cross-compiled packages
            x86_64-linux = mkPackage builders.x86_64-linux "release";
            aarch64-linux = mkPackage builders.aarch64-linux "release";
            x86_64-darwin = mkPackage builders.x86_64-darwin "release";
            aarch64-darwin = mkPackage builders.aarch64-darwin "release";

            # Docker image
            docker = dockerImage;
          };

          # Development shell
          devShells.default = lib.mkDevShell {
            shellName = "Rust App Example";
            extraPackages = with pkgs; [
              # Additional development tools
              cargo-edit
              cargo-watch
            ];
            shellHook = ''
              echo "🦀 Rust App Development Environment"
              echo ""
              echo "Available commands:"
              echo "  cargo build    - Build the application"
              echo "  cargo test     - Run tests"
              echo "  cargo run      - Run the application"
              echo "  nix build      - Build with Nix"
              echo ""
            '';
            treefmtWrapper = config.treefmt.build.wrapper;
          };

          # Apps that can be run with `nix run`
          apps = {
            # Run the application
            default = {
              type = "app";
              program = "${rust-app}/bin/rust-app";
            };

            # Upload Docker image to registry
            upload-docker = lib.mkDockerUploadApp dockerImage;

            # Run security audit
            audit = lib.mkAuditApp { };
          };

          # Checks that run with `nix flake check`
          checks = {
            # Run tests
            tests = builders.local.callPackage lib.mkRustPackage {
              src = sources.test;
              depsSrc = sources.deps;
              cargoToml = ./Cargo.toml;
              inherit rev;
              runTests = true;
            };

            # Run clippy linter
            clippy = builders.local.callPackage lib.mkRustPackage {
              src = sources.main;
              depsSrc = sources.deps;
              cargoToml = ./Cargo.toml;
              inherit rev;
              runClippy = true;
            };

            # Formatting check
            formatting = config.treefmt.build.check self;
          };

          # Code formatting configuration
          treefmt = lib.mkTreefmtConfig {
            inherit config;
            globalExcludes = [
              "target/**"
              "*.lock"
            ];
          };
        };
    };
}
