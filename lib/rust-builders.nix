# rust-builders.nix - Rust cross-compilation builder factory
#
# Provides functions to create Rust builders for different target platforms.
# Supports cross-compilation, static linking, and nightly toolchains.
#
# This is the main entry point for creating Rust builders. It provides
# convenient functions for common platforms and a function to create all
# builders at once.

{
  nixpkgs,
  rust-overlay,
  crane,
  localSystem,
  rustToolchainFile ? null, # Optional path to rust-toolchain.toml
}:

rec {
  # Create a Rust builder for the local platform
  # This is the default builder used for development
  #
  # Arguments:
  #   useRustNightly: Whether to use nightly Rust toolchain (default: false)
  mkLocalBuilder =
    {
      useRustNightly ? false,
    }:
    import ./rust-builder.nix {
      inherit
        nixpkgs
        rust-overlay
        crane
        localSystem
        useRustNightly
        rustToolchainFile
        ;
    };

  # Create a Rust builder for x86_64 Linux with musl (static linking)
  # Used for production Linux deployments
  #
  # Arguments: none
  mkX86_64LinuxBuilder =
    { }:
    import ./rust-builder.nix {
      inherit
        nixpkgs
        rust-overlay
        crane
        localSystem
        rustToolchainFile
        ;
      crossSystem = (import nixpkgs { inherit localSystem; }).lib.systems.examples.musl64;
      isCross = true;
      isStatic = true;
    };

  # Create a Rust builder for aarch64 Linux with musl (static linking)
  # Used for ARM64 Linux deployments (e.g., AWS Graviton)
  #
  # Arguments: none
  mkAarch64LinuxBuilder =
    { }:
    import ./rust-builder.nix {
      inherit
        nixpkgs
        rust-overlay
        crane
        localSystem
        rustToolchainFile
        ;
      crossSystem =
        (import nixpkgs { inherit localSystem; }).lib.systems.examples.aarch64-multiplatform-musl;
      isCross = true;
      isStatic = true;
    };

  # Create a Rust builder for x86_64 macOS
  # Note: Must be built from a Darwin system for proper code signing
  #
  # Arguments: none
  mkX86_64DarwinBuilder =
    { }:
    import ./rust-builder.nix {
      inherit
        nixpkgs
        rust-overlay
        crane
        localSystem
        rustToolchainFile
        ;
      crossSystem = (import nixpkgs { inherit localSystem; }).lib.systems.examples.x86_64-darwin;
      isCross = true;
    };

  # Create a Rust builder for aarch64 macOS (Apple Silicon)
  # Note: Must be built from a Darwin system for proper code signing
  #
  # Arguments: none
  mkAarch64DarwinBuilder =
    { }:
    import ./rust-builder.nix {
      inherit
        nixpkgs
        rust-overlay
        crane
        localSystem
        rustToolchainFile
        ;
      crossSystem = (import nixpkgs { inherit localSystem; }).lib.systems.examples.aarch64-darwin;
      isCross = true;
    };

  # Helper function to create all platform builders at once
  # Returns an attribute set with all available builders
  #
  # This is the most convenient way to get builders for all supported platforms.
  # Each builder can be used to compile packages via builder.callPackage.
  #
  # Arguments: none
  #
  # Returns:
  #   {
  #     local: Local platform builder
  #     localNightly: Local platform builder with nightly toolchain
  #     x86_64-linux: x86_64 Linux static builder
  #     aarch64-linux: aarch64 Linux static builder
  #     x86_64-darwin: x86_64 macOS builder
  #     aarch64-darwin: aarch64 macOS builder
  #   }
  mkAllBuilders =
    { }:
    {
      local = mkLocalBuilder { };
      localNightly = mkLocalBuilder { useRustNightly = true; };
      x86_64-linux = mkX86_64LinuxBuilder { };
      aarch64-linux = mkAarch64LinuxBuilder { };
      x86_64-darwin = mkX86_64DarwinBuilder { };
      aarch64-darwin = mkAarch64DarwinBuilder { };
    };
}
