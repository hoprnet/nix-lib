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
    # Initial hash - will need to be updated after first build
    # Replace with actual hash: nix-hash --type sha256 --to-sri $(nix-hash --type sha256 /nix/store/...-trivy-db-download)
    outputHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

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

    # Download the database only (no scanning)
    trivy --cache-dir $TRIVY_CACHE_DIR image --download-db-only

    echo ""
    echo "Database downloaded successfully!"
    echo ""

    # Package the database into the output
    mkdir -p $out/db
    cp -r $TRIVY_CACHE_DIR/db/* $out/db/

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
