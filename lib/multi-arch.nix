# multi-arch.nix - Multi-architecture Docker manifest utilities
#
# Provides functions to create OCI manifest lists that combine multiple
# platform-specific Docker images into a single reference with automatic
# platform selection.
#
# This enables true multi-arch Docker images where the container runtime
# automatically pulls the correct architecture variant.

{ pkgs }:

{
  # mkMultiArchManifest - Create OCI manifest list for multi-architecture images
  #
  # Combines multiple platform-specific Docker images into a single manifest list
  # that allows automatic platform selection when pulling the image.
  #
  # The resulting manifest can be pushed to a container registry where it will
  # act as a single image reference that works across different architectures.
  #
  # Example usage:
  #   manifest = mkMultiArchManifest {
  #     name = "myapp";
  #     tag = "latest";
  #     images = [
  #       { image = dockerImageAmd64; platform = "linux/amd64"; }
  #       { image = dockerImageArm64; platform = "linux/arm64"; }
  #     ];
  #   };
  #
  # Then push: nix run .#push-manifest
  #
  # Returns a derivation with:
  #   - manifest.json: The OCI manifest list
  #   - metadata.json: Manifest metadata
  #   - images/: Directory with all platform images
  mkMultiArchManifest =
    {
      name, # Name for the manifest
      tag ? "latest", # Tag for the manifest
      images, # List of { image, platform } attribute sets
    # Each image entry should have:
    #   image: Docker image derivation
    #   platform: Platform string (e.g., "linux/amd64", "linux/arm64")
    }:
    pkgs.runCommand "${name}-manifest-${tag}"
      {
        buildInputs = [ pkgs.jq ];
      }
      ''
        # Create input JSON for the build script
        cat >manifest-input.json <<'INPUT_EOF'
        {
          "name": "${name}",
          "tag": "${tag}",
          "images": [
            ${pkgs.lib.concatMapStringsSep ",\n      " (
              i: ''{"platform": "${i.platform}", "path": "${i.image}"}''
            ) images}
          ]
        }
        INPUT_EOF

        # Call the build script to create the manifest
        bash ${./scripts/build-manifest.sh} "$out" manifest-input.json ${./scripts/push-manifest.sh}
      '';
}
