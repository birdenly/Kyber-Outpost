# Contributing to Kyber Outpost

Kyber Outpost is a LAN-focused project. Contributions, bug reports, and improvements that keep the local/LAN workflow simple and reliable are welcome.

## Code of Conduct

By participating in this repository, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Questions & Bug Reports

Before opening a new issue:

1. Read [README.md](README.md) and [BUILDING.md](BUILDING.md).
2. Check existing [Issues](https://github.com/birdenly/Kyber-Outpost/issues) to see if the problem has already been reported.

When opening an [Issue](https://github.com/birdenly/Kyber-Outpost/issues/new), include:

- What you expected to happen vs. what actually happened
- Steps to reproduce the issue in LAN mode
- Relevant logs from `%APPDATA%\KyberOutpost\Logs` or `%APPDATA%\KyberOutpost\Launcher\log.txt`
- Your Windows version and whether you are launching via the Launcher or CLI

> **Note:** Do not include personal tokens, API keys, or local activation files (`.dlf` / `anadius.cfg` tokens) in public issues or pull requests.

## Pull Requests

- Keep changes focused on offline/LAN functionality.
- Follow the code conventions in [STANDARDS.md](STANDARDS.md).
- Verify that the affected component (`Module`, `Launcher`, `CLI`, or `Packages`) builds and passes analysis/tests before submitting. Please test yourself, not only with agents.
- By submitting a contribution, you confirm that you have the right to license your changes under the project's [GPL-3.0 License](LICENSE).
