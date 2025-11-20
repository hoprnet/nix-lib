# apps.nix - Utility applications and scripts
#
# Provides various utility scripts for development, testing, and maintenance,
# including Docker upload utilities and common development tools.

{ pkgs, flake-utils }:

rec {
  # Docker Upload Utilities
  # ----------------------

  # Create a script that builds and uploads a Docker image to a registry
  # Uses Google Cloud Registry authentication via GOOGLE_ACCESS_TOKEN
  #
  # Arguments:
  #   image: Derivation that produces a Docker image (e.g., from dockerTools.buildLayeredImage)
  #
  # Required environment variables:
  #   - GOOGLE_ACCESS_TOKEN: Access token for Google Cloud Registry authentication
  #   - IMAGE_TARGET: Full registry path for the target image (e.g., gcr.io/project/image:tag)
  #
  # Optional environment variables:
  #   - SKOPEO_INSECURE_POLICY=1: Enable insecure policy mode (bypasses signature verification)
  mkDockerUploadScript =
    image:
    pkgs.writeShellApplication {
      name = "docker-image-upload";
      runtimeInputs = with pkgs; [
        gzip
        skopeo
        nix
        jq
      ];
      text = ''
        # Set IMAGE_DERIVATION to the image path for the script
        export IMAGE_DERIVATION="${image}"
        ${builtins.readFile ./scripts/docker-upload.sh}
      '';
    };

  # Create a flake app from a Docker upload script
  # This makes the script runnable via `nix run`
  #
  # Arguments:
  #   image: Docker image derivation to upload
  mkDockerUploadApp =
    image:
    flake-utils.lib.mkApp {
      drv = mkDockerUploadScript image;
    };

  # Upload a multi-architecture manifest with all platform images
  # This handles pushing each platform-specific image and creating the manifest list
  #
  # Arguments:
  #   manifest: Multi-arch manifest derivation (from mkMultiArchManifest)
  #
  # Required environment variables:
  #   - GOOGLE_ACCESS_TOKEN: Access token for Google Cloud Registry authentication
  #   - IMAGE_TARGET: Full registry path for the target image (e.g., gcr.io/project/image:tag)
  mkMultiArchUploadScript =
    manifest:
    pkgs.writeShellApplication {
      name = "multi-arch-image-upload";
      runtimeInputs = with pkgs; [
        jq
        skopeo
        crane
      ];
      text = ''
        # Set MANIFEST_DIR to the manifest path for the script
        export MANIFEST_DIR="${manifest}"
        export POLICY_JSON="${./scripts/policy.json}"
        ${builtins.readFile ./scripts/multi-arch-upload.sh}
      '';
    };

  # Create a flake app from a multi-arch upload script
  # This makes the script runnable via `nix run`
  #
  # Arguments:
  #   manifest: Multi-arch manifest derivation to upload
  mkMultiArchUploadApp =
    manifest:
    flake-utils.lib.mkApp {
      drv = mkMultiArchUploadScript manifest;
    };

  # Development Utilities
  # --------------------

  # Run all or specific checks for the project
  # Without arguments: runs all checks
  # With argument: runs specific check by name
  #
  # Arguments:
  #   system: The system architecture (e.g., "x86_64-linux")
  mkCheckApp =
    { system }:
    flake-utils.lib.mkApp {
      drv = pkgs.writeShellScriptBin "check" ''
        set -e
        check=$1
        if [ -z "$check" ]; then
          # Run all checks by listing them from flake output
          nix flake show --json 2>/dev/null | \
            jq -r '.checks."${system}" | to_entries | .[].key | @sh' | \
            xargs -I '{}' sh -c 'nix build ".#checks.${system}.$1"' -- {}
        else
          # Run specific check
          nix build ".#checks.${system}.$check"
        fi
      '';
    };

  # Run cargo audit for security vulnerability checking
  mkAuditApp = flake-utils.lib.mkApp {
    drv = pkgs.writeShellApplication {
      name = "audit";
      runtimeInputs = with pkgs; [
        cargo
        cargo-audit
      ];
      text = ''
        cargo audit
      '';
    };
  };

  # Find an available port for CI testing
  # Used to avoid port conflicts in parallel CI runs
  #
  # Arguments:
  #   findPortScript: Path to the find_port.py script
  #   minPort: Minimum port number (default: 3000)
  #   maxPort: Maximum port number (default: 4000)
  #   skip: Number of ports to skip (default: 30)
  mkFindPortApp =
    {
      findPortScript,
      minPort ? 3000,
      maxPort ? 4000,
      skip ? 30,
    }:
    flake-utils.lib.mkApp {
      drv = pkgs.writeShellApplication {
        name = "find-port";
        text = ''
          ${pkgs.python3}/bin/python ${findPortScript} \
            --min-port ${toString minPort} \
            --max-port ${toString maxPort} \
            --skip ${toString skip}
        '';
      };
    };

  # Update GitHub labels configuration based on crate structure
  # Automatically generates labels for each crate in the monorepo
  #
  # This utility scans the workspace for Cargo.toml files and updates
  # .github/labeler.yml with appropriate labels for each crate.
  mkUpdateGithubLabelsApp = flake-utils.lib.mkApp {
    drv = pkgs.writeShellScriptBin "update-github-labels" ''
      set -eu

      # Remove existing crate entries to handle removed crates
      yq 'with_entries(select(.key != "crate:*"))' \
        .github/labeler.yml > labeler.yml.new

      # Add new crate entries for all known crates
      for f in `find . -mindepth 2 -name "Cargo.toml" -type f -printf '%P\n'`; do
        env \
          name="crate:`yq '.package.name' $f`" \
          dir="`dirname $f`/**" \
          yq -n '.[strenv(name)][0]."changed-files"[0]."any-glob-to-any-file" = env(dir)' \
          >> labeler.yml.new
      done

      mv labeler.yml.new .github/labeler.yml
    '';
  };
}
