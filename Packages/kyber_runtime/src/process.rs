use std::{collections::HashMap, env, path::{Path, PathBuf}, process::{Child, Command}, sync::{Mutex, OnceLock}};
use anyhow::{ensure, Context, Result};
use chrono::Datelike;

static GAMES: OnceLock<Mutex<HashMap<u32, Child>>> = OnceLock::new();

fn games() -> &'static Mutex<HashMap<u32, Child>> {
    GAMES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn track(mut command: Command) -> Result<u32> {
    let child = command.spawn().context("Could not start the local game process")?;
    let pid = child.id();
    games().lock().unwrap().insert(pid, child);
    Ok(pid)
}

pub fn start_game(slug: &str, path_override: Option<&str>, arguments: Vec<String>) -> Result<u32> {
    ensure!(cfg!(windows), "The local game runtime currently supports Windows only");
    let path = super::discovery::find_game(slug, path_override)?;
    let module = env::var_os("KYBER_MODULE_PATH").map(PathBuf::from)
        .or_else(|| env::current_exe().ok().map(|path| path.with_file_name("Kyber.dll")))
        .context("Could not locate the bundled Kyber.dll")?;
    // This remains a read of the machine's existing activation, never a renewal.
    let license = super::license::load_local_license()?;
    let profile = super::local_profile();
    super::configuration::prepare(&path, &module, &license.game_token, &profile)?;
    let today = chrono::Utc::now();
    let time = (104729 * today.year() as u32) ^ (224737 * today.month()) ^ (350377 * today.day());
    let handshake = time ^ (time << 16) ^ (time >> 16);
    let mut command = Command::new(&path);
    command.args(arguments).current_dir(path.parent().unwrap())
        .env("EAAuthCode", "unavailable")
        .env("EAEgsProxyIpcPort", "0")
        .env("EAEntitlementSource", "EA")
        .env("EAExternalSource", "EA")
        .env("EAFreeTrialGame", "false")
        .env("EAGameLocale", "en_US")
        .env("EAGenericAuthToken", "")
        .env("EALaunchCode", "unavailable")
        .env("EALaunchOwner", "EA")
        .env("EALaunchEAID", &profile.name)
        .env("EALaunchEnv", "production")
        .env("EALaunchOfflineMode", "true")
        .env("EALaunchUserAuthToken", "lan_offline_token")
        .env("EAAccessTokenJWS", "lan_offline_token")
        .env("EASecureLaunchTokenTemp", &license.user_id)
        .env("EARtPLaunchCode", handshake.to_string())
        .env("EASteamProxyIpcPort", "0")
        .env("ContentId", super::CONTENT_ID)
        .env("EAConnectionId", super::CONTENT_ID)
        .env("EALicenseToken", super::CONTENT_ID)
        .env("EAOnErrorExitRetCode", "1")
        // The offline emulator owns the SDK integration; there is no LSX server.
        .env_remove("EALsxPort").env_remove("MXLaunchId");
    log::info!("Starting local Battlefront II: {}", path.display());
    track(command)
}

pub fn is_running(pid: u32) -> Result<bool> {
    let mut tracked = games().lock().unwrap();
    match tracked.get_mut(&pid) {
        Some(child) => Ok(child.try_wait()?.is_none()),
        None => Ok(false),
    }
}

pub fn forget_finished(pid: u32) -> Result<()> {
    let mut tracked = games().lock().unwrap();
    if let Some(child) = tracked.get_mut(&pid) {
        ensure!(child.try_wait()?.is_some(), "The game is still running");
    }
    tracked.remove(&pid);
    Ok(())
}

pub fn stop_game(pid: u32) -> Result<()> {
    let mut tracked = games().lock().unwrap();
    if let Some(mut child) = tracked.remove(&pid) {
        if child.try_wait()?.is_none() { child.kill()?; }
        child.wait()?;
    }
    Ok(())
}

#[cfg(windows)]
pub fn module_loaded(pid: u32, expected: &Path) -> Result<bool> {
    use std::mem;
    use winapi::um::{handleapi::{CloseHandle, INVALID_HANDLE_VALUE}, tlhelp32::{CreateToolhelp32Snapshot, Module32FirstW, Module32NextW, MODULEENTRY32W, TH32CS_SNAPMODULE, TH32CS_SNAPMODULE32}};
    unsafe {
        let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
        if snapshot == INVALID_HANDLE_VALUE { return Ok(false); }
        struct Snapshot(winapi::um::winnt::HANDLE);
        impl Drop for Snapshot { fn drop(&mut self) { unsafe { CloseHandle(self.0); } } }
        let _guard = Snapshot(snapshot);
        let mut entry: MODULEENTRY32W = mem::zeroed();
        entry.dwSize = mem::size_of::<MODULEENTRY32W>() as u32;
        let expected = expected.to_string_lossy().replace('/', "\\").to_lowercase();
        let mut found = Module32FirstW(snapshot, &mut entry);
        while found != 0 {
            let length = entry.szExePath.iter().position(|c| *c == 0).unwrap_or(entry.szExePath.len());
            let path = String::from_utf16_lossy(&entry.szExePath[..length]).replace('/', "\\").to_lowercase();
            if path == expected { return Ok(true); }
            found = Module32NextW(snapshot, &mut entry);
        }
        Ok(false)
    }
}

#[cfg(not(windows))]
pub fn module_loaded(_pid: u32, _expected: &Path) -> Result<bool> {
    anyhow::bail!("Module verification currently supports Windows only")
}

#[cfg(all(test, windows))]
mod tests {
    use super::*;
    use std::{os::windows::process::CommandExt, time::{Duration, Instant}};
    #[test]
    fn direct_child_is_tracked_and_its_exit_is_observed_without_bootstrap() {
        let mut command = Command::new("cmd.exe");
        command.args(["/C", "exit", "23"]).creation_flags(0x08000000);
        let pid = track(command).unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        while is_running(pid).unwrap() {
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(10));
        }
        assert_eq!(games().lock().unwrap().get_mut(&pid).unwrap().try_wait().unwrap().unwrap().code(), Some(23));
        forget_finished(pid).unwrap();
        assert!(!is_running(pid).unwrap());
    }
}
