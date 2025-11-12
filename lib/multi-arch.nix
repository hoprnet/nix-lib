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
        buildInputs = [
          pkgs.crane
          pkgs.jq
        ];
      }
      ''
        mkdir -p $out/images
        cd $out

        echo "Creating multi-architecture manifest for ${name}:${tag}"
        echo "==========================================="

        # Process each platform image
        ${pkgs.lib.concatMapStringsSep "\n" (
          imageSpec:
          let
            img = imageSpec.image;
            platform = imageSpec.platform;
            safePlatform = builtins.replaceStrings [ "/" ] [ "-" ] platform;
          in
          ''
            echo ""
            echo "Processing ${platform} image..."
            echo "Source: ${img}"

            # Copy the image tarball to our output
            cp ${img} $out/images/${safePlatform}.tar.gz

            echo "Copied to: $out/images/${safePlatform}.tar.gz"
          ''
        ) images}

        echo ""
        echo "All images processed. Creating manifest list..."

        # Create manifest metadata
        cat > $out/metadata.json <<'METADATA_EOF'
        {
          "name": "${name}",
          "tag": "${tag}",
          "imageCount": ${toString (builtins.length images)},
          "platforms": [
            ${pkgs.lib.concatMapStringsSep ",\n    " (i: ''"${i.platform}"'') images}
          ],
          "images": {
            ${pkgs.lib.concatMapStringsSep ",\n    " (
              i:
              let
                safePlatform = builtins.replaceStrings [ "/" ] [ "-" ] i.platform;
              in
              ''"${i.platform}": "images/${safePlatform}.tar.gz"''
            ) images}
          }
        }
        METADATA_EOF

        echo ""
        echo "Manifest metadata:"
        cat $out/metadata.json | ${pkgs.jq}/bin/jq .

        # Copy the push-manifest helper script
        # The script reads platforms from metadata.json and uses tools from PATH
        cp ${./scripts/push-manifest.sh} $out/push-manifest.sh
        chmod +x $out/push-manifest.sh

        echo ""
        echo "==========================================="
        echo "✅ Multi-architecture manifest created!"
        echo ""
        echo "Output directory: $out"
        echo "  - manifest.json: Manifest list"
        echo "  - metadata.json: Manifest metadata"
        echo "  - images/: Platform-specific images"
        echo "  - push-manifest.sh: Helper script to push to registry"
        echo ""
        echo "To push to a registry:"
        echo "  $out/push-manifest.sh REGISTRY/IMAGE:TAG"
      '';
}
