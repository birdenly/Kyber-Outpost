//! Flutter bridge for the Outpost local runtime.
use std::{path::Path, time::{Duration, Instant}};
use flutter_rust_bridge::for_generated::anyhow::{self, bail};
use kyber_local_runtime as runtime;
use crate::frb_generated::StreamSink;

pub struct ServicePlayer {
    pub id: String,
    pub display_name: String,
    pub nickname: String,
}

pub async fn initialize_runtime() -> anyhow::Result<()> {
    log::info!("Outpost local runtime ready");
    Ok(())
}

pub async fn get_local_profile(name: Option<String>) -> anyhow::Result<ServicePlayer> {
    if let Some(name) = name { runtime::set_player_name(&name)?; }
    let profile = runtime::local_profile();
    Ok(ServicePlayer {
        id: profile.id,
        display_name: profile.name.clone(),
        nickname: profile.name,
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

#[frb(init)]
pub fn init_app() { flutter_rust_bridge::setup_default_user_utils(); }
flutter_logger::flutter_logger_init!(log::LevelFilter::Debug);
