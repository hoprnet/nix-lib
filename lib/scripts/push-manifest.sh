#!/usr/bin/env bash
# push-manifest.sh - Push multi-architecture manifest to container registry
#
# This script is part of a multi-arch manifest build and is designed to be
# run from the manifest output directory.
#
# Usage: ./push-manifest.sh REGISTRY/IMAGE:TAG
# Example: ./push-manifest.sh gcr.io/myproject/myapp:latest
#
# This script will:
# 1. Load and push each platform-specific image
# 2. Create and push a manifest list that references all platforms
#
# Requirements:
# - skopeo (for pushing images)
# - crane (for creating manifest lists)
# - jq (for reading metadata.json)

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 REGISTRY/IMAGE:TAG"
  echo "Example: $0 gcr.io/myproject/myapp:latest"
  exit 1
fi

TARGET="$1"
MANIFEST_DIR="$(dirname "$0")"

# Verify required tools are available
for tool in skopeo crane jq; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: Required tool '$tool' not found in PATH" >&2
    exit 1
  fi
done

# Verify metadata file exists
if [ ! -f "$MANIFEST_DIR/metadata.json" ]; then
  echo "ERROR: metadata.json not found in $MANIFEST_DIR" >&2
  exit 1
fi

echo "Pushing multi-arch manifest to: $TARGET"
echo "======================================="

# Read platforms from metadata.json
PLATFORMS=$(jq -r '.platforms[]' "$MANIFEST_DIR/metadata.json")

if [ -z "$PLATFORMS" ]; then
  echo "ERROR: No platforms found in metadata.json" >&2
  exit 1
fi

# Array to store pushed image refs
PLATFORM_REFS=()

# Push each platform image
for platform in $PLATFORMS; do
  echo ""
  echo "Pushing $platform image..."
  SAFE_PLATFORM="${platform//\//-}"
  PLATFORM_TAG="$TARGET-$SAFE_PLATFORM"

  if [ ! -f "$MANIFEST_DIR/images/$SAFE_PLATFORM.tar.gz" ]; then
    echo "ERROR: Image not found: $MANIFEST_DIR/images/$SAFE_PLATFORM.tar.gz" >&2
    exit 1
  fi

  skopeo copy \
    --format=oci \
    --dest-compress \
    "docker-archive:$MANIFEST_DIR/images/$SAFE_PLATFORM.tar.gz" \
    "docker://$PLATFORM_TAG"

  PLATFORM_REFS+=("$PLATFORM_TAG")
  echo "$platform pushed to: $PLATFORM_TAG"
done

# Create and push manifest list using crane
echo ""
echo "Creating manifest list..."

# Build the manifest arguments array
MANIFEST_ARGS=()
for ref in "${PLATFORM_REFS[@]}"; do
  MANIFEST_ARGS+=("-m" "$ref")
done

crane index append \
  "${MANIFEST_ARGS[@]}" \
  -t "$TARGET"

echo ""
echo "Multi-arch manifest successfully pushed to: $TARGET"
echo ""
echo "You can now pull the image on any platform:"
echo "  docker pull $TARGET"
