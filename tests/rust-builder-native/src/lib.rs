extern "C" {
    fn probe_openssl_version() -> std::os::raw::c_ulong;
}

pub fn c_openssl_version() -> u64 {
    unsafe { probe_openssl_version() as u64 }
}

pub fn rust_openssl_version() -> u64 {
    unsafe { openssl_sys::OpenSSL_version_num() as u64 }
}

pub fn assert_build_environment() {
    assert!(env!("BUILD_HOST").ends_with("-linux-gnu"));
    assert!(env!("BUILD_TARGET").ends_with("-linux-musl"));
    assert_eq!(env!("SELECTED_HOST_CC"), env!("EXPECTED_HOST_CC"));
    assert_eq!(env!("SELECTED_TARGET_CC"), env!("EXPECTED_TARGET_CC"));
    assert_eq!(env!("SELECTED_TARGET_CXX"), env!("EXPECTED_TARGET_CXX"));
    assert_eq!(
        env!("SELECTED_HOST_OPENSSL_LIB_DIR"),
        env!("EXPECTED_HOST_OPENSSL_LIB_DIR")
    );
    assert_eq!(
        env!("SELECTED_HOST_OPENSSL_INCLUDE_DIR"),
        env!("EXPECTED_HOST_OPENSSL_INCLUDE_DIR")
    );
    assert_eq!(
        env!("SELECTED_TARGET_OPENSSL_LIB_DIR"),
        env!("EXPECTED_TARGET_OPENSSL_LIB_DIR")
    );
    assert_eq!(
        env!("SELECTED_TARGET_OPENSSL_INCLUDE_DIR"),
        env!("EXPECTED_TARGET_OPENSSL_INCLUDE_DIR")
    );
    assert_ne!(
        env!("SELECTED_HOST_OPENSSL_LIB_DIR"),
        env!("SELECTED_TARGET_OPENSSL_LIB_DIR")
    );
    assert!(env!("HOST_OPENSSL_VERSION").parse::<u64>().unwrap() > 0);
}

#[cfg(test)]
mod tests {
    #[test]
    fn cargo_selects_gnu_host_and_musl_target_dependencies() {
        super::assert_build_environment();
    }

    #[test]
    fn c_and_rust_use_target_openssl() {
        assert!(super::c_openssl_version() > 0);
        assert_eq!(super::c_openssl_version(), super::rust_openssl_version());
    }
}
