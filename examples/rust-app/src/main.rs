use serde::{Deserialize, Serialize};
use std::env;

#[derive(Debug, Serialize, Deserialize)]
struct Info {
    name: String,
    version: String,
    platform: String,
}

fn main() {
    let info = Info {
        name: env!("CARGO_PKG_NAME").to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        platform: format!(
            "{}-{}",
            env::consts::OS,
            env::consts::ARCH
        ),
    };

    println!("=== Rust App Example ===");
    println!("{}", serde_json::to_string_pretty(&info).unwrap());
    println!("\nThis binary was built using the HOPR Nix Library!");
    println!("Git revision: {}", env!("VERGEN_GIT_SHA"));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_info_creation() {
        let info = Info {
            name: "test".to_string(),
            version: "1.0.0".to_string(),
            platform: "test-platform".to_string(),
        };
        assert_eq!(info.name, "test");
        assert_eq!(info.version, "1.0.0");
    }
}
