<h1 align="center">Kyber Outpost</h1>
<h4 align="center">KYBER is an Open-Source Private Server tool for STAR WARS™ Battlefront™ II (2017).</h4>
<p align="center">
  <a href="https://www.youtube.com/watch?v=l2NHgabpnXg">Jedha, Kyber, Erso</a>
</p>

------

> [!IMPORTANT]
> **This project is made strictly for LAN use. Its objective is NOT to update, improve, replace, or compete with KYBER in any way, shape, or form. All credit and recognition for the original work go to the creators/maintainers and contributors of KYBER:**
>
> **Creators / Maintainers:**
> - [Liam (@7reax)](https://github.com/7reax): API, CLI, Launcher, Packages, Proxy
> - [Magix (@MagixGames)](https://github.com/MagixGames): Module
>
> **Contributors:**
> - [ArmchairDevelopers/Kyber Contributors](https://github.com/ArmchairDevelopers/Kyber/graphs/contributors)
>
> <a href="https://github.com/ArmchairDevelopers/Kyber/graphs/contributors">
>   <img src="https://contrib.rocks/image?repo=ArmchairDevelopers/Kyber" />
> </a>
>
> **If you encounter any issues, please do not contact them — this project is not theirs to maintain or support.**

------

## Overview

**Kyber Outpost** is a LAN version of [Kyber V2](https://github.com/ArmchairDevelopers/Kyber). It uses the offline **anadius emulator** to launch the game and lets you host or join matches on the same network. Kyber Outpost still needs a legit copy with valid denuvo tokens, this will not change, this isnt a crack.

Outpost adds these features to the original Kyber V2 workflow:

- **LAN server discovery:** find rooms on your network or connect to the host's local IP address.
- **Local player profiles:** choose a nickname in the Launcher. Each name gets its own player ID.
- **LAN mod sharing:** synchronize the host's selected mods over the local network. This mean one player can download the mods and transfer to others instead of, for example, downloading 4x.
- **Portable installation:** runs Kyber Outpost directly from the game folder, with automatic detection of the adjacent executable.
- **Automatic emulator configuration:** maintain `anadius.cfg`, including file hashes, the local player profile, and the computer's existing activation.
- **Standalone local launch:** start games without an EA login in Outpost or a Maxima service.

Matches use your local network. Internet is needed for installation, official activation (denuvo), and downloading new mods from external services.

## How to play

Repeat setup on each computer that will join the match.

### 1. Install and activate the game

1. Install **STAR WARS Battlefront II (2017)** through the store where you own it.
2. Launch the original game through that store with internet available and wait until it reaches the main menu.

Kyber Outpost reuses the existing Denuvo activation on each computer. It does not create or renew an activation. If it expires or is rejected, launch the original game through its store again.

### 2. Install Outpost

Extract the **complete Windows release package** into the game folder, beside `starwarsbattlefrontii.exe`. Keep all included DLLs and folders. For example:

```text
C:\Program Files\EA Games\STAR WARS Battlefront II
```

Merge the release's `data` folder with the game's existing `Data` folder, preserving the game files.

Obtain these tools separately and place them in the same folder:

- Origin Unwrapper: `origin_unwrapper.exe` and its supplied support files.
- Origin emulator: the offline **`anadius64.dll`**.

Both tools are by **anadius** and are obtained separately. Links will not be given here, find it in a certain Steam Underground Community

### 3. Prepare the game

1. Close the game and Outpost. Start with the original `starwarsbattlefrontii.exe` in the game folder.
2. Run **[setup_outpost.bat](tool/setup_outpost.bat)** from that folder.
3. Wait for **Setup complete**. After the Unwrapper succeeds, the BAT saves the original as `starwarsbattlefrontii.exe.backup` and replaces the game executable with the prepared output, keeping the name **`starwarsbattlefrontii.exe`** so Kyber Outpost recognizes it.

Run the BAT once on the original executable. It prepares the game, saves the backup, and replaces the executable automatically. If preparation or backup fails, it stops before replacement. If writing under `Program Files` is denied, run the BAT as administrator.

To restore the original game, close the game and Outpost, move the prepared executable out of the folder, and rename `starwarsbattlefrontii.exe.backup` to `starwarsbattlefrontii.exe`.

Your folder should now contain the prepared game executable, `anadius64.dll`, and the complete Outpost package:

```text
STAR WARS Battlefront II\
|-- starwarsbattlefrontii.exe
|-- starwarsbattlefrontii.exe.backup
|-- dbdata.dll
|-- anadius64.dll
|-- kyber_launcher.exe
|-- Kyber.dll
|-- rust_lib.dll
|-- other release DLLs
|-- setup_outpost.bat
|-- Data\
'-- Patch\
...
```

### 4. Choose your player name

Open **kyber_launcher.exe**. In the **Local Player** step, choose your nickname and save it to continue to the optional Nexus Mods setup. You can change your name later by clicking it at the top right of the Launcher.

Names must be different within a room and contain 1 to 16 characters. Close the game before changing your name. Nexus sign-in is optional and is used for mod downloads.

The Launcher creates or completes **`anadius.cfg`** when starting the game.

Existing language settings and custom options are preserved. To select an installed language before the first launch, you can create this minimal `anadius.cfg`:

```text
"Config2"
{
    "Game"
    {
        "Language" "en_US"
    }
}
```

### 5. Game Setup

1. Connect all players to the same Ethernet or Wi-Fi network.
2. Allow the game and Launcher through Windows Firewall on your **Private** network.
3. Host a Match with whatever cofig you want.
Keep the host's Launcher open during the match so other players can find the room and receive its information and mods.
4. Joining: On another computer, open **HOME**, refresh the server list, and select the host's room.

If the room does not appear, use **DIRECT IP** with the host's local IPv4 address and game port, for example `192.168.1.50:25200`.

### Virtual LAN

For players on different networks, Outpost accepts Radmin VPN (`26.x.x.x`), Hamachi (`25.x.x.x`), and VPNs using private IPv4 addresses or `100.64.0.0/10`. Join the same virtual network and use **DIRECT IP** with the host's VPN address, for example `26.10.20.30:25200`. Automatic room discovery depends on the VPN's broadcast support.

Allow the game and Launcher through the VPN adapter's firewall. The [firewall helper](tool/allow_lan_firewall.ps1) includes these address ranges; rerun it if you previously used an older version. Playing between remote computers requires internet through the VPN. Virtual LAN gameplay has not yet been tested between two computers.

## Mods

New mods needs connection to NexusMods for downloads.

The host selects the mods. Kyber Outpost shares the required mod files over the LAN to other players.

## Troubleshooting

| Problem | What to check |
|---|---|
| Game not found | Place the Launcher beside `starwarsbattlefrontii.exe`, or check the game's Windows installation record. |
| Unwrapper fails | Check its output, support files, and that the input is the original executable. |
| Configuration cannot be saved | Give your Windows user Modify permission for the game folder and `anadius.cfg`. Program Files gave me problems with this. |
| Activation missing or rejected | Restore the original executable, run the game through the official store on this computer, then repeat. This is related to denuvo, the game needs to be legit. |
| Bad DLL hash | Start through Outpost to calculate the hashes. Check that `dbdata.dll` exists in the game folder. |
| Room missing or connection fails | Check both firewalls, the host's IP address, and Wi-Fi client isolation. Try DIRECT IP. |
| Missing VanillaBundleAggregation.kb | Supply the compatible file or launch without mods. |

The default LAN ports are **UDP 25200** for the game, **UDP 25201** for discovery, and **TCP 25202** for room information and mods. A [firewall helper](tool/allow_lan_firewall.ps1) is available for configuring rules manually.

## Building

See [BUILDING.md](BUILDING.md) for build instructions. Local Windows builds are placed in `Launcher/build/windows/x64/runner/Release`.

## License

[GPL-3.0](LICENSE)
