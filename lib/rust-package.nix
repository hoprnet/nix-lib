# rust-package.nix - Rust package builder with cross-compilation support
#
# Creates Rust packages with support for cross-compilation, static linking,
# documentation generation, and platform-specific optimizations.
#
# This is a low-level building block that can be used to build Rust packages
# with various configurations and profiles.

{
  buildDocs ? false, # Whether to build documentation
  buildVersion ? null, # Optional final-artifact version exposed as BUILD_VERSION
  CARGO_PROFILE ? "release", # Cargo build profile (release/dev/etc)
  cargoExtraArgs ? "", # Additional arguments for cargo build
  cargoNextestExtraArgs ? "", # Additional arguments for cargo nextest
  cargoTestExtraArgs ? "--workspace", # Additional arguments for cargo test (before --)
  prependPackageName ? true, # When true, prepend -p ${pname} to cargoExtraArgs
  cargoToml, # Path to the Cargo.toml file
  craneLib, # Crane library for Rust builds
  depsSrc, # Source tree with only dependencies
  html-tidy, # HTML validation tool
  isCross ? false, # Whether this is cross-compilation
  isStatic ? false, # Whether to create static binaries
  lib, # Nixpkgs lib utilities
  libiconv, # Character encoding library
  makeSetupHook, # Nix setup hook creator
  mold, # Fast linker for Rust
  llvmPackages, # LLVM toolchain packages
  pandoc, # Universal document converter
  pkg-config, # Package configuration tool
  pkgs, # Nixpkgs package set
  postInstall ? null, # Optional post-install script
  rev ? "unknown", # Git revision for version tracking
  runClippy ? false, # Whether to run Clippy linter
  runCoverage ? false, # Whether to run code coverage
  runNextest ? false, # Whether to run tests with cargo-nextest
  runTests ? false, # Whether to run tests
  testCargoProfile ? "test", # Cargo profile used by test and coverage modes
  runBench ? false, # Whether to run benchmarks
  buildBench ? false, # Whether to compile benchmarks without running (--no-run)
  cargoLlvmCovExtraArgs ? "--lcov --output-path $out", # Extra args for cargo-llvm-cov
  cargoLlvmCovCommand ? "test", # Subcommand for cargo-llvm-cov (test, run, etc.)
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

  # The target interpreter is used to patch the interpreter in the binary
  targetInterpreter =
    if hostPlatform.isLinux && hostPlatform.isx86_64 then
      "/lib64/ld-linux-x86-64.so.2"
    else if hostPlatform.isLinux && hostPlatform.isAarch64 then
      "/lib64/ld-linux-aarch64.so.1"
    else
      "";

  # The hook is used when building on darwin for non-darwin, where the flags
  # need to be cleaned up.
  darwinSuffixSalt = builtins.replaceStrings [ "-" "." ] [ "_" "_" ] buildPlatform.config;
  targetSuffixSalt = builtins.replaceStrings [ "-" "." ] [ "_" "_" ] hostPlatform.config;
  setupHookDarwin = makeSetupHook {
    name = "darwin-rust-gcc-hook";
    substitutions = { inherit darwinSuffixSalt targetSuffixSalt; };
  } ./setup-hook-darwin.sh;

  crateInfo = craneLib.crateNameFromCargoToml { inherit cargoToml; };
  pname = crateInfo.pname;
  actualCargoProfile =
    if runCoverage then
      testCargoProfile
    else if runNextest then
      testCargoProfile
    else if runTests then
      testCargoProfile
    else if runClippy then
      "dev"
    else if buildDocs then
      "dev"
    else if runBench || buildBench then
      "bench"
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

  # When cross-compiling, proc-macros (e.g. sqlx-macros) are compiled for the
  # build platform but may link against C libraries like openssl. Provide the
  # build-platform openssl via nativeBuildInputs so the linker can find
  # architecture-compatible libraries for proc-macro compilation.
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

  opensslLibPath = lib.makeLibraryPath [ pkgs.pkgsBuildHost.openssl ];

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

    cargoExtraArgs =
      if runCoverage then
        "--workspace ${cargoExtraArgs}"
      else if prependPackageName then
        "-p ${pname} ${cargoExtraArgs}"
      else
        cargoExtraArgs;
    strictDeps = true;
    # disable running tests automatically for now
    doCheck = false;
    # set to the revision because during build the Git info is not available
    VERGEN_GIT_SHA = rev;
  }
  // lib.optionalAttrs (buildVersion != null) { BUILD_VERSION = buildVersion; };

  sharedArgs =
    if runCoverage then
      sharedArgsBase
      // {
        inherit cargoLlvmCovCommand;
        # Keep the instrumented dependency artifacts restored from
        # buildDepsOnly. Each Nix build starts from a clean build directory, so
        # there are no stale coverage profiles to retain.
        cargoLlvmCovExtraArgs = "--no-clean ${cargoLlvmCovExtraArgs}";
        # Crane restores cargoArtifacts before cargo-llvm-cov runs. Point both
        # tools at the same directory so the instrumented archive is restored
        # where cargo-llvm-cov expects it.
        CARGO_LLVM_COV_TARGET_DIR = "target/llvm-cov-target";
        CARGO_TARGET_DIR = "target/llvm-cov-target";
        LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.pkgsBuildHost.openssl ];
        RUST_BACKTRACE = "full";
      }
    else if runNextest then
      sharedArgsBase
      // {
        inherit cargoNextestExtraArgs;
        doCheck = true;
        doInstallCargoArtifacts = false;
        LD_LIBRARY_PATH = opensslLibPath;
        RUST_BACKTRACE = "full";
      }
    else if runTests then
      sharedArgsBase
      // {
        inherit cargoTestExtraArgs;
        doCheck = true;
        doInstallCargoArtifacts = false;
        LD_LIBRARY_PATH = opensslLibPath;
        RUST_BACKTRACE = "full";
      }
    else if runClippy then
      sharedArgsBase
      // {
        cargoClippyExtraArgs = "-- -Dwarnings";
        doInstallCargoArtifacts = false;
      }
    else if runBench || buildBench then
      sharedArgsBase
      // {
        LD_LIBRARY_PATH = opensslLibPath;
        RUST_BACKTRACE = "full";
      }
    else
      sharedArgsBase;

  docsArgs = {
    cargoArtifacts = null;
    cargoExtraArgs = ""; # overwrite the default to build all docs
    cargoDocExtraArgs = "--workspace --no-deps";
    RUSTDOCFLAGS = "--enable-index-page -Z unstable-options -D warnings --document-private-items";
    CARGO_TARGET_DIR = "target/";
    LD_LIBRARY_PATH = opensslLibPath;
    postBuild = ''
      ${pandoc}/bin/pandoc -f markdown+hard_line_breaks -t html README.md > readme.html
      mv target/''${CARGO_BUILD_TARGET}/doc target/
      ${html-tidy}/bin/tidy -q --custom-tags yes -i target/doc/index.html > index.html || :
      sed '/<section id="main-content" class="content">/ r readme.html' index.html > target/doc/index.html
      cp index.html target/doc/index-old.html
      rm readme.html index.html
    '';
  };

  depsOnlyArgs =
    builtins.removeAttrs sharedArgs [
      "BUILD_VERSION"
      "VERGEN_GIT_SHA"
      "doInstallCargoArtifacts"
    ]
    // {
      pname = pnameDeps;
      src = depsSrc;
    }
    // lib.optionalAttrs runCoverage {
      # cargo-llvm-cov uses a separate instrumented target directory. Prepare
      # dependencies under the same environment so the final coverage build
      # can reuse them instead of recompiling the full dependency graph.
      nativeBuildInputs = sharedArgs.nativeBuildInputs ++ [ craneLib.cargo-llvm-cov ];
      buildPhaseCargoCommand = ''
        eval "$(cargo llvm-cov show-env --sh)"
        ${
          if cargoLlvmCovCommand == "test" || cargoLlvmCovCommand == "nextest" then
            "cargoWithProfile test ${sharedArgs.cargoExtraArgs} --no-run"
          else
            "cargoWithProfile build ${sharedArgs.cargoExtraArgs}"
        }
      '';
      checkPhaseCargoCommand = "";
    }
    // lib.optionalAttrs (runTests || runNextest) {
      # A single no-run test build prepares normal and dev dependencies,
      # including build-script outputs, without compiling the dependency graph
      # separately through cargo check and cargo build first.
      buildPhaseCargoCommand = "";
      cargoTestExtraArgs = "--no-run --lib";
    }
    // lib.optionalAttrs runClippy {
      # Clippy only reuses cargo check artifacts; a separate cargo build adds
      # no reusable work for the final lint derivation.
      buildPhaseCargoCommand = "cargoWithProfile check ${sharedArgs.cargoExtraArgs}";
    };

  defaultArgs = {
    cargoArtifacts = craneLib.buildDepsOnly depsOnlyArgs;
  };

  args = if buildDocs then sharedArgs // docsArgs else sharedArgs // defaultArgs;

  # cargo-llvm-cov's --profile option becomes the nextest runner profile when
  # using its nextest subcommand. Pass the Cargo build profile through
  # nextest's unambiguous --cargo-profile option instead.
  coverageNextestArgs = lib.optionalAttrs (runCoverage && cargoLlvmCovCommand == "nextest") {
    CARGO_PROFILE = "";
    cargoExtraArgs = "--cargo-profile ${actualCargoProfile} ${args.cargoExtraArgs}";
  };

  mkBench = import ./cargo-bench.nix {
    mkCargoDerivation = craneLib.mkCargoDerivation;
    noRun = buildBench;
  };

  builder =
    if runCoverage then
      craneLib.cargoLlvmCov
    else if runNextest then
      craneLib.cargoNextest
    else if runTests then
      craneLib.cargoTest
    else if runClippy then
      craneLib.cargoClippy
    else if buildDocs then
      craneLib.cargoDoc
    else if runBench || buildBench then
      mkBench
    else
      craneLib.buildPackage;
in
builder (
  args
  // coverageNextestArgs
  // {
    inherit src postInstall;

    preConfigure = ''
      # respect the amount of available cores for building
      export CARGO_BUILD_JOBS=$NIX_BUILD_CORES
    '';

    preFixup = lib.optionalString (isCross && targetInterpreter != "" && !isStatic) ''
      for f in `find $out/bin/ -type f`; do
        echo "patching interpreter for $f to ${targetInterpreter}"
        patchelf --set-interpreter ${targetInterpreter} --output $f.patched $f
        mv $f.patched $f
      done
    '';
  }
)
