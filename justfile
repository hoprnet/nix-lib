# Default recipe - show available commands
default:
    @just --list

# Update the trivy-db hash to the latest version
update-trivy-db-hash:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Updating trivy-db hash..."
    echo ""

    # Backup the current file
    cp lib/trivy-db.nix lib/trivy-db.nix.bak

    # Set a fake hash to force rebuild
    FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    sed -i "s|outputHash = \"sha256-[^\"]*\";|outputHash = \"$FAKE_HASH\";|g" lib/trivy-db.nix

    echo "Building trivy-db to get new hash..."
    # Build and capture the error containing the correct hash
    BUILD_OUTPUT=$(nix build --impure --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; in import ./lib/trivy-db.nix { inherit pkgs lib; }' --no-link 2>&1 || true)

    # Extract the new hash from the error message
    NEW_HASH=$(echo "$BUILD_OUTPUT" | grep "got:" | awk '{print $2}')

    if [ -z "$NEW_HASH" ]; then
        echo "ERROR: Could not extract new hash from build output"
        echo "Build output:"
        echo "$BUILD_OUTPUT"
        # Restore backup
        mv lib/trivy-db.nix.bak lib/trivy-db.nix
        exit 1
    fi

    echo "New hash: $NEW_HASH"

    # Update the hash in the file
    sed -i "s|outputHash = \"$FAKE_HASH\";|outputHash = \"$NEW_HASH\";|g" lib/trivy-db.nix

    # Update the date comment
    CURRENT_DATE=$(date +%Y-%m-%d)
    sed -i "s|# Hash verified on .*|# Hash verified on $CURRENT_DATE|g" lib/trivy-db.nix

    # Remove backup
    rm lib/trivy-db.nix.bak

    echo ""
    echo "Verifying build with new hash..."
    if nix build --impure --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; in import ./lib/trivy-db.nix { inherit pkgs lib; }' --no-link; then
        echo ""
        echo "Success! trivy-db hash updated to: $NEW_HASH"
        echo "   Date updated to: $CURRENT_DATE"
    else
        echo ""
        echo "ERROR: Build failed with new hash"
        exit 1
    fi

# Build the trivy-db derivation
build-trivy-db:
    nix build --impure --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; in import ./lib/trivy-db.nix { inherit pkgs lib; }'

# Check the flake for errors
check:
    nix flake check

# Format all Nix files
fmt:
    nix fmt

# Show flake outputs
show:
    nix flake show

# Update flake lock file
update-lock:
    nix flake update

# Enter development shell
dev:
    nix develop

# Build example shell package
build-example:
    nix build .#example-shell

# Clean up result symlinks
clean:
    rm -f result result-*
