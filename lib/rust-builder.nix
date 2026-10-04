# rust-builder.nix - Cross-compilation Rust builder factory
#
# Creates Rust build environments for cross-compilation to different platforms.
# Configures toolchains, linkers, and platform-specific settings for building
# Rust applications that can run on various architectures and operating systems.
#
# This is a low-level function. Most users should use rust-builders.nix instead.

{
  crane, # Crane build system for Rust
  crossSystem ? localSystem, # Target system for cross-compilation
  isCross ? false, # Whether this is a cross-compilation build
  isStatic ? false, # Whether to create statically linked binaries
  localSystem, # Host system where compilation occurs
  nixpkgs, # Nixpkgs package set
  nixpkgs-unstable ? nixpkgs, # Unstable nixpkgs (used for cargo-llvm-cov)
  rust-overlay, # Rust toolchain overlay
  useRustNightly ? false, # Whether to use nightly Rust toolchain
  rustToolchainFile ? null, # Optional path to rust-toolchain.toml
  withLlvmTools ? false, # Whether to include llvm-tools for code coverage
}@args:
let
  crossSystem0 = crossSystem;
in
let
  pkgsLocal = import nixpkgs {
    localSystem = args.localSystem;
    overlays = [
      rust-overlay.overlays.default
    ];
  };

  localSystem = pkgsLocal.lib.systems.elaborate args.localSystem;
  crossSystem =
    let
      system = pkgsLocal.lib.systems.elaborate crossSystem0;
    in
    if crossSystem0 == null || pkgsLocal.lib.systems.equals system localSystem then
      localSystem
    else
      system;

  # Native musl packages provide cached compilers when the CPU architecture matches.
  useNativeMusl =
    isStatic && localSystem.isLinux && crossSystem.isMusl && localSystem.system == crossSystem.system;

  pkgs =
    if useNativeMusl then
      (pkgsLocal.pkgsMusl // { inherit (pkgsLocal) pkgsStatic pkgsBuildHost; })
    else
      import nixpkgs {
        inherit localSystem crossSystem;
        overlays = [
          rust-overlay.overlays.default
        ];
      };

  # `buildPlatform` is the local host platform
  # `hostPlatform` is the cross-compilation output platform
  buildPlatform = pkgsLocal.stdenv.buildPlatform;
  hostPlatform = pkgs.stdenv.hostPlatform;

  envCase = triple: pkgsLocal.lib.strings.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] triple);

  cargoTarget =
    if hostPlatform.config == "arm64-apple-darwin" then "aarch64-apple-darwin" else hostPlatform.config;

  llvmToolsExtensions = if withLlvmTools then [ "llvm-tools-preview" ] else [ ];

  rustToolchainFun =
    if useRustNightly then
      p:
      p.rust-bin.selectLatestNightlyWith (
        toolchain:
        toolchain.default.override {
          extensions = llvmToolsExtensions;
        }
      )
    else if rustToolchainFile != null then
      p:
      (p.rust-bin.fromRustupToolchainFile rustToolchainFile).override {
        targets = [ cargoTarget ];
        extensions = llvmToolsExtensions;
      }
    else
      p:
      p.rust-bin.stable.latest.default.override {
        targets = [ cargoTarget ];
        extensions = llvmToolsExtensions;
      };

  # Rust build scripts and proc-macros run with the build host's libc.
  craneLibBase =
    ((crane.mkLib (if useNativeMusl then pkgsLocal else pkgs)).overrideToolchain rustToolchainFun)
    .overrideScope
      (
        _final: _prev:
        pkgsLocal.lib.optionalAttrs useNativeMusl {
          stdenvSelector = _: pkgs.stdenv;
        }
      );

  # When llvm-tools are enabled (for coverage), override cargo-llvm-cov to use
  # the version from nixpkgs-unstable, as the release channel may have it
  # marked as broken or outdated.
  pkgsUnstableLocal = import nixpkgs-unstable {
    localSystem = args.localSystem;
  };
  craneLib =
    if withLlvmTools then
      craneLibBase.overrideScope (
        _final: _prev: {
          cargo-llvm-cov = pkgsUnstableLocal.cargo-llvm-cov;
        }
      )
    else
      craneLibBase;

  # mold is only supported on Linux builds, so falling back to lld for Darwin
  linker = if buildPlatform.isDarwin then "lld" else "mold";

  buildEnvBase = {
    CARGO_BUILD_TARGET = cargoTarget;
    "CARGO_TARGET_${envCase cargoTarget}_LINKER" =
      if useNativeMusl then "${pkgs.stdenv.cc}/bin/cc" else "${pkgs.stdenv.cc.targetPrefix}cc";
    HOST_CC =
      if useNativeMusl then "${pkgsLocal.stdenv.cc}/bin/cc" else "${pkgs.stdenv.cc.nativePrefix}cc";
  }
  // pkgsLocal.lib.optionalAttrs useNativeMusl {
    "CARGO_TARGET_${envCase buildHostTarget}_LINKER" = "${pkgsLocal.stdenv.cc}/bin/cc";
    "CC_${builtins.replaceStrings [ "-" ] [ "_" ] cargoTarget}" = "${pkgs.stdenv.cc}/bin/cc";
    "CXX_${builtins.replaceStrings [ "-" ] [ "_" ] cargoTarget}" = "${pkgs.stdenv.cc}/bin/c++";
  };
  buildEnvCross =
    if isCross then
      {
        # For cross-compilation, don't use mold/lld as it can cause issues
        CARGO_BUILD_RUSTFLAGS = "";
      }
    else
      {
        CARGO_BUILD_RUSTFLAGS = "-C link-arg=-fuse-ld=${linker}";
      };
  buildEnvStatic =
    if isStatic then
      {
        CARGO_BUILD_RUSTFLAGS = "${buildEnvCross.CARGO_BUILD_RUSTFLAGS} -C target-feature=+crt-static";
      }
    else
      { };

  # When cross-compiling, proc-macros (e.g. sqlx-macros) are compiled for the
  # build platform but openssl-sys's build script finds the target platform's
  # openssl via pkg-config. This causes architecture mismatch linker errors.
  # Set target-specific OPENSSL env vars so openssl-sys finds the correct
  # library for each architecture, and disable pkg-config to prevent conflicts.
  targetOpenssl = if isStatic then pkgs.pkgsStatic.openssl else pkgs.openssl;
  buildHostOpenssl = pkgsLocal.openssl;
  buildHostTarget =
    if buildPlatform.config == "arm64-apple-darwin" then
      "aarch64-apple-darwin"
    else
      buildPlatform.config;

  buildEnvOpenssl =
    if isCross then
      {
        OPENSSL_NO_PKG_CONFIG = "1";
        "${envCase cargoTarget}_OPENSSL_LIB_DIR" = "${targetOpenssl.out}/lib";
        "${envCase cargoTarget}_OPENSSL_INCLUDE_DIR" = "${targetOpenssl.dev}/include";
      }
      // pkgsLocal.lib.optionalAttrs (buildHostTarget != cargoTarget) {
        "${envCase buildHostTarget}_OPENSSL_LIB_DIR" = "${buildHostOpenssl.out}/lib";
        "${envCase buildHostTarget}_OPENSSL_INCLUDE_DIR" = "${buildHostOpenssl.dev}/include";
      }
      // (
        if buildHostTarget != cargoTarget then
          {
            "${envCase buildHostTarget}_OPENSSL_LIB_DIR" = "${buildHostOpenssl.out}/lib";
            "${envCase buildHostTarget}_OPENSSL_INCLUDE_DIR" = "${buildHostOpenssl.dev}/include";
          }
        else
          { }
      )
    else
      { };

  buildEnv = buildEnvBase // buildEnvCross // buildEnvStatic // buildEnvOpenssl;

in
{
  callPackage = (
    package: args:
    let
      # Build tools run on the glibc host; target libraries and the compiler use musl.
      packageCall =
        if useNativeMusl then
          pkgs.newScope {
            inherit pkgs;
            inherit (pkgsLocal)
              llvmPackages
              pkg-config
              libiconv
              mold
              makeSetupHook
              html-tidy
              pandoc
              ;
          }
        else
          pkgs.callPackage;
      crate = packageCall package (
        args
        // {
          inherit craneLib isCross isStatic;
        }
      );
    in
    # Override the derivation to add cross-compilation environment variables.
    crate.overrideAttrs (
      previous:
      buildEnv
      // {
        # We also have to override the `cargoArtifacts` derivation with the same changes.
        cargoArtifacts =
          if previous.cargoArtifacts != null then
            previous.cargoArtifacts.overrideAttrs (previous: buildEnv)
          else
            null;
      }
    )
  );
}
