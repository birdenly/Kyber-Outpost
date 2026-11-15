# Local runtime and LAN networking

Kyber Outpost uses local player profiles and the offline Origin/EA emulator.
The Launcher and CLI share the runtime in `Packages/kyber_runtime`.

## Finding the game

The Launcher looks for `starwarsbattlefrontii.exe` beside its own executable,
then checks the Windows installation record:

- `HKLM\SOFTWARE\EA Games\STAR WARS Battlefront II`
- `HKLM\SOFTWARE\WOW6432Node\EA Games\STAR WARS Battlefront II`

A registered path is used only if the executable exists. The CLI can also
supply an explicit path through `--game-path`.

Install the complete Launcher package in the game folder. Merge its `data`
folder with the game's `Data` folder while preserving existing game files.
The installation needs a prepared executable, `anadius64.dll`, and an existing
Denuvo activation accepted on that computer. See [README.md](README.md) for setup.

## Player profile

Choose a nickname during the Local Player setup or by clicking the name at
the top right of the Launcher. It is saved in the current Launcher's settings.
The CLI accepts a nickname through `start_game --name`.

The frontend passes the nickname directly to the Rust runtime. The runtime
calculates stable local IDs from the trimmed, case-normalized name; these
IDs are independent of the activation owner's account. The game receives its
name through the launch parameters supplied by the runtime.

Names must contain 1 to 16 characters, without quotes, backslashes, or control
characters. The Launcher checks the room's live names before joining, and the
native server rejects duplicate nicknames. Close the game before changing its
profile.

## Configuration and activation

Before launch, the runtime creates or completes `anadius.cfg`:

- Adds missing required entries while preserving custom options and comments.
- Calculates SHA-1 fingerprints of the executable and the configured Denuvo DLL.
- Updates the local player name and IDs, existing activation token, and module path.
- Saves atomically, and skips writing when nothing changed.

The selected language must be installed. The game folder and configuration need
Modify permission for the current Windows user. Keep the configuration private
because it contains the local activation token.

The activation reader uses `1035052.dlf` in
`%ProgramData%\Electronic Arts\EA Services\License`, or
`1035052_cached.dlf` when the first is absent. It reads an existing activation;
it does not generate or renew one. If activation is rejected, use the original
game through its official store before preparing it again.

## Processes and dependencies

The runtime starts and tracks the game directly, confirms that `Kyber.dll`
loaded, and waits for its local RPC interface. No LSX server or EA account
service runs in Outpost.

- `discovery.rs`: portable installation and Windows registry detection.
- `license.rs`: existing local activation reader.
- `configuration.rs`: emulator configuration and file hashes.
- `process.rs`: child process lifecycle and module detection.
- `Launcher/rust/src/mod_download`: local ZIP downloader with the original
  Maxima authorship and GPL notices retained.

Maxima is no longer a project dependency. Some frontend class names retain that
name as internal compatibility aliases. The native module still requires
`vivoxsdk.dll` to load, although cloud voice is disabled.

## Networking

| Purpose | Default transport |
|---|---|
| Game | Direct UDP 25200 |
| Room discovery | UDP broadcast 25201 |
| Room information and mods | HTTP TCP 25202 |
| Launcher/module control | Local RPC |

The game and HTTP filters accept loopback, private IPv4 networks, link-local
addresses, `100.64.0.0/10`, `25.0.0.0/8`, and `26.0.0.0/8`.
HTTP also accepts local IPv6 addresses and the configured mod services.

For a virtual LAN, join the same VPN network and use DIRECT IP with the host's
VPN IPv4 address. Room discovery depends on broadcast routing. The firewall
helper permits the relevant LAN/VPN ranges for the specified game and Launcher
executables; updating the script does not modify rules already installed in Windows.

External account, telemetry, and cloud session services are disabled. Mod
downloads use their existing Nexus/ModBridge services. The HTTP filter rejects
other hosts before DNS resolution and on redirects, and bypasses HTTP proxies.
It is an application policy, not a system firewall.

## Verification

Run from the repository root:

```powershell
dart tool/verify_lan_network.dart
cargo test --offline --manifest-path Packages/kyber_runtime/Cargo.toml
cargo test --offline --manifest-path Launcher/rust/Cargo.toml mod_zip_can_be_listed_read_and_downloaded_without_maxima
```

The checks cover address filters, local HTTP and redirects, game discovery,
activation parsing, profile validation, configuration updates, process tracking,
and ZIP downloads. A match between remote computers through a VPN remains
unverified.
