fn main() {
    rust_builder_native::assert_build_environment();
    let version = rust_builder_native::c_openssl_version();
    assert!(version > 0);
    assert_eq!(version, rust_builder_native::rust_openssl_version());
    println!(
        "host={} target={} openssl={version}",
        env!("BUILD_HOST"),
        env!("BUILD_TARGET")
    );
}
