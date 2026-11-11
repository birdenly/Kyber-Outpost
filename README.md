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

**Kyber Outpost** is a standalone LAN / Peer-to-Peer adaptation of [ArmchairDevelopers/Kyber](https://github.com/ArmchairDevelopers/Kyber) designed exclusively for local network play (`UDP :25200`), LAN server discovery (`UDP Broadcast :25201`), and local `.fbmod` synchronization between LAN hosts/peers (`HTTP :25202`).

| Directory | Description |
|-----------|-------------|
| `Module` | C++ game module (`Kyber.dll`) injected into the game client/server |
| `Launcher` | Flutter desktop application for LAN hosting, discovery, and mod management |
| `CLI` | Command-line interface tools for launching or hosting on LAN |
| `Packages` | Shared Dart packages (`kyber`, `kyber_collection`, `nexus_bridge`, `nexus_gql`) |
| `ThirdParty/Maxima` | Open-source local game launcher & LSX service |

## Building

See [BUILDING.md](BUILDING.md) for build instructions.

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)** — see the [LICENSE](LICENSE) file for details.

In accordance with **Section 5 of the GPL-3.0**, this repository is a modified version of [ArmchairDevelopers/Kyber](https://github.com/ArmchairDevelopers/Kyber) adapted for local LAN operation (modified in November 2026). All original copyright notices (`Copyright Armchair Developers / Sean Kahler`) remain in full effect.
