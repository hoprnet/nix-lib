# flake-module.nix - HOPR Nix Library flake-parts module
#
# This module provides treefmt integration for Rust projects using the
# HOPR Nix Library. It wraps treefmt-nix and auto-configures formatters
# for Rust, Nix, TOML, YAML, JSON, Markdown, Python, and shell scripts.
#
# Usage in your flake:
#   imports = [ inputs.nix-lib.flakeModules.default ];
#
#   perSystem = { ... }: {
#     nix-lib.treefmt = {
#       globalExcludes = [ "generated/*" ];
#       extraFormatters = {
#         settings.formatter.custom.command = "...";
#       };
#     };
#   };

# This function receives nix-lib's inputs via importApply
{ inputs }:

# This is the actual flake-parts module
{ lib, ... }:

{
  # Import treefmt-nix module from nix-lib's inputs
  imports = [
    inputs.treefmt-nix.flakeModule
  ];

  # Configure perSystem options and config
  perSystem =
    { config, system, pkgs, ... }:
    let
      # Get the nix-lib library functions for this system
      nixLib = inputs.self.lib.${system};
    in
    {
      # Define perSystem options
      options.nix-lib.treefmt = {
        globalExcludes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional file patterns to exclude from formatting";
          example = [
            "generated/*"
            "vendor/*"
          ];
        };

        extraFormatters = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Additional formatter configurations to merge with base config";
          example = {
            settings.formatter.custom = {
              command = "custom-formatter";
              includes = [ "*.custom" ];
            };
          };
        };
      };

      # Apply configuration
      config = {
        # Apply mkTreefmtConfig using the configured options
        treefmt = nixLib.mkTreefmtConfig {
          inherit config;
          globalExcludes = config.nix-lib.treefmt.globalExcludes;
          extraFormatters = config.nix-lib.treefmt.extraFormatters;
        };

        # Export the formatter for nix fmt
        formatter = config.treefmt.build.wrapper;
      };
    };
}
