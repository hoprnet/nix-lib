{
  libForSystem,
  nixpkgs,
  pkgs,
  system,
  rust-overlay,
}:
let
  lib = pkgs.lib;
  packageSet =
    localSystem:
    import nixpkgs {
      inherit localSystem;
      overlays = [ rust-overlay.overlays.default ];
    };
  snapshot =
    builder:
    builder.callPackage (
      {
        stdenv,
        craneLib,
        isCross,
        isStatic,
        llvmPackages,
        pkgs,
        openssl,
      }:
      stdenv.mkDerivation {
        name = "rust-builder-platform-check";
        dontUnpack = true;
        installPhase = ''touch "$out"'';
        cargoArtifacts = null;
        passthru = {
          compiler = stdenv.cc.cc.outPath;
          toolchain = craneLib.rustc.drvPath;
          buildLlvm = llvmPackages.llvm.outPath;
          staticCompiler = pkgs.pkgsStatic.stdenv.cc.cc.outPath;
          hostOpenssl = pkgs.pkgsBuildHost.openssl.outPath;
          namedOpenssl = openssl.outPath;
          host = stdenv.hostPlatform.config;
          inherit isCross isStatic;
        };
      }
    ) { };
  nativeCase =
    localSystem: target: expectedTarget:
    let
      local = packageSet localSystem;
      result = snapshot (((libForSystem localSystem).mkRustBuilders { }).${target});
      rust = local.rust-bin.stable.latest.default.override {
        targets = [ expectedTarget ];
        extensions = [ ];
      };
    in
    {
      expr = {
        inherit (result)
          compiler
          toolchain
          host
          isStatic
          buildLlvm
          staticCompiler
          hostOpenssl
          ;
        staticFlag = lib.hasInfix "+crt-static" result.CARGO_BUILD_RUSTFLAGS;
        targetCC = result."CC_${builtins.replaceStrings [ "-" ] [ "_" ] expectedTarget}";
        namedOpenssl = result.namedOpenssl;
        targetCXX = result."CXX_${builtins.replaceStrings [ "-" ] [ "_" ] expectedTarget}";
        hostCC = result.HOST_CC;
      };
      expected = {
        compiler = local.pkgsMusl.stdenv.cc.cc.outPath;
        toolchain = rust.drvPath;
        buildLlvm = local.llvmPackages.llvm.outPath;
        staticCompiler = local.pkgsStatic.stdenv.cc.cc.outPath;
        hostOpenssl = local.pkgsBuildHost.openssl.outPath;
        host = expectedTarget;
        isStatic = true;
        staticFlag = true;
        targetCC = "${local.pkgsMusl.stdenv.cc}/bin/cc";
        namedOpenssl = local.pkgsMusl.openssl.outPath;
        targetCXX = "${local.pkgsMusl.stdenv.cc}/bin/c++";
        hostCC = "${local.stdenv.cc}/bin/cc";
      };
    };
  crossCase =
    localSystem: target: crossSystem:
    let
      local = packageSet localSystem;
      targetPkgs = import nixpkgs {
        inherit localSystem;
        crossSystem = local.lib.systems.examples.${crossSystem};
        overlays = [ rust-overlay.overlays.default ];
      };
      result = snapshot (((libForSystem localSystem).mkRustBuilders { }).${target});
    in
    {
      expr = {
        inherit (result)
          compiler
          host
          isCross
          isStatic
          ;
      };
      expected = {
        compiler = targetPkgs.stdenv.cc.cc.outPath;
        host = targetPkgs.stdenv.hostPlatform.config;
        isCross = true;
        isStatic = true;
      };
    };
  failures = lib.runTests {
    testNativeAarch64Musl = nativeCase "aarch64-linux" "aarch64-linux" "aarch64-unknown-linux-musl";
    testNativeX86Musl = nativeCase "x86_64-linux" "x86_64-linux" "x86_64-unknown-linux-musl";
    testX86ToAarch64 = crossCase "x86_64-linux" "aarch64-linux" "aarch64-multiplatform-musl";
    testAarch64ToX86 = crossCase "aarch64-linux" "x86_64-linux" "musl64";
    testLocalBuilder = {
      expr = (snapshot (((libForSystem system).mkRustBuilders { }).local)).host;
      expected = (packageSet system).stdenv.hostPlatform.config;
    };
  };
  project = libForSystem system;
  builders = project.mkRustBuilders { };
  nativeBuilder =
    if pkgs.stdenv.hostPlatform.isAarch64 then builders.aarch64-linux else builders.x86_64-linux;
  src = project.mkSrc {
    root = ../examples/rust-app;
    fs = lib.fileset;
  };
  depsSrc = project.mkDepsSrc {
    root = ../examples/rust-app;
    fs = lib.fileset;
  };
  packageArgs = {
    inherit src depsSrc;
    cargoToml = ../examples/rust-app/Cargo.toml;
    rev = "musl-builder-test";
  };
  binary = nativeBuilder.callPackage project.mkRustPackage packageArgs;
in
{
  rustBuilderUnit =
    assert lib.assertMsg (failures == [ ]) (builtins.toJSON failures);
    pkgs.runCommand "check-rust-builder-unit" { } ''touch "$out"'';
}
// lib.optionalAttrs pkgs.stdenv.isLinux {
  rustBuilderIntegration = binary.overrideAttrs {
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      # The example exposes tests through a binary target.
      cargoWithProfile test -p rust-app --bin rust-app
      runHook postCheck
    '';
  };
  rustBuilderCIntegration = nativeBuilder.callPackage (
    {
      stdenv,
      pkgs,
      binutils,
      craneLib,
      isCross,
      isStatic,
    }:
    stdenv.mkDerivation {
      name = "check-rust-builder-c-integration";
      cargoArtifacts = null;
      dontUnpack = true;
      dontPatchELF = true;
      nativeBuildInputs = [ binutils ];
      buildInputs = [ pkgs.pkgsStatic.openssl ];
      buildPhase = ''
        target="''${CARGO_BUILD_TARGET//-/_}"
        compilerVariable="CC_$target"
        "''${!compilerVariable}" -static-pie -x c -o test-c - -lcrypto -ldl -pthread <<'C'
        #include <openssl/crypto.h>
        int main(void) { return OpenSSL_version_num() == 0; }
        C
      '';
      doCheck = true;
      checkPhase = ''
        ./test-c
        readelf -l test-c > segments
        readelf -d test-c > dynamic
        [[ "$(< segments)" != *INTERP* ]]
        [[ "$(< dynamic)" != *NEEDED* ]]
      '';
      installPhase = ''cp test-c "$out"'';
    }
  ) { };
  rustBuilderEndToEnd =
    pkgs.runCommand "check-rust-builder-end-to-end"
      {
        nativeBuildInputs = [
          pkgs.binutils
          pkgs.python3
        ];
      }
      ''
        binary=${binary}/bin/rust-app
        readelf -l "$binary" > segments
        readelf -d "$binary" > dynamic
        python3 - "$binary" <<'PY'
        import json
        import struct
        import subprocess
        import sys
        from pathlib import Path
        with open(sys.argv[1], "rb") as executable:
            header = executable.read(20)
        expected_machine = ${if pkgs.stdenv.hostPlatform.isAarch64 then "183" else "62"}
        assert header[:4] == b"\x7fELF"
        assert struct.unpack("<H", header[18:20])[0] == expected_machine
        assert "INTERP" not in Path("segments").read_text()
        assert "NEEDED" not in Path("dynamic").read_text()
        completed = subprocess.run([sys.argv[1]], check=True, text=True, capture_output=True)
        assert completed.stderr == "", completed.stderr
        info, _ = json.JSONDecoder().raw_decode(completed.stdout.split("\n", 1)[1])
        assert info["name"] == "rust-app"
        assert info["platform"] == "linux-${pkgs.stdenv.hostPlatform.parsed.cpu.name}"
        assert "Git revision: musl-builder-test" in completed.stdout
        PY
        touch "$out"
      '';
}
