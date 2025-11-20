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

{
  pkgs,
  lib,
}:

pkgs.runCommand "trivy-db-download"
  {
    # Fixed-output derivation settings
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    # Hash verified on 2025-11-20
    # To update: remove this hash, rebuild, and replace with the new hash from the error message
    outputHash = "sha256-/YrzbwsHYpTnf+cTKN6w7GqMx5VLYgqHADo+WyOJ2+4=";

    nativeBuildInputs = [
      pkgs.trivy
      pkgs.cacert
      pkgs.jq
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
    # Execute the download script
    bash ${./scripts/download-trivy-db.sh}
  ''
