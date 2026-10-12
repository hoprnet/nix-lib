# Rust builder native dependency fixture

This crate exercises the GNU build host and musl target through Cargo. Its build
script uses GNU OpenSSL and records the compilers selected by `cc` for both
platforms. A C function and `openssl-sys` call target OpenSSL at runtime.

The nix-lib checks provide the expected compiler and OpenSSL paths. Run the
fixture with `nix build .#checks.x86_64-linux.rustBuilderNativeIntegration`. The
corresponding ARM check runs on an aarch64-linux builder.
