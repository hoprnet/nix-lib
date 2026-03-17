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

  noRunFlag = if noRun then "--no-run " else "";
in
# Create the benchmark derivation by extending the base cargo derivation
# with benchmark-specific configuration
mkCargoDerivation (
  args
  // {
    inherit cargoArtifacts;
    pnameSuffix = "-bench"; # Distinguish benchmark builds from regular builds

    buildPhaseCargoCommand = "cargo bench ${noRunFlag}--workspace --locked";

    nativeBuildInputs = (args.nativeBuildInputs or [ ]);
  }
)
