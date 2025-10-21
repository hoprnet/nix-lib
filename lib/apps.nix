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
    pkgs.writeShellScriptBin "docker-image-upload" ''
      set -euo pipefail

      # Validation function for environment variables
      validate_env_var() {
        local var_name="$1"
        local var_value="''${!var_name:-}"

        if [[ -z "$var_value" ]]; then
          echo "ERROR: Required environment variable $var_name is not set or empty" >&2
          echo "Usage: Set $var_name before running this script" >&2
          exit 1
        fi
      }

      # Validate required environment variables
      validate_env_var "GOOGLE_ACCESS_TOKEN"
      validate_env_var "IMAGE_TARGET"

      # Build the Docker image using Nix
      # --no-link prevents creating a result symlink
      # --print-out-paths returns the store path of the built image
      if ! OCI_ARCHIVE="$(nix build --no-link --print-out-paths ${image} 2>/dev/null)"; then
        echo "ERROR: Failed to build Docker image with Nix" >&2
        exit 2
      fi

      # Validate build output
      if [[ -z "$OCI_ARCHIVE" ]]; then
        echo "ERROR: Nix build returned empty output path" >&2
        exit 2
      fi

      if [[ ! -f "$OCI_ARCHIVE" ]]; then
        echo "ERROR: Built image archive does not exist: $OCI_ARCHIVE" >&2
        exit 2
      fi

      echo "Docker image built successfully: $OCI_ARCHIVE"

      # Prepare skopeo command with security options
      skopeo_args=(
        "copy"
        "--dest-registry-token=$GOOGLE_ACCESS_TOKEN"
      )

      # Add insecure policy flag only if explicitly requested
      if [[ "''${SKOPEO_INSECURE_POLICY:-}" == "1" ]]; then
        echo "WARNING: Using insecure policy mode (signature verification disabled)" >&2
        skopeo_args+=("--insecure-policy")
      fi

      skopeo_args+=(
        "docker-archive:$OCI_ARCHIVE"
        "docker://$IMAGE_TARGET"
      )

      # Upload the image to the registry using skopeo
      # Pipe through gzip for faster compression before upload
      echo "Uploading image to registry: $IMAGE_TARGET"
      if ! ${pkgs.gzip}/bin/gzip --fast < "$OCI_ARCHIVE" | ${pkgs.skopeo}/bin/skopeo "''${skopeo_args[@]}"; then
        echo "ERROR: Failed to upload image to registry" >&2
        exit 3
      fi

      echo "Image uploaded successfully to: $IMAGE_TARGET"
    '';

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
