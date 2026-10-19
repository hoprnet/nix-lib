use std::env;

fn record(name: &str, value: impl std::fmt::Display) {
    println!("cargo:rustc-env={name}={value}");
}

fn main() {
    let host = env::var("HOST").unwrap();
    let target = env::var("TARGET").unwrap();
    record("BUILD_HOST", &host);
    record("BUILD_TARGET", &target);
    record("HOST_OPENSSL_VERSION", openssl::version::number());

    let host_compiler = cc::Build::new().host(&host).target(&host).get_compiler();
    let mut target_build = cc::Build::new();
    let target_compiler = target_build.get_compiler();
    let target_cxx = cc::Build::new().cpp(true).get_compiler();
    record("SELECTED_HOST_CC", host_compiler.path().display());
    record("SELECTED_TARGET_CC", target_compiler.path().display());
    record("SELECTED_TARGET_CXX", target_cxx.path().display());

    for (platform, triple) in [("HOST", &host), ("TARGET", &target)] {
        let prefix = triple.replace('-', "_").to_uppercase();
        for suffix in ["LIB_DIR", "INCLUDE_DIR"] {
            let name = format!("{prefix}_OPENSSL_{suffix}");
            println!("cargo:rerun-if-env-changed={name}");
            record(
                &format!("SELECTED_{platform}_OPENSSL_{suffix}"),
                env::var(name).unwrap(),
            );
        }
    }
    for name in [
        "EXPECTED_HOST_CC",
        "EXPECTED_TARGET_CC",
        "EXPECTED_TARGET_CXX",
        "EXPECTED_HOST_OPENSSL_LIB_DIR",
        "EXPECTED_HOST_OPENSSL_INCLUDE_DIR",
        "EXPECTED_TARGET_OPENSSL_LIB_DIR",
        "EXPECTED_TARGET_OPENSSL_INCLUDE_DIR",
    ] {
        println!("cargo:rerun-if-env-changed={name}");
        record(name, env::var(name).unwrap());
    }

    let prefix = target.replace('-', "_").to_uppercase();
    target_build
        .include(env::var(format!("{prefix}_OPENSSL_INCLUDE_DIR")).unwrap())
        .file("src/probe.c")
        .compile("openssl_probe");
    println!("cargo:rerun-if-changed=src/probe.c");
}
