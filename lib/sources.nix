# sources.nix - File source management utilities
#
# Provides functions for creating filtered source trees for different build contexts.
# This helps reduce build closure sizes and improves caching by only including
# necessary files for each build step.

{ lib }:

rec {
  # Create a filtered source for dependency-only builds
  # Only includes files necessary for resolving Rust dependencies
  #
  # Arguments:
  #   root: Path to the project root
  #   fs: lib.fileset (typically lib.fileset)
  #   extraFiles: Optional list of additional files to include (default: [])
  mkDepsSrc =
    {
      root,
      fs,
      extraFiles ? [ ],
    }:
    fs.toSource {
      inherit root;
      fileset = fs.unions (
        [
          # Cargo configuration
          (root + "/.cargo/config.toml")
          (root + "/Cargo.lock")
          # Include all Cargo.toml files for workspace resolution
          (fs.fileFilter (file: file.name == "Cargo.toml") root)
        ]
        ++ extraFiles
      );
    };

  # Create a filtered source for main Rust builds
  # Includes all necessary source files and resources
  #
  # Arguments:
  #   root: Path to the project root
  #   fs: lib.fileset (typically lib.fileset)
  #   extraFiles: Optional list of additional files to include (default: [])
  #   extraExtensions: Optional list of additional file extensions to include (default: [])
  mkSrc =
    {
      root,
      fs,
      extraFiles ? [ ],
      extraExtensions ? [ ],
    }:
    let
      baseExtensions = [
        "rs"
        "toml"
      ];
      allExtensions = baseExtensions ++ extraExtensions;

      fileset = fs.unions (
        [
          # Cargo configuration
          (root + "/.cargo/config.toml")
          (root + "/Cargo.lock")
          (root + "/README.md")

          # Source files
        ]
        ++ (map (ext: fs.fileFilter (file: file.hasExt ext) root) allExtensions)
        ++ extraFiles
      );
    in
    fs.toSource {
      inherit root fileset;
    };

  # Create a filtered source for test builds
  # Includes additional test data and fixtures
  #
  # Arguments:
  #   root: Path to the project root
  #   fs: lib.fileset (typically lib.fileset)
  #   extraFiles: Optional list of additional files to include (default: [])
  #   extraExtensions: Optional list of additional file extensions to include (default: [])
  #   testDataPatterns: Optional list of glob patterns for test data files (default: [])
  mkTestSrc =
    {
      root,
      fs,
      extraFiles ? [ ],
      extraExtensions ? [ ],
      testDataPatterns ? [ ],
    }:
    let
      baseExtensions = [
        "rs"
        "toml"
      ];
      allExtensions = baseExtensions ++ extraExtensions;

      fileset = fs.unions (
        [
          # Cargo configuration
          (root + "/.cargo/config.toml")
          (root + "/Cargo.lock")
          (root + "/README.md")

          # Source files
        ]
        ++ (map (ext: fs.fileFilter (file: file.hasExt ext) root) allExtensions)
        ++ extraFiles
      );
    in
    fs.toSource {
      inherit root fileset;
    };
}
