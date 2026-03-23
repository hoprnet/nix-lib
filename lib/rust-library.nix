# rust-library.nix - Rust library crate builder with cross-compilation support
#
# Builds Rust library crates (lib.rs, no main.rs) and installs the compiled
# .rlib and .a artifacts to $out/lib/.
#
# This is a low-level building block. Most users should call it via:
#   builder.callPackage lib.mkRustLibrary { ... }

{
  CARGO_PROFILE ? "release", # Cargo build profile (release/dev/etc)
  cargoExtraArgs ? "", # Additional arguments for cargo build
  cargoToml, # Path to the Cargo.toml file
  craneLib, # Crane library for Rust builds
  depsSrc, # Source tree with only dependencies
  isCross ? false, # Whether this is cross-compilation
  isStatic ? false, # Whether to create static binaries
  lib, # Nixpkgs lib utilities
  libiconv, # Character encoding library
  makeSetupHook, # Nix setup hook creator
  mold, # Fast linker for Rust
  llvmPackages, # LLVM toolchain packages
  pkg-config, # Package configuration tool
  pkgs, # Nixpkgs package set
  rev ? "unknown", # Git revision for version tracking
  runClippy ? false, # Whether to run Clippy linter
  runTests ? false, # Whether to run tests
  src, # Source tree
  stdenv, # Standard environment
  extraBuildInputs ? [ ], # Additional build inputs
  extraNativeBuildInputs ? [ ], # Additional native build inputs
}:
let
  # `hostPlatform` is the cross-compilation output platform
  # `buildPlatform` is the platform we are compiling on
  buildPlatform = stdenv.buildPlatform;
  hostPlatform = stdenv.hostPlatform;

  # The hook is used when building on darwin for non-darwin, where the flags need to be cleaned up.
  darwinSuffixSalt = builtins.replaceStrings [ "-" "." ] [ "_" "_" ] buildPlatform.config;
  targetSuffixSalt = builtins.replaceStrings [ "-" "." ] [ "_" "_" ] hostPlatform.config;
  setupHookDarwin = makeSetupHook {
    name = "darwin-rust-gcc-hook";
    substitutions = { inherit darwinSuffixSalt targetSuffixSalt; };
  } ./setup-hook-darwin.sh;

  crateInfo = craneLib.crateNameFromCargoToml { inherit cargoToml; };
  pname = crateInfo.pname;

  # Cargo uses underscores in artifact filenames even when the crate name uses hyphens
  pnameUnderscore = builtins.replaceStrings [ "-" ] [ "_" ] pname;

  actualCargoProfile =
    if runTests then
      "test"
    else if runClippy then
      "dev"
    else
      CARGO_PROFILE;
  pnameSuffix = if actualCargoProfile == "release" then "" else "-${actualCargoProfile}";
  pnameDeps = if actualCargoProfile == "release" then pname else "${pname}-${actualCargoProfile}";

  version = lib.strings.concatStringsSep "." (
    lib.lists.take 3 (builtins.splitVersion crateInfo.version)
  );

  isDarwinForDarwin = buildPlatform.isDarwin && hostPlatform.isDarwin;
  isDarwinForNonDarwin = buildPlatform.isDarwin && !hostPlatform.isDarwin;

  linuxNativeBuildInputs =
    if buildPlatform.isLinux then
      [
        # mold is only supported on Linux
        mold
      ]
    else
      [ ];
  darwinBuildInputs =
    if isDarwinForDarwin || isDarwinForNonDarwin then
      [
        pkgs.pkgsBuildHost.apple-sdk_15
      ]
    else
      [ ];
  darwinNativeBuildInputs =
    if !isDarwinForDarwin && isDarwinForNonDarwin then [ setupHookDarwin ] else [ ];

  # When cross-compiling, proc-macros are compiled for the build platform but
  # may link against C libraries like openssl.
  crossNativeBuildInputs =
    if isCross then
      [
        pkgs.pkgsBuildHost.openssl
      ]
    else
      [ ];

  buildInputs =
    if isStatic then
      with pkgs.pkgsStatic;
      [
        openssl
        cacert
      ]
    else
      with pkgs;
      [
        openssl
        cacert
      ];

  sharedArgsBase = {
    inherit pname pnameSuffix version;
    CARGO_PROFILE = actualCargoProfile;

    nativeBuildInputs = [
      llvmPackages.bintools
      pkg-config
      libiconv
    ]
    ++ stdenv.extraNativeBuildInputs
    ++ darwinNativeBuildInputs
    ++ linuxNativeBuildInputs
    ++ crossNativeBuildInputs
    ++ extraNativeBuildInputs;
    buildInputs = buildInputs ++ stdenv.extraBuildInputs ++ darwinBuildInputs ++ extraBuildInputs;

    # Build only the lib target for this crate
    cargoExtraArgs = "-p ${pname} --lib ${cargoExtraArgs}";
    strictDeps = true;
    doCheck = false;
    VERGEN_GIT_SHA = rev;
  };

  sharedArgs =
    if runTests then
      sharedArgsBase
      // {
        cargoTestExtraArgs = "--workspace";
        doCheck = true;
        LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.pkgsBuildHost.openssl ];
        RUST_BACKTRACE = "full";
      }
    else if runClippy then
      sharedArgsBase // { cargoClippyExtraArgs = "-- -Dwarnings"; }
    else
      sharedArgsBase;

  defaultArgs = {
    cargoArtifacts = craneLib.buildDepsOnly (
      sharedArgs
      // {
        pname = pnameDeps;
        src = depsSrc;
      }
    );
  };

  args = sharedArgs // defaultArgs;

  builder =
    if runTests then
      craneLib.cargoTest
    else if runClippy then
      craneLib.cargoClippy
    else
      craneLib.buildPackage;
in
builder (
  args
  // {
    inherit src;

    preConfigure = ''
      # respect the amount of available cores for building
      export CARGO_BUILD_JOBS=$NIX_BUILD_CORES
    '';

    # Library crates don't produce executables, so `cargo install` would fail.
    # Instead, copy the compiled .rlib and .a artifacts to $out/lib/.
    #
    # Cargo uses underscores in artifact filenames regardless of the crate name
    # (e.g. crate "my-lib" produces "libmy_lib-<hash>.rlib").
    installPhaseCommand = ''
      mkdir -p $out/lib
      find target -type f \
        \( -name "lib${pnameUnderscore}*.rlib" -o -name "lib${pnameUnderscore}*.a" \) \
        ! -path "*/incremental/*" \
        -exec cp -n {} "$out/lib/" \;
    '';
  }
)
