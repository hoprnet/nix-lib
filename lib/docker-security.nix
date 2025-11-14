# docker-security.nix - Docker security scanning and SBOM generation utilities
#
# Provides functions to scan Docker images for vulnerabilities and generate
# Software Bill of Materials (SBOM) in multiple formats.
#
# These utilities are designed to be used as separate build targets or
# integrated into CI/CD pipelines.

{
  pkgs,
  lib ? pkgs.lib,
}:

let
  # Import pre-fetched Trivy database for offline scanning
  trivyDb = import ./trivy-db.nix { inherit pkgs lib; };
in

{
  # mkTrivyScan - Scan a Docker image for vulnerabilities using Trivy
  #
  # Returns a derivation that produces vulnerability scan reports in various formats.
  # The scan can be configured to fail on specific severity levels.
  #
  # Example usage:
  #   trivyScan = mkTrivyScan {
  #     image = dockerImage;
  #     name = "myapp-trivy-scan";
  #     severity = "HIGH,CRITICAL";
  #     format = "json";
  #   };
  #
  # Then build: nix build .#trivyScan
  mkTrivyScan =
    {
      image, # Docker image derivation to scan
      name ? "${image.imageName}-trivy-scan", # Name for the scan output derivation
      severity ? "UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL", # Comma-separated severity levels
      format ? "json", # Output format: json, table, sarif, cyclonedx, spdx, etc.
      vulnType ? "os,library", # Vulnerability types to scan: os, library
      exitCode ? 0, # Exit code when vulnerabilities are found (0 = don't fail)
      timeout ? "5m", # Scan timeout
      ignoreUnfixed ? false, # Ignore vulnerabilities without fixes
      trivyDatabase ? trivyDb, # Pre-fetched Trivy database for offline scanning
    }:
    pkgs.runCommand name
      {
        buildInputs = [
          pkgs.trivy
          trivyDatabase
        ];
        inherit image;

        # Environment variables for offline scanning
        TRIVY_SKIP_DB_UPDATE = "true";
        TRIVY_SKIP_JAVA_DB_UPDATE = "true";
      }
      ''
        mkdir -p $out

        # Create a writable cache directory and copy the pre-fetched database
        # Trivy/SQLite needs write access to open the database file
        echo "Setting up writable Trivy cache..."
        export TRIVY_CACHE_DIR=$TMPDIR/trivy-cache
        mkdir -p $TRIVY_CACHE_DIR/db
        cp -r ${trivyDatabase}/db/* $TRIVY_CACHE_DIR/db/
        chmod -R u+w $TRIVY_CACHE_DIR
        echo "Using pre-fetched Trivy database from: ${trivyDatabase}"

        echo "Loading Docker image: ${image}"
        ${pkgs.trivy}/bin/trivy image \
          --input ${image} \
          --format ${format} \
          --severity ${severity} \
          --vuln-type ${vulnType} \
          --exit-code ${toString exitCode} \
          --timeout ${timeout} \
          --skip-db-update \
          --skip-java-db-update \
          ${pkgs.lib.optionalString ignoreUnfixed "--ignore-unfixed"} \
          --output $out/scan-report.${format} \
          ${image.imageName}:${image.imageTag or "latest"}

        echo "Trivy scan complete. Report saved to $out/scan-report.${format}"

        # Also generate a human-readable table summary
        ${pkgs.trivy}/bin/trivy image \
          --input ${image} \
          --format table \
          --severity ${severity} \
          --vuln-type ${vulnType} \
          --skip-db-update \
          --skip-java-db-update \
          ${pkgs.lib.optionalString ignoreUnfixed "--ignore-unfixed"} \
          --output $out/scan-summary.txt \
          ${image.imageName}:${image.imageTag or "latest"} || true

        echo "Scan results available in: $out"
        ls -lah $out/
      '';

  # mkSBOM - Generate Software Bill of Materials for a Docker image
  #
  # Creates SBOMs in multiple formats (SPDX and CycloneDX) using Syft.
  # These can be uploaded as GitHub artifacts or used for supply chain security.
  #
  # Example usage:
  #   sbom = mkSBOM {
  #     image = dockerImage;
  #     name = "myapp-sbom";
  #   };
  #
  # Then build: nix build .#sbom
  mkSBOM =
    {
      image, # Docker image derivation to analyze
      name ? "${image.imageName}-sbom", # Name for the SBOM output derivation
      formats ? [
        "spdx-json"
        "cyclonedx-json"
      ], # SBOM formats to generate
    }:
    pkgs.runCommand name
      {
        buildInputs = [ pkgs.syft ];
        inherit image;
      }
      ''
        set -euo pipefail

        mkdir -p $out

        # Validate that at least one format is requested
        if [ ${builtins.toString (builtins.length formats)} -eq 0 ]; then
          echo "ERROR: No SBOM formats specified. Available formats: spdx-json, cyclonedx-json, syft-json"
          exit 1
        fi

        # Verify image exists
        if [ ! -f "${image}" ]; then
          echo "ERROR: Docker image not found: ${image}"
          ls -la "$(dirname "${image}")" || true
          exit 1
        fi

        echo "Loading Docker image for SBOM generation: ${image}"
        echo "Requested formats: ${builtins.toString formats}"

        # Create writable cache directory for Syft
        # Syft needs write access to cache vulnerability databases and scan metadata
        echo "Setting up writable Syft cache..."
        export SYFT_CACHE_DIR=$TMPDIR/syft-cache
        mkdir -p $SYFT_CACHE_DIR

        # Generate SPDX SBOM
        ${
          if builtins.elem "spdx-json" formats then
            ''
              echo "Generating SPDX JSON SBOM..."
              ${pkgs.syft}/bin/syft scan \
                oci-archive:${image} \
                --output spdx-json=$out/sbom.spdx.json

              if [ ! -f "$out/sbom.spdx.json" ]; then
                echo "ERROR: Failed to generate SPDX SBOM at $out/sbom.spdx.json"
                exit 1
              fi
              echo "SPDX SBOM generated: $out/sbom.spdx.json ($(stat -c%s "$out/sbom.spdx.json" 2>/dev/null || stat -f%z "$out/sbom.spdx.json" 2>/dev/null) bytes)"
            ''
          else
            ""
        }

        # Generate CycloneDX SBOM
        ${
          if builtins.elem "cyclonedx-json" formats then
            ''
              echo "Generating CycloneDX JSON SBOM..."
              ${pkgs.syft}/bin/syft scan \
                oci-archive:${image} \
                --output cyclonedx-json=$out/sbom.cyclonedx.json

              if [ ! -f "$out/sbom.cyclonedx.json" ]; then
                echo "ERROR: Failed to generate CycloneDX SBOM at $out/sbom.cyclonedx.json"
                exit 1
              fi
              echo "CycloneDX SBOM generated: $out/sbom.cyclonedx.json ($(stat -c%s "$out/sbom.cyclonedx.json" 2>/dev/null || stat -f%z "$out/sbom.cyclonedx.json" 2>/dev/null) bytes)"
            ''
          else
            ""
        }

        # Generate additional formats if requested
        ${
          if builtins.elem "syft-json" formats then
            ''
              echo "Generating Syft native JSON SBOM..."
              ${pkgs.syft}/bin/syft scan \
                oci-archive:${image} \
                --output syft-json=$out/sbom.syft.json

              if [ ! -f "$out/sbom.syft.json" ]; then
                echo "ERROR: Failed to generate Syft SBOM at $out/sbom.syft.json"
                exit 1
              fi
              echo "Syft JSON SBOM generated: $out/sbom.syft.json ($(stat -c%s "$out/sbom.syft.json" 2>/dev/null || stat -f%z "$out/sbom.syft.json" 2>/dev/null) bytes)"
            ''
          else
            ""
        }

        echo "SBOM generation complete. Artifacts available in: $out"
        ls -lah $out/
      '';
}
