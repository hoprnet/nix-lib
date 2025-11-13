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
        TRIVY_CACHE_DIR = "${trivyDatabase}";
        TRIVY_SKIP_DB_UPDATE = "true";
        TRIVY_SKIP_JAVA_DB_UPDATE = "true";
      }
      ''
        mkdir -p $out

        echo "Loading Docker image: ${image}"
        echo "Using pre-fetched Trivy database from: ${trivyDatabase}"
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
        mkdir -p $out

        echo "Loading Docker image for SBOM generation: ${image}"

        # Generate SPDX SBOM
        ${
          if builtins.elem "spdx-json" formats then
            ''
              echo "Generating SPDX JSON SBOM..."
              ${pkgs.syft}/bin/syft scan \
                oci-archive:${image} \
                --output spdx-json=$out/sbom.spdx.json
              echo "SPDX SBOM generated: $out/sbom.spdx.json"
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
              echo "CycloneDX SBOM generated: $out/sbom.cyclonedx.json"
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
              echo "Syft JSON SBOM generated: $out/sbom.syft.json"
            ''
          else
            ""
        }

        echo "SBOM generation complete. Artifacts available in: $out"
        ls -lah $out/
      '';
}
