#!/usr/bin/env bash
# docker-build.sh - Build Docker images
#
# This script builds a Docker image using Nix
#
# Required environment variables:
#   IMAGE_DERIVATION    - Nix store path or flake reference to build
#
# Optional environment variables:
#   IMAGE_NAME          - Tag to apply to the loaded image (e.g. my-app:latest)

set -euo pipefail

# Validation function for environment variables
validate_env_var() {
  local var_name="$1"
  local var_value="${!var_name:-}"

  if [[ -z $var_value ]]; then
    echo "ERROR: Required environment variable $var_name is not set or empty" >&2
    echo "Usage: Set $var_name before running this script" >&2
    exit 1
  fi
}

# Validate required environment variables
validate_env_var "IMAGE_DERIVATION"

# Build the Docker image using Nix
# --no-link prevents creating a result symlink
# --print-out-paths returns the store path of the built image
echo "Building Docker image from: $IMAGE_DERIVATION"
if ! OCI_ARCHIVE="$(nix build --no-link --print-out-paths "$IMAGE_DERIVATION" 2>/dev/null)"; then
  echo "ERROR: Failed to build Docker image with Nix" >&2
  exit 2
fi

# Validate build output
if [[ -z $OCI_ARCHIVE ]]; then
  echo "ERROR: Nix build returned empty output path" >&2
  exit 2
fi

if [[ ! -f $OCI_ARCHIVE ]]; then
  echo "ERROR: Built image archive does not exist: $OCI_ARCHIVE" >&2
  exit 2
fi

echo "Docker image built successfully: $OCI_ARCHIVE"

# Load the image into Docker
echo "Loading image into Docker..."
if ! LOAD_OUTPUT=$(docker load < "$OCI_ARCHIVE"); then
  echo "ERROR: Failed to load Docker image" >&2
  exit 3
fi
echo "$LOAD_OUTPUT"

# Extract the loaded image ID/tag from the output
# Expected output format: "Loaded image: name:tag"
LOADED_IMAGE=$(echo "$LOAD_OUTPUT" | grep "Loaded image:" | head -n1 | cut -d' ' -f3)

if [[ -z "$LOADED_IMAGE" ]]; then
  echo "WARNING: Could not determine loaded image name"
else
  echo "Image loaded as: $LOADED_IMAGE"

  # Tag the image if IMAGE_NAME is provided
  if [[ -n "${IMAGE_NAME:-}" ]]; then
    echo "Tagging image as: $IMAGE_NAME"
    if ! docker tag "$LOADED_IMAGE" "$IMAGE_NAME"; then
      echo "ERROR: Failed to tag image" >&2
      exit 3
    fi
    echo "Image successfully tagged: $IMAGE_NAME"
  fi
fi


