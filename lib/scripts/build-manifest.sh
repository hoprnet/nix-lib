#!/usr/bin/env bash
# build-manifest.sh - Build multi-architecture Docker manifest
#
# This script creates a multi-architecture manifest directory containing:
# - Platform-specific image tarballs
# - metadata.json with manifest configuration
# - push-manifest.sh helper script
#
# Usage: build-manifest.sh OUTPUT_DIR INPUT_JSON PUSH_SCRIPT
#
# Parameters:
#   OUTPUT_DIR  - Directory where manifest will be created
#   INPUT_JSON  - JSON file with manifest configuration
#   PUSH_SCRIPT - Path to push-manifest.sh script to copy
#
# Input JSON format:
#   {
#     "name": "myapp",
#     "tag": "latest",
#     "images": [
#       {"platform": "linux/amd64", "path": "/path/to/image.tar.gz"},
#       {"platform": "linux/arm64", "path": "/path/to/image.tar.gz"}
#     ]
#   }

set -euo pipefail

# Verify required tools
if ! command -v jq &>/dev/null; then
  echo "ERROR: Required tool 'jq' not found in PATH" >&2
  exit 1
fi

# Validate parameters
if [ $# -ne 3 ]; then
  echo "Usage: $0 OUTPUT_DIR INPUT_JSON PUSH_SCRIPT" >&2
  exit 1
fi

OUTPUT_DIR="$1"
INPUT_JSON="$2"
PUSH_SCRIPT="$3"

# Validate input file exists
if [ ! -f "$INPUT_JSON" ]; then
  echo "ERROR: Input JSON file not found: $INPUT_JSON" >&2
  exit 1
fi

if [ ! -f "$PUSH_SCRIPT" ]; then
  echo "ERROR: Push script not found: $PUSH_SCRIPT" >&2
  exit 1
fi

# Read manifest configuration
NAME=$(jq -r '.name' "$INPUT_JSON")
TAG=$(jq -r '.tag' "$INPUT_JSON")
IMAGE_COUNT=$(jq '.images | length' "$INPUT_JSON")

# Validate that at least one image is provided
if ! [[ $IMAGE_COUNT =~ ^[0-9]+$ ]] || [ "$IMAGE_COUNT" -eq 0 ]; then
  echo "ERROR: No images found in input JSON" >&2
  echo "The 'images' array must contain at least one image" >&2
  exit 1
fi

echo "Creating multi-architecture manifest for $NAME:$TAG"
echo "==========================================="
echo ""

# Create output directory structure
mkdir -p "$OUTPUT_DIR/images"

# Process each platform image
jq -c '.images[]' "$INPUT_JSON" | while IFS= read -r img_json; do
  PLATFORM=$(echo "$img_json" | jq -r '.platform')
  IMAGE_PATH=$(echo "$img_json" | jq -r '.path')
  SAFE_PLATFORM="${PLATFORM//\//-}"

  echo "Processing $PLATFORM image..."
  echo "  Source: $IMAGE_PATH"

  if [ ! -f "$IMAGE_PATH" ]; then
    echo "ERROR: Image file not found: $IMAGE_PATH" >&2
    exit 1
  fi

  # Copy the image tarball to our output
  cp "$IMAGE_PATH" "$OUTPUT_DIR/images/$SAFE_PLATFORM.tar.gz"
  echo "  Copied to: images/$SAFE_PLATFORM.tar.gz"
  echo ""
done

echo "All images processed. Creating manifest metadata..."
echo ""

# Generate metadata.json
# Build the images object mapping platform to file path
IMAGES_OBJECT=$(jq -r '.images[] | @json' "$INPUT_JSON" | while IFS= read -r img_json; do
  PLATFORM=$(echo "$img_json" | jq -r '.platform')
  SAFE_PLATFORM="${PLATFORM//\//-}"
  echo "\"$PLATFORM\": \"images/$SAFE_PLATFORM.tar.gz\""
done | paste -sd ',' -)

# Build the platforms array
PLATFORMS_ARRAY=$(jq -r '[.images[].platform]' "$INPUT_JSON")

# Create final metadata.json
cat >"$OUTPUT_DIR/metadata.json" <<EOF
{
  "name": "$NAME",
  "tag": "$TAG",
  "imageCount": $IMAGE_COUNT,
  "platforms": $PLATFORMS_ARRAY,
  "images": {
    $IMAGES_OBJECT
  }
}
EOF

echo "Manifest metadata:"
jq . "$OUTPUT_DIR/metadata.json"
echo ""

# Copy the push-manifest helper script
cp "$PUSH_SCRIPT" "$OUTPUT_DIR/push-manifest.sh"
chmod +x "$OUTPUT_DIR/push-manifest.sh"

echo "==========================================="
echo "✅ Multi-architecture manifest created!"
echo ""
echo "Output directory: $OUTPUT_DIR"
echo "  - metadata.json: Manifest metadata"
echo "  - images/: Platform-specific images"
echo "  - push-manifest.sh: Helper script to push to registry"
echo ""
echo "To push to a registry:"
echo "  $OUTPUT_DIR/push-manifest.sh REGISTRY/IMAGE:TAG"
