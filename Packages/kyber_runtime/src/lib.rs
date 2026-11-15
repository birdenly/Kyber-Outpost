//! Local game runtime shared by the Outpost launcher and CLI.
//! No account client, license server, LSX server or background service.
pub mod discovery;
pub mod license;
pub mod process;
mod configuration;

use std::sync::{OnceLock, RwLock};
use anyhow::{ensure, Result};

static PLAYER_NAME: OnceLock<RwLock<String>> = OnceLock::new();

fn player_name() -> &'static RwLock<String> {
    PLAYER_NAME.get_or_init(|| RwLock::new("OutpostPlayer".to_owned()))
}

pub fn set_player_name(name: &str) -> Result<()> {
    let name = name.trim();
    ensure!(!name.is_empty() && name.chars().count() <= 16 &&
        !name.chars().any(|c| c == '"' || c == '\\' || c.is_control()),
        "Choose a nickname with 1 to 16 characters, without quotes, backslashes or control characters.");
    *player_name().write().unwrap() = name.to_owned();
    Ok(())
}

pub const GAME_SLUG: &str = "star-wars-battlefront-2";
pub const CONTENT_ID: &str = "1035052";

pub struct LocalProfile {
    pub id: String,
    pub name: String,
}

fn lan_profile_id(name: &str) -> String {
    let mut hash = 14695981039346656037u64;
    for byte in name.trim().to_lowercase().bytes() {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(1099511628211);
    }
    // Local SDK identity, independent of the owner of the existing activation.
    // Keep it positive and exactly representable by the game's UI.
    ((hash & ((1u64 << 52) - 1)) | (1u64 << 52)).to_string()
}

pub fn local_profile() -> LocalProfile {
    let name = player_name().read().unwrap().clone();
    let id = lan_profile_id(&name);
    LocalProfile {
        name,
        id,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn local_profile_uses_the_selected_name_and_rejects_invalid_updates() {
        set_player_name(" Player Two ").unwrap();
        let profile = local_profile();
        assert_eq!(profile.name, "Player Two");
        assert_eq!(profile.id, lan_profile_id("Player Two"));
        for name in ["", "bad\"name", "bad\\name", "bad\nname", "a-name-that-is-too-long"] {
            assert!(set_player_name(name).is_err());
        }
        assert_eq!(local_profile().id, profile.id);
        set_player_name("OutpostPlayer").unwrap();
    }

    #[test]
    fn local_sdk_id_follows_the_nickname_and_fits_ui_numbers() {
        let first = lan_profile_id("OutpostPlayer");
        assert_eq!(first, lan_profile_id(" outpostplayer "));
        assert_ne!(first, lan_profile_id("OutpostPlayer 2"));
        let id = first.parse::<u64>().unwrap();
        assert!(id >= 1 << 52 && id < 1 << 53);
        assert_eq!((id as f64) as u64, id);
    }
}
