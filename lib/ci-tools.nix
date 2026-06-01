rec {
  names = [
    "lcov"
    "skopeo"
    "dive"
    "go-containerregistry"
    "shellcheck"
    "shfmt"
  ];

  mkPackages = pkgs: map (name: builtins.getAttr name pkgs) names;
}
