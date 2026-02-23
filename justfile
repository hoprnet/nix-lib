# Default recipe - show available commands
default:
    @just --list

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
