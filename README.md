# HOPR Nix Library

A reusable library of Nix functions for building Rust projects with cross-compilation, Docker images, and comprehensive development environments.

## Features

- **Cross-compilation**: Build Rust binaries for multiple platforms (Linux x86_64/ARM64, macOS x86_64/ARM64)
- **Static linking**: Create fully static binaries with musl on Linux
- **Docker images**: Build optimized, layered container images
- **Development shells**: Rich development environments with all necessary tools
- **Code formatting**: Integrated treefmt configuration for multiple languages
- **Utility apps**: Docker upload scripts, security audits, and more

## Quick Start

### Add as a Flake Input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    nix-lib.url = "github:hoprnet/nix-lib";
    # For local development:
    # nix-lib.url = "path:../nix-lib";
  };

  outputs = { self, nixpkgs, nix-lib, ... }: {
    # Your flake outputs
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
  runClippy = false;         # Optional: run clippy
  buildDocs = false;         # Optional: build documentation
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

#### `mkTreefmtConfig`

Create a treefmt configuration (requires treefmt-nix flake module).

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

#### `mkDockerUploadApp`

Create an app for building and uploading Docker images.

```nix
apps.upload-image = lib.mkDockerUploadApp myDockerImage;

# Usage:
# GOOGLE_ACCESS_TOKEN=... IMAGE_TARGET=gcr.io/project/image:tag nix run .#upload-image
```

#### `mkCheckApp`

Create an app for running Nix checks.

```nix
apps.check = lib.mkCheckApp { system = "x86_64-linux"; };

# Usage:
# nix run .#check           # Run all checks
# nix run .#check my-check  # Run specific check
```

#### `mkAuditApp`

Create a cargo audit app for security scanning.

```nix
apps.audit = lib.mkAuditApp;

# Usage:
# nix run .#audit
```

## Complete Example

See the [blokli](../blokli) project for a complete real-world example of using this library.

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

      apps.upload = lib.mkDockerUploadApp myImage;
    };
}
```

## Platform Support

| Platform | Native | Cross-compile | Static Linking |
|----------|--------|---------------|----------------|
| x86_64-linux | ✓ | ✓ | ✓ (musl) |
| aarch64-linux | ✓ | ✓ | ✓ (musl) |
| x86_64-darwin | ✓ | ✓* | - |
| aarch64-darwin | ✓ | ✓* | - |

*Note: macOS cross-compilation must be done from a Darwin system for proper code signing.

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

Contributions welcome! Please ensure all Nix files are properly formatted with `nix fmt`.
