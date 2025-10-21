# shells.nix - Development shell templates
#
# Provides functions to create comprehensive development environments
# for Rust projects with all necessary tools for development, testing,
# CI/CD, and documentation workflows.

{
  pkgs,
  crane,
  rustToolchain ? null, # Optional Rust toolchain override
  rustToolchainFile ? null, # Optional path to rust-toolchain.toml
  extraPackages ? [ ], # Additional packages to include
  shellName ? "Development", # Name shown in shell prompt
  shellHook ? "", # Additional shell hook commands
  treefmtWrapper ? null, # Optional treefmt wrapper
  treefmtPrograms ? [ ], # Optional treefmt programs
  includePostgres ? false, # Whether to include PostgreSQL tools
  postgresPackage ? null, # Optional PostgreSQL package override
}:

let
  buildPlatform = pkgs.stdenv.buildPlatform;

  # Determine cargo target based on platform
  cargoTarget =
    if buildPlatform.config == "arm64-apple-darwin" then
      "aarch64-apple-darwin"
    else
      buildPlatform.config;

  # Use provided Rust toolchain or default from rust-toolchain.toml or stable
  defaultRustToolchain =
    if rustToolchainFile != null then
      (pkgs.pkgsBuildHost.rust-bin.fromRustupToolchainFile rustToolchainFile).override {
        targets = [ cargoTarget ];
      }
    else
      (pkgs.pkgsBuildHost.rust-bin.stable.latest.default).override {
        targets = [ cargoTarget ];
      };

  finalRustToolchain = if rustToolchain != null then rustToolchain else defaultRustToolchain;

  craneLib = (crane.mkLib pkgs).overrideToolchain finalRustToolchain;

  # Platform-specific packages
  linuxPackages = pkgs.lib.optionals pkgs.stdenv.isLinux (
    with pkgs;
    [
      mold # Fast linker (Linux only)
      autoPatchelfHook
    ]
  );

  # PostgreSQL packages (optional)
  postgresPackages =
    if includePostgres then
      [
        (if postgresPackage != null then postgresPackage else pkgs.postgresql_17)
      ]
    else
      [ ];

  # Treefmt packages (optional)
  treefmtPackages = if treefmtWrapper != null then [ treefmtWrapper ] ++ treefmtPrograms else [ ];

  # Core packages for all development environments
  corePackages = with pkgs; [
    # Core build tools
    bash
    coreutils
    curl
    findutils
    gnumake
    jq
    just
    llvmPackages.bintools
    lsof
    openssl
    patchelf
    pkg-config
    time
    which

    # Rust tooling
    cargo-audit # Rust security auditing
  ];

  # CI/CD packages
  ciPackages = with pkgs; [
    lcov # Code coverage
    skopeo # Container image tools
    dive # Docker layer analysis
  ];

  # All packages combined
  allPackages =
    corePackages ++ ciPackages ++ postgresPackages ++ treefmtPackages ++ linuxPackages ++ extraPackages;

  # Shell hook with Rust version display
  defaultShellHook = ''
    echo "🦀 ${shellName} Shell"
    echo "   Rust version: $(rustc --version)"
    echo "   Cargo version: $(cargo --version)"
    echo ""
  '';

  finalShellHook = defaultShellHook + shellHook;

  # mold is only supported on Linux, so falling back to lld on Darwin
  linker = if buildPlatform.isDarwin then "lld" else "mold";
in
craneLib.devShell {
  shellHook = finalShellHook;
  packages = allPackages;

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (
    [
      pkgs.pkgsBuildHost.openssl
      pkgs.pkgsBuildHost.curl
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.pkgsBuildHost.libgcc.lib ]
  );

  CARGO_BUILD_RUSTFLAGS = "-C link-arg=-fuse-ld=${linker}";
}
