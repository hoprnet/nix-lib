# HOPR Nix Library

A reusable library of Nix functions for building Rust projects with
cross-compilation, Docker images, and comprehensive development environments.

## Features

- **Cross-compilation**: Build Rust binaries for multiple platforms (Linux
  x86_64/ARM64, macOS x86_64/ARM64)
- **Static linking**: Create fully static binaries with musl on Linux
- **Library crates**: Build Rust library crates and install `.rlib`/`.a`
  artifacts
- **Docker images**: Build optimized, layered container images
- **Development shells**: Rich development environments with all necessary tools
- **Code formatting**: Integrated treefmt configuration via flake module
- **Man page generation**: Automatic manual page creation from binaries
- **Utility apps**: Docker upload scripts, security audits, and more

## Quick Start

### Add as a Flake Input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    nix-lib.url = "github:hoprnet/nix-lib";
    # For local development:
    # nix-lib.url = "git+file:../nix-lib";

    # Import the flake module for automatic treefmt configuration
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = { self, nixpkgs, nix-lib, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        nix-lib.flakeModules.default  # Provides treefmt integration
      ];

      # Your flake configuration
    };
}
```

### Basic Usage

```nix
let
  lib = nix-lib.lib.${system};

  # Create builders for all platforms
  builders = lib.mkRustBuilders {
    rustToolchainFile = ./rust-toolchain.toml;
  };

  # Create filtered source trees
  sources = {
    main = lib.mkSrc { root = ./.; fs = nixpkgs.lib.fileset; };
    deps = lib.mkDepsSrc { root = ./.; fs = nixpkgs.lib.fileset; };
  };

  # Build a package
  myPackage = builders.local.callPackage lib.mkRustPackage {
    src = sources.main;
    depsSrc = sources.deps;
    cargoToml = ./Cargo.toml;
    rev = "v1.0.0";
  };
in
{
  packages.default = myPackage;
}
```

## API Reference

### Rust Builders

#### `mkRustBuilders`

Create builders for all supported platforms.

```nix
builders = lib.mkRustBuilders {
  rustToolchainFile = ./rust-toolchain.toml; # Optional
};

# Returns:
# {
#   local = <builder>;          # Local platform
#   localNightly = <builder>;   # Local with nightly toolchain
#   x86_64-linux = <builder>;   # x86_64 Linux static
#   aarch64-linux = <builder>;  # ARM64 Linux static
#   x86_64-darwin = <builder>;  # x86_64 macOS
#   aarch64-darwin = <builder>; # ARM64 macOS (Apple Silicon)
# }
```

#### `mkRustBuilder`

Create a single builder for a specific platform.

```nix
builder = lib.mkRustBuilder {
  localSystem = "x86_64-linux";
  crossSystem = "aarch64-linux";
  isCross = true;
  isStatic = true;
  rustToolchainFile = ./rust-toolchain.toml;
};
```

### Source Filtering

#### `mkSrc`

Create a filtered source tree for building.

```nix
src = lib.mkSrc {
  root = ./.;
  fs = nixpkgs.lib.fileset;
  extraFiles = [ ./config.yaml ];        # Optional
  extraExtensions = [ "graphql" "sql" ]; # Optional
};
```

#### `mkDepsSrc`

Create a minimal source tree for dependency resolution.

```nix
depsSrc = lib.mkDepsSrc {
  root = ./.;
  fs = nixpkgs.lib.fileset;
  extraFiles = [ ./custom.toml ]; # Optional
};
```

#### `mkTestSrc`

Create a source tree including test data.

```nix
testSrc = lib.mkTestSrc {
  root = ./.;
  fs = nixpkgs.lib.fileset;
  extraFiles = [ ./test-data ];
};
```

### Rust Packages

#### `mkRustPackage`

Build a Rust package (typically called via `builder.callPackage`).

```nix
package = builder.callPackage lib.mkRustPackage {
  src = sources.main;
  depsSrc = sources.deps;
  cargoToml = ./Cargo.toml;
  rev = "v1.0.0";
  CARGO_PROFILE = "release"; # Optional: release/dev/test
  runTests = false;          # Optional: run tests
  cargoTestExtraArgs = "--workspace";  # Optional: args for cargo test
  prependPackageName = true;           # Optional: prepend -p ${pname} to cargo args
  runClippy = false;         # Optional: run clippy
  buildDocs = false;         # Optional: build documentation
  runBench = false;          # Optional: run benchmarks
  buildBench = false;        # Optional: compile benchmarks (--no-run)
};
```

##### Splitting Unit and Integration Tests

Tests can be split into separate Nix derivations for independent caching and
execution. The examples below assume `sources.test` was created with
`lib.mkTestSrc` (see [Source Filtering](#source-filtering)).

```nix
# Unit tests only (cargo test --lib)
unit-tests = builder.callPackage lib.mkRustPackage {
  src = sources.test;
  depsSrc = sources.deps;
  cargoToml = ./Cargo.toml;
  rev = "v1.0.0";
  runTests = true;
  cargoTestExtraArgs = "--lib";
};

# Integration tests only (cargo test --test '*')
integration-tests = builder.callPackage lib.mkRustPackage {
  src = sources.test;
  depsSrc = sources.deps;
  cargoToml = ./Cargo.toml;
  rev = "v1.0.0";
  runTests = true;
  cargoTestExtraArgs = "--test '*' -- --test-threads=1";
};
```

These can be exposed as packages for `nix build` or as checks for
`nix flake check`.

#### `mkRustLibrary`

Build a Rust library crate (a crate with `lib.rs` and no `main.rs`). The
compiled `.rlib` and `.a` artifacts are installed to `$out/lib/`. Call via
`builder.callPackage`.

```nix
myLib = builder.callPackage lib.mkRustLibrary {
  src = sources.main;
  depsSrc = sources.deps;
  cargoToml = ./Cargo.toml;
  rev = "v1.0.0";
  CARGO_PROFILE = "release"; # Optional: release/dev/test (default: release)
  runTests = false;          # Optional: run tests
  runClippy = false;         # Optional: run clippy
};

# Artifacts are available at:
# ${myLib}/lib/libmy_lib-<hash>.rlib
# ${myLib}/lib/libmy_lib.a          (if a C-compatible static lib was produced)
```

Cross-compilation works exactly as with `mkRustPackage`:

```nix
myLibAmd64 = builders."x86_64-linux".callPackage lib.mkRustLibrary {
  src = sources.main;
  depsSrc = sources.deps;
  cargoToml = ./Cargo.toml;
  rev = "v1.0.0";
};
```

### Docker Images

#### `mkDockerImage`

Create an optimized Docker image.

```nix
image = lib.mkDockerImage {
  name = "my-app";
  tag = "latest";
  Entrypoint = [ "${myPackage}/bin/my-app" ];
  Cmd = [ "--help" ];
  env = [ "RUST_LOG=info" ];
  extraContents = [ pkgs.curl ];
};
```

### Development Shells

#### `mkDevShell`

Create a development environment.

```nix
devShell = lib.mkDevShell {
  rustToolchainFile = ./rust-toolchain.toml;
  shellName = "My Project";
  extraPackages = [ pkgs.postgresql ];
  includePostgres = true;
  shellHook = ''
    echo "Welcome to my project!"
  '';
};
```

### Code Formatting

The library provides a flake-parts module that automatically configures treefmt.

#### Using the Flake Module

Import `nix-lib.flakeModules.default` to get automatic treefmt configuration:

```nix
{
  imports = [ nix-lib.flakeModules.default ];

  perSystem = { ... }: {
    nix-lib.treefmt = {
      globalExcludes = [ "generated/*" "vendor/*" ];
      extraFormatters = {
        settings.formatter.custom = {
          command = "my-formatter";
          includes = [ "*.custom" ];
        };
      };
    };
  };
}
```

The module automatically configures formatters for:

- Rust (rustfmt with nightly)
- Nix (nixfmt)
- TOML (taplo with alignment and sorting)
- YAML (yamlfmt)
- JSON and Markdown (prettier)
- Shell scripts (shfmt)
- Python (ruff)

#### `mkTreefmtConfig`

Low-level function for manual treefmt configuration (used internally by the
module).

```nix
treefmt = lib.mkTreefmtConfig {
  inherit config; # From flake-parts
  globalExcludes = [ "generated/*" ];
  extraFormatters = {
    # Custom formatter configuration
  };
};
```

### Utility Applications

#### `mkCheckApp`

Create an app for running Nix checks.

```nix
apps.check = lib.mkCheckApp { system = "x86_64-linux"; };

# Usage:
# nix run .#check           # Run all checks
# nix run .#check my-check  # Run specific check
```

#### `mkAuditApp`

Create a cargo audit app for security scanning. Supports custom toolchains.

```nix
# Basic usage
apps.audit = lib.mkAuditApp { };

# With custom toolchain file
apps.audit = lib.mkAuditApp {
  rustToolchainFile = ./rust-toolchain.toml;
};
```

### Documentation

#### `mkManPage`

Generate a manual page from a binary using help2man.

```nix
manPage = lib.mkManPage {
  pname = "my-app";
  binary = myPackage;
  description = "My application description";
};

# The man page will be in:
# ${manPage}/share/man/man1/my-app.1.gz
```

## Complete Example

See the [examples/rust-app](examples/rust-app) directory for a complete example
demonstrating all features of this library.

Quick example:

### Basic Example

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    nix-lib.url = "path:../nix-lib";
    crane.url = "github:ipetkov/crane/v0.21.0";
  };

  outputs = { self, nixpkgs, nix-lib, crane, ... }:
    let
      system = "x86_64-linux";
      lib = nix-lib.lib.${system};

      builders = lib.mkRustBuilders {
        rustToolchainFile = ./rust-toolchain.toml;
      };

      sources = {
        main = lib.mkSrc { root = ./.; fs = nixpkgs.lib.fileset; };
        deps = lib.mkDepsSrc { root = ./.; fs = nixpkgs.lib.fileset; };
      };

      myApp = builders.local.callPackage lib.mkRustPackage {
        src = sources.main;
        depsSrc = sources.deps;
        cargoToml = ./Cargo.toml;
        rev = "v1.0.0";
      };

      myImage = lib.mkDockerImage {
        name = "my-app";
        Entrypoint = [ "${myApp}/bin/my-app" ];
      };

    in
    {
      packages.default = myApp;
      packages.docker = myImage;

      devShells.default = lib.mkDevShell {
        shellName = "My App Development";
      };

    };
}
```

### Complete Example with Security

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    nix-lib.url = "github:hoprnet/nix-lib";
  };

  outputs = { self, nixpkgs, nix-lib, ... }:
    let
      # Support multiple systems
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    in
    forAllSystems (system:
      let
        lib = nix-lib.lib.${system};

        # Create builders for cross-compilation
        builders = lib.mkRustBuilders {
          rustToolchainFile = ./rust-toolchain.toml;
        };

        # Source filtering
        sources = {
          main = lib.mkSrc { root = ./.; fs = nixpkgs.lib.fileset; };
          deps = lib.mkDepsSrc { root = ./.; fs = nixpkgs.lib.fileset; };
        };

        # Build for x86_64 Linux
        appAmd64 = builders.x86_64-linux.callPackage lib.mkRustPackage {
          src = sources.main;
          depsSrc = sources.deps;
          cargoToml = ./Cargo.toml;
          rev = "v1.0.0";
        };

        # Build for ARM64 Linux
        appArm64 = builders.aarch64-linux.callPackage lib.mkRustPackage {
          src = sources.main;
          depsSrc = sources.deps;
          cargoToml = ./Cargo.toml;
          rev = "v1.0.0";
        };

        # Docker images for each architecture
        imageAmd64 = lib.mkDockerImage {
          name = "my-app";
          tag = "latest";
          Entrypoint = [ "${appAmd64}/bin/my-app" ];
          pkgsLinux = nixpkgs.legacyPackages.x86_64-linux;
        };

        imageArm64 = lib.mkDockerImage {
          name = "my-app";
          tag = "latest";
          Entrypoint = [ "${appArm64}/bin/my-app" ];
          pkgsLinux = nixpkgs.legacyPackages.aarch64-linux;
        };

        in
        {
        packages = {
          default = appAmd64;
          amd64 = appAmd64;
          arm64 = appArm64;
          docker-amd64 = imageAmd64;
          docker-arm64 = imageArm64;
        };

        apps = {
          # Security audit
          audit = lib.mkAuditApp {
            rustToolchainFile = ./rust-toolchain.toml;
          };
        };

        devShells.default = lib.mkDevShell {
          shellName = "My App Development";
          rustToolchainFile = ./rust-toolchain.toml;
        };
      }
    );
}
```

### Library Crate Example

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    nix-lib.url = "github:hoprnet/nix-lib";
  };

  outputs = { self, nixpkgs, nix-lib, ... }:
    let
      system = "x86_64-linux";
      lib = nix-lib.lib.${system};

      builders = lib.mkRustBuilders {
        rustToolchainFile = ./rust-toolchain.toml;
      };

      sources = {
        main = lib.mkSrc { root = ./.; fs = nixpkgs.lib.fileset; };
        deps = lib.mkDepsSrc { root = ./.; fs = nixpkgs.lib.fileset; };
      };

      # Build the library for the local platform
      myLib = builders.local.callPackage lib.mkRustLibrary {
        src = sources.main;
        depsSrc = sources.deps;
        cargoToml = ./Cargo.toml;
        rev = "v1.0.0";
      };

      # Cross-compile the same library for x86_64 Linux (static)
      myLibAmd64 = builders."x86_64-linux".callPackage lib.mkRustLibrary {
        src = sources.main;
        depsSrc = sources.deps;
        cargoToml = ./Cargo.toml;
        rev = "v1.0.0";
      };

    in
    {
      packages = {
        default = myLib;
        amd64 = myLibAmd64;
      };

      # Run clippy on the library
      checks.clippy = builders.local.callPackage lib.mkRustLibrary {
        src = sources.main;
        depsSrc = sources.deps;
        cargoToml = ./Cargo.toml;
        rev = "v1.0.0";
        runClippy = true;
      };
    };
}
```

### CI/CD Integration Example

```bash
# Build a Docker image — creates ./result symlink to the .tar.gz in the Nix store
nix build .#docker-amd64

# Load into the local Docker daemon for testing
docker load < ./result

# Push to a registry with skopeo (no Docker daemon required)
skopeo copy \
  --dest-creds "$REGISTRY_USER:$REGISTRY_TOKEN" \
  docker-archive:./result \
  docker://ghcr.io/org/my-app:latest

# Run unit tests (built by Nix, fully cached)
nix build -L .#unit-tests

# Run integration tests (built by Nix, fully cached)
nix build -L .#integration-tests

# Run unit tests with nightly toolchain
nix build -L .#unit-tests-nightly
```

## Platform Support

| Platform       | Native | Cross-compile | Static Linking |
| -------------- | ------ | ------------- | -------------- |
| x86_64-linux   | ✓      | ✓             | ✓ (musl)       |
| aarch64-linux  | ✓      | ✓             | ✓ (musl)       |
| x86_64-darwin  | ✓      | ✓*            | -              |
| aarch64-darwin | ✓      | ✓*            | -              |

*Note: macOS cross-compilation must be done from a Darwin system for proper code
signing.

## Development

To work on the library itself:

```bash
cd nix-lib
nix develop
```

Format code:

```bash
nix fmt
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please ensure all Nix files are properly formatted with
`nix fmt`.
