#!/usr/bin/env bash
# download-trivy-db.sh - Download and validate Trivy vulnerability database
#
# This script downloads the Trivy vulnerability database and validates its structure.
# It is used by the trivy-db.nix derivation to create a pre-fetched database
# for offline scanning in sandboxed Nix builds.
#
# Required environment variables:
#   out       - Output directory for the database files (set by Nix)
#   TMPDIR    - Temporary directory for download cache (set by Nix)
#
# Required tools in PATH:
#   trivy     - Trivy CLI for downloading the database
#
# The script will:
# 1. Download the Trivy database to a temporary cache directory
# 2. Validate that all required files exist and are non-empty
# 3. Package the database files into the output directory
# 4. Display database metadata for verification

set -euo pipefail

# Create temporary cache directory
export TRIVY_CACHE_DIR=$TMPDIR/trivy-cache
mkdir -p "$TRIVY_CACHE_DIR"

echo "Downloading Trivy vulnerability database..."
echo "This may take a few minutes depending on network speed..."
echo ""

# Download the database only (no scanning)
if ! trivy --cache-dir "$TRIVY_CACHE_DIR" image --download-db-only; then
  echo "ERROR: Failed to download Trivy database" >&2
  exit 1
fi

echo ""
echo "Validating database download..."

# Validate download was successful
if [ ! -d "$TRIVY_CACHE_DIR/db" ]; then
  echo "ERROR: Database directory not created: $TRIVY_CACHE_DIR/db" >&2
  exit 1
fi

if [ ! -f "$TRIVY_CACHE_DIR/db/trivy.db" ]; then
  echo "ERROR: Database file not found: $TRIVY_CACHE_DIR/db/trivy.db" >&2
  exit 1
fi

if [ ! -s "$TRIVY_CACHE_DIR/db/trivy.db" ]; then
  echo "ERROR: Database file is empty: $TRIVY_CACHE_DIR/db/trivy.db" >&2
  exit 1
fi

if [ ! -f "$TRIVY_CACHE_DIR/db/metadata.json" ]; then
  echo "ERROR: Database metadata not found: $TRIVY_CACHE_DIR/db/metadata.json" >&2
  exit 1
fi

echo "Database downloaded and validated successfully!"
echo ""

# Package the database into the output
echo "Packaging database files..."
mkdir -p "$out/db"
cp -r "$TRIVY_CACHE_DIR"/db/* "$out/db/"
echo "Files copied to output directory"
echo ""

# Display database information
echo "Database files packaged:"
ls -lah "$out/db/"
echo ""

if [ -f "$out/db/metadata.json" ]; then
  echo "Database metadata:"
  cat "$out/db/metadata.json"
  echo ""
fi

echo "Trivy database derivation created at: $out"
