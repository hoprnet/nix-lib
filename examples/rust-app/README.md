# Rust App Example

This example demonstrates how to use the HOPR Nix Library to build a Rust
application with cross-compilation, Docker images, and development environments.

## Features Demonstrated

- ✅ Building Rust packages with Nix
- ✅ Cross-compilation to multiple platforms
- ✅ Creating Docker images
- ✅ Development shells with tooling
- ✅ Code formatting with treefmt
- ✅ Running tests and clippy checks
- ✅ Security audits with cargo-audit
- ✅ Source filtering for optimized builds

## Quick Start

### Build the application

```bash
# Build for your local platform
nix build

# Run the application
nix run

# Or run directly
./result/bin/rust-app
```

### Cross-compile to other platforms

```bash
# Build for x86_64 Linux (static binary)
nix build .#x86_64-linux

# Build for ARM64 Linux (static binary)
nix build .#aarch64-linux

# Build for x86_64 macOS
nix build .#x86_64-darwin

# Build for ARM64 macOS (Apple Silicon)
nix build .#aarch64-darwin
```

### Development

```bash
# Enter development shell
nix develop

# Inside the dev shell:
cargo build
cargo test
cargo run

# Format code
nix fmt
```

### Docker

```bash
# Build Docker image
nix build .#docker

# Load the image
docker load < result

# Upload to registry (requires environment variables)
GOOGLE_ACCESS_TOKEN=xxx IMAGE_TARGET=gcr.io/project/rust-app:latest nix run .#upload-docker
```

### Quality Checks

```bash
# Run all checks
nix flake check

# Run tests only
nix build .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').tests

# Run clippy only
nix build .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').clippy

# Run security audit
nix run .#audit
```

## Project Structure

```
.
├── flake.nix          # Nix flake configuration
├── Cargo.toml         # Rust package manifest
├── Cargo.lock         # Dependency lock file
├── src/
│   └── main.rs        # Application source code
└── README.md          # This file
```

## Flake Configuration Breakdown

### Inputs

The example uses these inputs:

- `nixpkgs`: Standard Nix packages
- `nix-lib`: The HOPR Nix Library (from parent directory)
- `flake-parts`: For better flake organization
- `treefmt-nix`: For code formatting

### Builders

Builders are created for all supported platforms:

```nix
builders = lib.mkRustBuilders { };
```

This provides:

- `builders.local` - Local platform
- `builders.localNightly` - Local with nightly Rust
- `builders.x86_64-linux` - x86_64 Linux static
- `builders.aarch64-linux` - ARM64 Linux static
- `builders.x86_64-darwin` - x86_64 macOS
- `builders.aarch64-darwin` - ARM64 macOS

### Source Filtering

The example demonstrates three types of source filtering:

```nix
sources = {
  main = lib.mkSrc { ... };      # Full source for building
  deps = lib.mkDepsSrc { ... };  # Minimal source for dependencies
  test = lib.mkTestSrc { ... };  # Source with test data
};
```

This improves build caching by separating dependency resolution from the main
build.

### Packages

Multiple package variants are defined:

- `default` - Local release build
- `dev` - Development build (faster, with debug symbols)
- `x86_64-linux`, `aarch64-linux`, etc. - Cross-compiled packages
- `docker` - Docker image

### Development Shell

The dev shell includes:

- Rust toolchain
- Build tools (cargo, rustc, etc.)
- Code formatters
- Additional tools (cargo-edit, cargo-watch)

### Checks

Automated checks ensure code quality:

- `tests` - Run Cargo tests
- `clippy` - Run Clippy linter
- `formatting` - Check code formatting

## Adapting for Your Project

To use the HOPR Nix Library in your own project:

1. **Update flake inputs** - Change `nix-lib.url` to point to the library:
   ```nix
   nix-lib.url = "github:hoprnet/nix-lib";
   ```

2. **Customize builders** - Add a `rustToolchainFile` if you use
   `rust-toolchain.toml`:
   ```nix
   builders = lib.mkRustBuilders {
     rustToolchainFile = ./rust-toolchain.toml;
   };
   ```

3. **Add extra dependencies** - Extend `extraFiles` in source filtering:
   ```nix
   sources.main = lib.mkSrc {
     root = ./.;
     fs = nixpkgs.lib.fileset;
     extraFiles = [ ./config.yaml ];
     extraExtensions = [ "graphql" "sql" ];
   };
   ```

4. **Customize Docker images** - Add extra packages or environment variables:
   ```nix
   dockerImage = lib.mkDockerImage {
     name = "my-app";
     tag = "v1.0.0";
     Entrypoint = [ "${myApp}/bin/my-app" ];
     extraContents = [ pkgs.curl pkgs.jq ];
     env = [
       "RUST_LOG=debug"
       "APP_ENV=production"
     ];
   };
   ```

5. **Add more checks** - Include additional quality checks:
   ```nix
   checks = {
     tests = ...;
     clippy = ...;
     docs = builders.local.callPackage lib.mkRustPackage {
       buildDocs = true;
       ...
     };
   };
   ```

## Tips

- **Faster iteration**: Use `nix build .#dev` for development builds
- **CI/CD**: Use `nix flake check` in your CI pipeline
- **Caching**: The library's source filtering maximizes Nix cache hits
- **Static binaries**: Linux builds use musl for fully static binaries
- **Security**: Run `nix run .#audit` regularly to check for vulnerabilities

## License

MIT License - see [LICENSE](../../LICENSE) file for details.
