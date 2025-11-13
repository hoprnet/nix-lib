# trivy-db.nix - Pre-fetched Trivy vulnerability database for offline scanning
#
# This derivation downloads the Trivy vulnerability database as a fixed-output
# derivation, allowing it to be used in sandboxed Nix builds without network access.
#
# The database is updated by Aqua Security every 6 hours. To update this derivation:
# 1. Change outputHash to lib.fakeSha256 temporarily
# 2. Run: nix build .#trivyDb
# 3. Copy the expected hash from the error message
# 4. Update the outputHash with the correct value
#
# Note: The database will become stale over time. Consider rebuilding this
# derivation regularly (e.g., weekly) to ensure up-to-date vulnerability data.

{ pkgs, lib }:

pkgs.runCommand "trivy-db-download"
  {
    # Fixed-output derivation settings
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    # Hash verified on 2025-11-13
    # To update: remove this hash, rebuild, and replace with the new hash from the error message
    outputHash = "sha256-8jVc7uS7Uz+dWbUMaVlMbP6kIiau3DPwuI0+7LlMtDc=";

    nativeBuildInputs = [
      pkgs.trivy
      pkgs.cacert
    ];

    # SSL certificate bundle for HTTPS downloads
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

    # Metadata for debugging
    meta = {
      description = "Pre-fetched Trivy vulnerability database";
      homepage = "https://github.com/aquasecurity/trivy-db";
      license = lib.licenses.asl20;
      maintainers = [ ];
    };
  }
  ''
    # Create temporary cache directory
    export TRIVY_CACHE_DIR=$TMPDIR/trivy-cache
    mkdir -p $TRIVY_CACHE_DIR

    echo "Downloading Trivy vulnerability database..."
    echo "This may take a few minutes depending on network speed..."
    echo ""

    # Download the database only (no scanning)
    if ! trivy --cache-dir $TRIVY_CACHE_DIR image --download-db-only; then
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
    mkdir -p $out/db
    cp -r $TRIVY_CACHE_DIR/db/* $out/db/
    echo "Files copied to output directory"
    echo ""

    # Display database information
    echo "Database files packaged:"
    ls -lah $out/db/
    echo ""

    if [ -f $out/db/metadata.json ]; then
      echo "Database metadata:"
      cat $out/db/metadata.json
      echo ""
    fi

    echo "Trivy database derivation created at: $out"
  ''
