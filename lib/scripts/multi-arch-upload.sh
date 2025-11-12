#!/usr/bin/env bash
# multi-arch-upload.sh - Upload multi-architecture Docker manifests
#
# This script uploads all platform-specific Docker images from a multi-arch
# manifest and creates a manifest list that enables automatic platform selection.
#
# Required environment variables:
#   GOOGLE_ACCESS_TOKEN - Access token for registry authentication
#   IMAGE_TARGET        - Full registry path (e.g., gcr.io/project/image:tag)
#   MANIFEST_DIR        - Path to the manifest directory containing images and metadata
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
validate_env_var "MANIFEST_DIR"

# Validate manifest directory
if [[ ! -d "$MANIFEST_DIR" ]]; then
  echo "ERROR: Manifest directory does not exist: $MANIFEST_DIR" >&2
  exit 2
fi

if [[ ! -f "$MANIFEST_DIR/metadata.json" ]]; then
  echo "ERROR: Manifest metadata not found: $MANIFEST_DIR/metadata.json" >&2
  exit 2
fi

echo "======================================="
echo "Multi-Arch Docker Image Upload"
echo "======================================="
echo ""
echo "Manifest: $MANIFEST_DIR"
echo "Target: $IMAGE_TARGET"
echo ""

# Read manifest metadata
MANIFEST_NAME=$(jq -r '.name' "$MANIFEST_DIR/metadata.json")
MANIFEST_TAG=$(jq -r '.tag' "$MANIFEST_DIR/metadata.json")
PLATFORMS=$(jq -r '.platforms[]' "$MANIFEST_DIR/metadata.json")

echo "Manifest: $MANIFEST_NAME:$MANIFEST_TAG"
echo "Platforms:"
for platform in $PLATFORMS; do
  echo "  - $platform"
done
echo ""

# Prepare skopeo base args
skopeo_base_args=(
  "--dest-registry-token=$GOOGLE_ACCESS_TOKEN"
)

# Add insecure policy flag only if explicitly requested
if [[ "${SKOPEO_INSECURE_POLICY:-}" == "1" ]]; then
  echo "WARNING: Using insecure policy mode (signature verification disabled)" >&2
  skopeo_base_args+=("--insecure-policy")
fi

# Array to store pushed image references for manifest creation
PUSHED_REFS=()

# Upload each platform-specific image
for platform in $PLATFORMS; do
  echo "--------------------------------------"
  echo "Uploading $platform image..."
  echo "--------------------------------------"

  # Convert platform to safe filename format (e.g., linux/amd64 -> linux-amd64)
  SAFE_PLATFORM="${platform//\//-}"
  IMAGE_FILE="$MANIFEST_DIR/images/$SAFE_PLATFORM.tar.gz"

  if [[ ! -f "$IMAGE_FILE" ]]; then
    echo "ERROR: Platform image not found: $IMAGE_FILE" >&2
    exit 3
  fi

  # Create platform-specific tag
  PLATFORM_TARGET="$IMAGE_TARGET-$SAFE_PLATFORM"

  echo "Source: $IMAGE_FILE"
  echo "Target: $PLATFORM_TARGET"

  # Upload the image
  if ! skopeo copy \
    "${skopeo_base_args[@]}" \
    --format=oci \
    --dest-compress \
    "docker-archive:$IMAGE_FILE" \
    "docker://$PLATFORM_TARGET"; then
    echo "ERROR: Failed to upload $platform image" >&2
    exit 3
  fi

  PUSHED_REFS+=("$PLATFORM_TARGET")
  echo "✓ $platform image uploaded successfully"
  echo ""
done

# Create and push manifest list
echo "======================================="
echo "Creating manifest list..."
echo "======================================="
echo ""

# Use crane to create the manifest list
if ! crane index append \
  --docker-registry-token="$GOOGLE_ACCESS_TOKEN" \
  --tag "$IMAGE_TARGET" \
  "${PUSHED_REFS[@]}"; then
  echo "ERROR: Failed to create manifest list" >&2
  exit 4
fi

echo ""
echo "======================================="
echo "SUCCESS!"
echo "======================================="
echo ""
echo "Multi-architecture image uploaded to:"
echo "  $IMAGE_TARGET"
echo ""
echo "You can now pull this image on any supported platform:"
echo "  docker pull $IMAGE_TARGET"
echo ""
echo "The container runtime will automatically select the"
echo "correct architecture variant for your platform."
