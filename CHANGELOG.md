# Changelog

## Kyber Outpost (LAN Edition)

- Converted Launcher, CLI, and Module (`Kyber.dll`) to a self-contained offline/LAN architecture.
- Added automatic local game discovery, offline emulator configuration (`anadius.cfg`), and local player profiles.
- Added LAN UDP server discovery, direct IP connection, and automatic HTTP `.fbmod` synchronization from the LAN host.
- Simplified the CLI (`start_game` and `start_server`) for direct LAN play.
- Added NexusMods Personal API Key login encrypted locally via Windows DPAPI.
- Fixed Ewok Hunt (`Mode3`) team balancing and round startup behavior for LAN matches.
- Removed cloud/central server dependencies, proxy networking, online telemetry/social services, and Vivox VoIP.
- Added System32 DirectX DLL preloading (`d3d11.dll`, `dxgi.dll`, `d3d9.dll`) and `--disable-gpu` WebView2 configuration in the Launcher to prevent conflicts with game directory DX11 proxies (such as SpecialK).
