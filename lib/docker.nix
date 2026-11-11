# docker.nix - Docker image builder utility
#
# Creates layered Docker images with optimized caching and minimal size.
# Provides a consistent base for all container images.
#
# This builder automatically selects between buildImage (for macOS) and
# buildLayeredImage (for Linux) to work around fakeroot issues on recent macOS.

{
  pkgs, # Nixpkgs package set (should be Linux packages for Docker images)
  name, # Name of the Docker image
  Entrypoint, # Container entrypoint script or binary
  Cmd ? [ ], # Default command to run in container
  env ? [ ], # Additional environment variables for the container
  extraContents ? [ ], # Additional packages to include in image
  basePackages ? null, # Override base packages (default: bash, cacert, coreutils, etc.)
  tag ? "latest", # Docker image tag
  pathsToLink ? [ "/bin" ],
}:
let
  # Library path for essential system libraries
  libPath = pkgs.lib.makeLibraryPath [ pkgs.openssl ];

  # CA bundle for SSL verification.
  # Mozilla removed emSign ECC Root CA - G3 from certdata.txt in nss-cacert >= 3.128
  # (including release-26.05's nss-cacert 3.131.1). Passing a blacklist override for it
  # on newer versions fails buildcatrust assertion checks (exit code 3: cert in blocklist
  # but not in cert store). For older nixpkgs pins (< 3.128) where the compromised root
  # is still present, we apply the blacklist override; for newer pins, stock pkgs.cacert
  # already excludes it.
  cacert =
    if (builtins.compareVersions (pkgs.cacert.version or "0") "3.128") < 0 then
      pkgs.cacert.override { blacklist = [ "emSign ECC Root CA - G3" ]; }
    else
      pkgs.cacert;

  # Default base packages included in all Docker images
  # These provide essential runtime dependencies
  defaultBasePackages = with pkgs; [
    bash
    cacert
    coreutils
    dnsutils
    findutils
    iana-etc
    nettools
    util-linux
  ];

  # Use provided base packages or default
  actualBasePackages = if basePackages != null then basePackages else defaultBasePackages;

  # Base packages included in all Docker images
  # These provide essential runtime dependencies
  copyToRoot = pkgs.buildEnv {
    name = "image-root";
    paths = actualBasePackages ++ extraContents;
    pathsToLink = pathsToLink;
  };

  # Default environment variables
  defaultEnv = [
    "NO_COLOR=true" # suppress colored log output
    "RUST_BACKTRACE=full"
    "LD_LIBRARY_PATH=${libPath}"
    "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
  ];

  Env = defaultEnv ++ env;

  # Use buildImage on macOS to avoid fakeroot issues
  # buildLayeredImage requires fakeroot which doesn't work on recent macOS
  buildImageArgs = {
    inherit name copyToRoot tag;
    created = "now";
    config = { inherit Cmd Entrypoint Env; };
  };

  buildLayeredImageArgs = {
    inherit name tag;
    created = "now";
    contents = copyToRoot;
    config = { inherit Cmd Entrypoint Env; };
  };
in
if pkgs.stdenv.hostPlatform.isDarwin then
  pkgs.dockerTools.buildImage buildImageArgs
else
  pkgs.dockerTools.buildLayeredImage buildLayeredImageArgs
