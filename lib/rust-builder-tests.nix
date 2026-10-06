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
        cmake,
        protobuf,
      }:
      craneLib.mkCargoDerivation {
        pname = "rust-builder-platform-check";
        version = "1.0.0";
        dontUnpack = true;
        buildPhaseCargoCommand = "";
        installPhaseCommand = ''touch "$out"'';
        cargoVendorDir = pkgs.emptyDirectory;
        cargoArtifacts = null;
        nativeBuildInputs = [
          cmake
          protobuf
          llvmPackages.llvm
        ];
        buildInputs = [ openssl ];
        passthru = {
          compiler = stdenv.cc.cc.outPath;
          staticCompiler = pkgs.pkgsStatic.stdenv.cc.cc.outPath;
          hostOpenssl = pkgs.pkgsBuildHost.openssl.outPath;
          namedOpensslHost = openssl.stdenv.hostPlatform.config;
          host = stdenv.hostPlatform.config;
          build = stdenv.buildPlatform.config;
          buildPackagesHost = pkgs.buildPackages.stdenv.hostPlatform.config;
          buildBuildHost = pkgs.pkgsBuildBuild.stdenv.hostPlatform.config;
          buildHostHost = pkgs.pkgsBuildHost.stdenv.hostPlatform.config;
          downloadHost =
            (craneLib.downloadCargoPackage {
              name = "platform-probe";
              version = "1.0.0";
              checksum = pkgs.lib.fakeSha256;
            }).stdenv.hostPlatform.config;
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
      hasNativeInput = input: lib.any (dep: dep.drvPath == input.drvPath) result.nativeBuildInputs;
      hostTarget = local.stdenv.hostPlatform.config;
    in
    {
      expr = {
        inherit (result)
          compiler
          host
          isStatic
          staticCompiler
          hostOpenssl
          build
          buildPackagesHost
          buildBuildHost
          buildHostHost
          downloadHost
          namedOpensslHost
          name
          ;
        nativeRust = lib.any (
          dep:
          (dep.pname or "") == rust.pname
          && dep.version == rust.version
          && dep.stdenv.hostPlatform.config == hostTarget
        ) result.nativeBuildInputs;
        nativeLlvm = hasNativeInput local.llvmPackages.llvm;
        nativeCmake = hasNativeInput local.cmake;
        nativeProtobuf = hasNativeInput local.protobuf;
        targetOpenssl = lib.any (dep: dep.stdenv.hostPlatform.config == expectedTarget) result.buildInputs;
        staticFlag = lib.hasInfix "+crt-static" result.CARGO_BUILD_RUSTFLAGS;
        targetCC = result."CC_${builtins.replaceStrings [ "-" ] [ "_" ] expectedTarget}";
        targetCXX = result."CXX_${builtins.replaceStrings [ "-" ] [ "_" ] expectedTarget}";
        hostCC = result.HOST_CC;
      };
      expected = {
        compiler = local.pkgsMusl.stdenv.cc.cc.outPath;
        nativeRust = true;
        nativeLlvm = true;
        nativeCmake = true;
        nativeProtobuf = true;
        targetOpenssl = true;
        staticCompiler = local.pkgsStatic.stdenv.cc.cc.outPath;
        hostOpenssl = local.pkgsBuildHost.openssl.outPath;
        host = expectedTarget;
        build = hostTarget;
        buildPackagesHost = hostTarget;
        buildBuildHost = hostTarget;
        buildHostHost = hostTarget;
        downloadHost = hostTarget;
        namedOpensslHost = expectedTarget;
        name = "rust-builder-platform-check-${expectedTarget}-1.0.0";
        isStatic = true;
        staticFlag = true;
        targetCC = "${local.pkgsMusl.stdenv.cc}/bin/cc";
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
  fixturePkgs = packageSet system;
  fixtureArgs = {
    src = project.mkSrc {
      root = ../tests/rust-builder-native;
      fs = lib.fileset;
      extraExtensions = [ "c" ];
    };
    depsSrc = project.mkDepsSrc {
      root = ../tests/rust-builder-native;
      fs = lib.fileset;
    };
    cargoToml = ../tests/rust-builder-native/Cargo.toml;
  };
  fixtureEnv = {
    EXPECTED_HOST_CC = "${fixturePkgs.stdenv.cc}/bin/cc";
    EXPECTED_TARGET_CC = "${fixturePkgs.pkgsMusl.stdenv.cc}/bin/cc";
    EXPECTED_TARGET_CXX = "${fixturePkgs.pkgsMusl.stdenv.cc}/bin/c++";
    EXPECTED_HOST_OPENSSL_LIB_DIR = "${fixturePkgs.openssl.out}/lib";
    EXPECTED_HOST_OPENSSL_INCLUDE_DIR = "${fixturePkgs.openssl.dev}/include";
    EXPECTED_TARGET_OPENSSL_LIB_DIR = "${fixturePkgs.pkgsStatic.openssl.out}/lib";
    EXPECTED_TARGET_OPENSSL_INCLUDE_DIR = "${fixturePkgs.pkgsStatic.openssl.dev}/include";
  };
  nativePackage =
    runTests:
    (nativeBuilder.callPackage project.mkRustPackage (fixtureArgs // { inherit runTests; }))
    .overrideAttrs
      (
        previous:
        fixtureEnv
        // {
          cargoArtifacts = previous.cargoArtifacts.overrideAttrs (_: fixtureEnv);
        }
      );
  nativeBinary = nativePackage false;
in
{
  rustBuilderUnit =
    assert lib.assertMsg (failures == [ ]) (builtins.toJSON failures);
    pkgs.runCommand "check-rust-builder-unit" { } ''touch "$out"'';
}
// lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  rustBuilderNativeIntegration = nativePackage true;
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
        python3 - "${nativeBinary}/bin/rust-builder-native" <<'PY'
        import struct
        import subprocess
        import sys
        from pathlib import Path
        binary = sys.argv[1]
        header = Path(binary).read_bytes()[:20]
        assert header[:4] == b"\x7fELF"
        assert struct.unpack("<H", header[18:20])[0] == ${
          if pkgs.stdenv.hostPlatform.isAarch64 then "183" else "62"
        }
        segments = subprocess.run(["readelf", "-l", binary], check=True, capture_output=True, text=True)
        dynamic = subprocess.run(["readelf", "-d", binary], check=True, capture_output=True, text=True)
        assert segments.stderr == "", segments.stderr
        assert dynamic.stderr == "", dynamic.stderr
        assert "INTERP" not in segments.stdout
        assert "NEEDED" not in dynamic.stdout
        completed = subprocess.run([binary], check=True, capture_output=True, text=True)
        assert completed.stderr == "", completed.stderr
        info = dict(field.split("=", 1) for field in completed.stdout.split())
        cpu = "${pkgs.stdenv.hostPlatform.parsed.cpu.name}"
        assert info["host"] == f"{cpu}-unknown-linux-gnu", info
        assert info["target"] == f"{cpu}-unknown-linux-musl", info
        assert int(info["openssl"]) > 0, info
        PY
        touch "$out"
      '';
}
