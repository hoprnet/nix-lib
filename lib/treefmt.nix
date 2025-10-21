# treefmt.nix - Code formatting configuration template
#
# Provides a standard treefmt configuration for Rust projects with
# support for multiple file types and formatters.
#
# This is a function that returns a treefmt configuration suitable
# for use with the treefmt-nix flake module.

{
  config, # Flake-parts config
  pkgs, # Nixpkgs package set
  globalExcludes ? [ ], # Additional global exclusions
  extraFormatters ? { }, # Additional formatter configurations
}:

let
  # Default global exclusions for most projects
  defaultExcludes = [
    # Binary and lock files
    "**/*.id"
    "**/.cargo-ok"
    "**/.gitignore"

    # Configuration files that shouldn't be formatted
    ".actrc"
    ".dockerignore"
    ".editorconfig"
    ".gcloudignore"
    ".gitattributes"
    ".yamlfmt"
    "LICENSE"
    "Makefile"

    # Build artifacts
    "target/*"

    # Vendor code
    "vendor/*"
  ];

  allExcludes = defaultExcludes ++ globalExcludes;
in
{
  # Project root detection file
  inherit (config.flake-root) projectRootFile;

  # Global exclusions - files and directories to never format
  settings.global.excludes = allExcludes;

  # Shell script formatting
  programs.shfmt.enable = true;

  # YAML formatting
  programs.yamlfmt.enable = true;
  settings.formatter.yamlfmt.settings = {
    formatter.type = "basic";
    formatter.max_line_length = 120;
    formatter.trim_trailing_whitespace = true;
    formatter.scan_folded_as_literal = true;
    formatter.include_document_start = true;
  };

  # Markdown and JSON formatting with Prettier
  programs.prettier.enable = true;
  settings.formatter.prettier.includes = [
    "*.md"
    "*.json"
  ];
  settings.formatter.prettier.excludes = [
    "*.yml"
    "*.yaml"
  ];

  # Rust formatting with nightly for unstable features
  programs.rustfmt.enable = true;
  settings.formatter.rustfmt = {
    command = "${pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default)}/bin/rustfmt";
    options = [
      "--config-path"
      "."
    ];
  };

  # Nix formatting using official Nixpkgs style
  programs.nixfmt.enable = true;

  # TOML formatting
  programs.taplo.enable = true;
  settings.formatter.taplo.options = [
    "-o"
    "align_entries=true"
    "-o"
    "reorder_keys=true"
    "-o"
    "reorder_arrays=true"
  ];

  # Python formatting with Ruff
  programs.ruff-format.enable = true;
}
// extraFormatters
