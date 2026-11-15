//! Flutter bridge for the Outpost local runtime.
use std::{path::Path, time::{Duration, Instant}};
use flutter_rust_bridge::for_generated::anyhow::{self, bail};
use kyber_local_runtime as runtime;
use crate::frb_generated::StreamSink;

pub struct ServiceImage { pub height: Option<u16>, pub width: Option<u16>, pub path: String }
pub struct ServiceAvatarList { pub small: ServiceImage, pub medium: ServiceImage, pub large: ServiceImage }
pub struct ServicePlayer {
    pub id: String, pub pd: String, pub psd: String,
    pub display_name: String, pub unique_name: String, pub nickname: String,
    pub avatar: Option<ServiceAvatarList>, pub relationship: String,
}

#[frb(non_opaque)]
pub enum BasicPresence { Unknown, Offline, Online, Dnd, Away }
#[frb(non_opaque)]
pub struct RtmPresence { pub player_id: String, pub basic: BasicPresence, pub status: String, pub game: Option<String> }

pub async fn initialize_runtime() -> anyhow::Result<()> {
    log::info!("Outpost local runtime ready");
    Ok(())
}

pub async fn get_local_profile(name: Option<String>) -> anyhow::Result<ServicePlayer> {
    if let Some(name) = name { runtime::set_player_name(&name)?; }
    let profile = runtime::local_profile();
    Ok(ServicePlayer {
        id: profile.id.clone(), pd: profile.id.clone(), psd: profile.id,
        display_name: profile.name.clone(), unique_name: profile.name.clone(), nickname: profile.name,
        avatar: None, relationship: "SELF".to_owned(),
    })
}

pub async fn check_game_installation() -> anyhow::Result<()> {
    runtime::discovery::find_game(runtime::GAME_SLUG, None)?;
    Ok(())
}

#[frb(sync)]
pub fn get_game_dir(game_slug: String) -> String {
    runtime::discovery::find_game(&game_slug, None).ok()
        .and_then(|path| path.parent().map(|dir| dir.to_string_lossy().into_owned()))
        .unwrap_or_default()
}

pub async fn start_game(game_slug: String, game_path_override: Option<String>, game_args: Option<Vec<String>>) -> anyhow::Result<u32> {
    runtime::process::start_game(&game_slug, game_path_override.as_deref(), game_args.unwrap_or_default())
}

pub async fn stop_game(pid: u32) -> anyhow::Result<()> { runtime::process::stop_game(pid) }

pub async fn wait_for_kyber_module(pid: u32, path: String) -> anyhow::Result<()> {
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        if !runtime::process::is_running(pid)? { bail!("The game exited before Kyber.dll was loaded. Check its local Denuvo activation."); }
        if runtime::process::module_loaded(pid, Path::new(&path))? { return Ok(()); }
        if Instant::now() >= deadline { bail!("The offline emulator did not load Kyber.dll within 30 seconds. Check the game installation and DLL dependencies."); }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

pub async fn game_events(pid: u32, game_sink: StreamSink<String>) -> anyhow::Result<()> {
    // Lifetime comes from our direct child handle, independently of Origin/LSX.
    while runtime::process::is_running(pid)? {
        if game_sink.add("GameRunning".to_owned()).is_err() { return Ok(()); }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
    runtime::process::forget_finished(pid)?;
    Ok(())
}

// Compatibility for existing offline UI models. These never use EA services.
pub async fn check_game_ownership() -> anyhow::Result<bool> { Ok(!get_game_dir(runtime::GAME_SLUG.to_owned()).is_empty()) }
pub async fn get_auth_token() -> String { "lan_offline_token".to_owned() }
pub async fn get_friend_list() -> anyhow::Result<Vec<ServicePlayer>> { Ok(Vec::new()) }
pub async fn set_rtm_presence(status: String) -> anyhow::Result<()> { let _ = status; Ok(()) }
pub async fn start_rtm_connection() -> anyhow::Result<()> { Ok(()) }
pub async fn get_rtm_presences(presence_sink: StreamSink<RtmPresence>) -> anyhow::Result<()> { let _ = presence_sink; Ok(()) }
pub async fn avatar_image(pd: &str, width: u16, height: u16) -> anyhow::Result<String> { let _ = (pd, width, height); Ok(String::new()) }
pub async fn get_user(pd: String) -> anyhow::Result<ServicePlayer> {
    let player = get_local_profile(None).await?;
    if pd != player.pd { bail!("Local player not found"); }
    Ok(player)
}
pub async fn search_user(name: String) -> anyhow::Result<ServicePlayer> { let _ = name; bail!("Account search is unavailable in LAN mode") }

#[frb(init)]
pub fn init_app() { flutter_rust_bridge::setup_default_user_utils(); }
flutter_logger::flutter_logger_init!(log::LevelFilter::Debug);

pub async fn get_short_token() -> anyhow::Result<String> { bail!("EA token exchange is disabled in LAN mode") }
pub async fn login_with_token(token: String) -> anyhow::Result<()> { let _ = token; bail!("EA login is disabled in LAN mode") }
pub async fn download_game(download_path: String, progress_sink: StreamSink<(usize, usize)>) -> anyhow::Result<()> { let _ = (download_path, progress_sink); bail!("Use an existing local game installation"); }
