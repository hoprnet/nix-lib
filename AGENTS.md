# AGENTS.md

This file provides guidance to AI agents when working with code in this
repository.

## Project Overview

This is a Nix flake library providing reusable functions for building Rust
projects with cross-compilation, Docker images, and development environments. It
is designed to be imported as a flake input by other projects.

## Development Commands

### Formatting

```bash
nix fmt
```

### Enter development shell

```bash
nix develop
```

### Build example package

```bash
nix build .#example-shell
```

### Test the library in a consuming project

Use a local path reference in the consuming project's flake:

```nix
inputs.nix-lib.url = "path:../nix-lib";
```

## Architecture

### Library Structure

The library is organized as a flake that exposes functions through
`lib.${system}`. All functions are defined in `lib/` and exported through
`lib/default.nix`.

**Entry point:** `lib/default.nix` imports and re-exports all library functions.

### Core Modules

#### Rust Builders (`rust-builders.nix` + `rust-builder.nix`)

- **Two-layer design**: `rust-builders.nix` provides high-level
  platform-specific builders (local, x86_64-linux, aarch64-linux, etc.), while
  `rust-builder.nix` is the low-level factory that creates individual builders
- **mkAllBuilders**: Returns an attrset with pre-configured builders for all
  supported platforms (local, localNightly, x86_64-linux, aarch64-linux,
  x86_64-darwin, aarch64-darwin)
- **Cross-compilation**: Uses nixpkgs cross-compilation with musl for static
  Linux binaries
- **Toolchain support**: Can use rust-toolchain.toml, nightly toolchain, or
  stable
- **Builder pattern**: Each builder has a `callPackage` method that wraps
  rust-package.nix with the appropriate cross-compilation environment variables
  (CARGO_BUILD_TARGET, linker settings, RUSTFLAGS for static linking)

#### Source Filtering (`sources.nix`)

- **Three source types**:
  - `mkDepsSrc`: Minimal source for dependency resolution (Cargo.toml,
    Cargo.lock, .cargo/config.toml)
  - `mkSrc`: Full source for building (adds .rs files, README.md)
  - `mkTestSrc`: Source with test data
- **Purpose**: Reduces build closure size and improves caching by filtering
  files

#### Rust Package Builder (`rust-package.nix`)

- **Low-level builder**: Called via `builder.callPackage` from consumer projects
- **Multi-mode**: Supports release builds, tests (runTests), clippy (runClippy),
  docs (buildDocs), and benchmarks (runBench)
- **Cargo profiles**: Controlled via CARGO_PROFILE (release/dev/test)
- **Cross-compilation handling**:
  - Patches interpreter for cross-compiled Linux binaries (patchelf)
  - Darwin-specific setup hooks for cross-compilation from macOS
  - Static linking via RUSTFLAGS with crt-static feature
- **Dependencies**: Uses crane's two-phase build (buildDepsOnly for caching
  dependencies, then buildPackage)

#### Docker Images (`docker.nix`)

- Creates OCI-compliant layered images using nixpkgs dockerTools
- Default includes minimal base packages (cacert, tzdata, glibc/musl)
- Must use Linux packages (handles cross-building from Darwin)

#### Development Shells (`shells.nix`)

- Provides Rust toolchain, build tools, and optional PostgreSQL
- Integrates with treefmt for code formatting

#### Utility Apps (`apps.nix`)

- **mkDockerUploadApp**: Builds and uploads Docker images to registries (uses
  skopeo with Google Cloud authentication)
- **mkCheckApp**: Runs nix flake checks
- **mkAuditApp**: Runs cargo-audit for security scanning
- **mkFindPortApp**: Finds available ports for CI testing
- **mkUpdateGithubLabelsApp**: Updates GitHub labels based on crate structure

### Key Design Patterns

1. **Per-system library instantiation**: The flake uses `eachSystemMap` to
   create a library instance for each system, accessible via
   `nix-lib.lib.${system}`

2. **Builder factory pattern**: Builders are created with platform-specific
   settings, then consumers call `builder.callPackage` to build packages with
   those settings

3. **Source separation**: Dependencies and main source are built separately for
   better caching (depsSrc vs src)

4. **Environment variable injection**: Cross-compilation settings are injected
   via overrideAttrs on both the main derivation and cargoArtifacts

5. **Optional toolchain file**: Most functions accept an optional
   `rustToolchainFile` parameter for reproducible Rust versions

## Important Notes

- This is a library, not an application. Changes should maintain backward
  compatibility.
- All platform-specific logic is in `rust-builder.nix` (Darwin build hooks,
  static linking flags, linker selection).
- Docker images must use Linux packages; `mkDockerImage` handles this
  automatically.
- Cross-compilation from macOS to Linux is supported, but macOS targets must be
  built on Darwin for code signing.
- The library exposes both high-level conveniences (`mkRustBuilders`) and
  low-level building blocks (`mkRustBuilder`, `mkRustPackage`).
