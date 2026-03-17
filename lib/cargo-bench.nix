# cargo-bench.nix - Cargo benchmark runner
#
# Creates a derivation for running Rust benchmarks using cargo bench.
# Builds on the standard Cargo derivation but with benchmarking-specific configuration.

{
  mkCargoDerivation,
  noRun ? false,
}:

{
  cargoArtifacts,

  ...
}@origArgs:
let
  # Remove benchmark-specific arguments that aren't needed for the base derivation
  args = builtins.removeAttrs origArgs [
    "cargoExtraArgs"
  ];

  benchCmd =
    if noRun then "cargo bench --no-run --workspace --locked" else "cargo bench --workspace --locked";
in
# Create the benchmark derivation by extending the base cargo derivation
# with benchmark-specific configuration
mkCargoDerivation (
  args
  // {
    inherit cargoArtifacts;
    pnameSuffix = "-bench"; # Distinguish benchmark builds from regular builds

    buildPhaseCargoCommand = benchCmd;

    nativeBuildInputs = (args.nativeBuildInputs or [ ]);
  }
)
