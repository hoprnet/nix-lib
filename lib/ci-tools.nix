{
  names = [
    "lcov"
    "skopeo"
    "dive"
    "go-containerregistry"
    "shellcheck"
    "shfmt"
  ];

  mkPackages =
    pkgs: with pkgs; [
      lcov # Code coverage
      skopeo # Container image tools
      dive # Docker layer analysis
      go-containerregistry # OCI image manipulation tool (includes crane and gcrane)
      shellcheck # Shell script linting
      shfmt # Shell script formatting
    ];
}
