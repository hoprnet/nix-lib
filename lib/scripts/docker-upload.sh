#!/usr/bin/env bash
# docker-upload.sh - Build and upload Docker images to container registries
#
# This script builds a Docker image using Nix and uploads it to a container
# registry using skopeo. It supports Google Cloud Registry authentication.
#
# Required environment variables:
#   GOOGLE_ACCESS_TOKEN - Access token for registry authentication
#   IMAGE_TARGET        - Full registry path (e.g., gcr.io/project/image:tag)
#   IMAGE_DERIVATION    - Nix store path or flake reference to build
#
# Optional environment variables:
#   SKOPEO_INSECURE_POLICY - Set to "1" to bypass signature verification

set -euo pipefail

# Validation function for environment variables
validate_env_var() {
  local var_name="$1"
  local var_value="${!var_name:-}"

  if [[ -z "$var_value" ]]; then
    echo "ERROR: Required environment variable $var_name is not set or empty" >&2
    echo "Usage: Set $var_name before running this script" >&2
    exit 1
  fi
}

# Validate required environment variables
validate_env_var "GOOGLE_ACCESS_TOKEN"
validate_env_var "IMAGE_TARGET"
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
if [[ "${SKOPEO_INSECURE_POLICY:-}" == "1" ]]; then
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
if ! gzip --fast < "$OCI_ARCHIVE" | skopeo "${skopeo_args[@]}"; then
  echo "ERROR: Failed to upload image to registry" >&2
  exit 3
fi

echo "Image uploaded successfully to: $IMAGE_TARGET"
