# shells.nix - Development shell templates
#
# Provides functions to create comprehensive development environments
# for Rust projects with all necessary tools for development, testing,
# CI/CD, and documentation workflows.

{
  pkgs,
  pkgsUnstable ? pkgs, # Unstable nixpkgs (used for cargo-llvm-cov)
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
  withLlvmTools ? false, # Whether to include llvm-tools for code coverage
}:

let
  buildPlatform = pkgs.stdenv.buildPlatform;

  # Determine cargo target based on platform
  cargoTarget =
    if buildPlatform.config == "arm64-apple-darwin" then
      "aarch64-apple-darwin"
    else
      buildPlatform.config;

  llvmToolsExtensions = if withLlvmTools then [ "llvm-tools-preview" ] else [ ];

  # Use provided Rust toolchain or default from rust-toolchain.toml or stable
  defaultRustToolchain =
    if rustToolchainFile != null then
      (pkgs.rust-bin.fromRustupToolchainFile rustToolchainFile).override {
        targets = [ cargoTarget ];
        extensions = llvmToolsExtensions;
      }
    else
      (pkgs.rust-bin.stable.latest.default).override {
        targets = [ cargoTarget ];
        extensions = llvmToolsExtensions;
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

  # Coverage packages (optional)
  coveragePackages = if withLlvmTools then [ pkgsUnstable.cargo-llvm-cov ] else [ ];

  # CI/CD packages
  ciPackages = with pkgs; [
    lcov # Code coverage
    skopeo # Container image tools
    dive # Docker layer analysis
    go-containerregistry # OCI image manipulation tool (includes crane and gcrane)
    shellcheck # Shell script linting
    shfmt # Shell script formatting
  ];

  # All packages combined
  allPackages =
    corePackages
    ++ ciPackages
    ++ coveragePackages
    ++ postgresPackages
    ++ treefmtPackages
    ++ linuxPackages
    ++ extraPackages;

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
      pkgs.openssl
      pkgs.curl
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.libgcc.lib ]
  );

  CARGO_BUILD_RUSTFLAGS = "-C link-arg=-fuse-ld=${linker}";
}
