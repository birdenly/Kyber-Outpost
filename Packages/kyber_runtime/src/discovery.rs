use std::{env, path::{Path, PathBuf}};
use anyhow::{bail, Result};

pub const GAME_EXE: &str = "starwarsbattlefrontii.exe";

fn executable(path: PathBuf) -> Option<PathBuf> {
    let path = if path.is_dir() { path.join(GAME_EXE) } else { path };
    path.is_file().then_some(path)
}

fn detect(launcher: Option<&Path>, cwd: Option<&Path>, registered: impl FnOnce() -> Vec<PathBuf>) -> Option<PathBuf> {
    if let Some(path) = launcher.and_then(|path| executable(path.with_file_name(GAME_EXE))) {
        return Some(path);
    }
    if let Some(path) = launcher.and_then(|path| path.parent()?.parent()).and_then(|dir| executable(dir.join(GAME_EXE))) {
        return Some(path);
    }
    if let Some(path) = cwd.and_then(|dir| executable(dir.join(GAME_EXE))) {
        return Some(path);
    }
    registered().into_iter().find_map(executable)
}

#[cfg(windows)]
fn registered_paths() -> Vec<PathBuf> {
    use winreg::{RegKey, enums::HKEY_LOCAL_MACHINE};
    let root = RegKey::predef(HKEY_LOCAL_MACHINE);
    let mut paths = Vec::new();
    for name in ["STAR WARS Battlefront II", super::GAME_SLUG] {
        for prefix in ["SOFTWARE\\EA Games", "SOFTWARE\\WOW6432Node\\EA Games"] {
            if let Ok(key) = root.open_subkey(format!("{}\\{}", prefix, name)) {
                if let Ok(path) = key.get_value::<String, _>("Install Dir") {
                    if !path.trim().is_empty() { paths.push(PathBuf::from(path)); }
                }
            }
        }
    }
    paths
}

#[cfg(not(windows))]
fn registered_paths() -> Vec<PathBuf> { Vec::new() }

pub fn find_game(slug: &str, explicit_path: Option<&str>) -> Result<PathBuf> {
    if slug != super::GAME_SLUG { bail!("Unsupported local game: {}", slug); }
    let explicit = explicit_path.map(PathBuf::from);
    let result = if let Some(path) = explicit {
        executable(path)
    } else {
        let cwd = env::current_dir().ok();
        detect(env::current_exe().ok().as_deref(), cwd.as_deref(), registered_paths)
    };
    result.ok_or_else(|| anyhow::anyhow!(
        "Battlefront II was not found beside the launcher or at the installation registered in Windows. Install the complete launcher beside starwarsbattlefrontii.exe."
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn portable_installation_wins_and_registry_skips_stale_paths() {
        let root = env::temp_dir().join(format!("outpost-path-{}-{}", std::process::id(), chrono::Utc::now().timestamp_nanos_opt().unwrap()));
        std::fs::create_dir_all(root.join("portable")).unwrap();
        std::fs::create_dir_all(root.join("registered")).unwrap();
        let launcher = root.join("portable/kyber_launcher.exe");
        let registered = root.join("registered");
        std::fs::write(registered.join(GAME_EXE), []).unwrap();
        assert_eq!(detect(Some(&launcher), None, || vec![root.join("missing"), registered.clone()]), Some(registered.join(GAME_EXE)));
        let portable = root.join("portable").join(GAME_EXE);
        std::fs::write(&portable, []).unwrap();
        assert_eq!(detect(Some(&launcher), None, || panic!("portable game must take priority")), Some(portable.clone()));
        let cli = root.join("portable/cli/kyber_cli.exe");
        std::fs::create_dir_all(cli.parent().unwrap()).unwrap();
        assert_eq!(detect(Some(&cli), None, || panic!("parent game must take priority")), Some(portable));
        std::fs::remove_dir_all(root).unwrap();
    }
}
