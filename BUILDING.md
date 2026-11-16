# Building Kyber Outpost

## Prerequisites

- Clone the repository.
- Download and install [Protoc](https://github.com/protocolbuffers/protobuf/releases) and ensure `protoc` is in your `PATH`

------

## Dart/Flutter Projects (Launcher, CLI, Packages)

### Prequisites
- [Flutter](https://flutter.dev) (master channel)
- [Rust](https://rustup.rs) (nightly toolchain)
- [Melos](https://melos.invertase.dev): `dart pub global activate melos`

### Bootstrapping (Required for Launcher & CLI)

Bootstrap the workspace from the repository root:

```bash
melos bootstrap
```

This installs dependencies, generates proto bindings, and runs code generation.

## Launcher (Flutter)

### Generating FFI Bindings

Generate the Rust bridge and the local FFI bindings:
```bash
cd Launcher
flutter_rust_bridge_codegen generate
dart run tool/ffigen.dart
```

### Run in Debug Mode

From the launcher directory, run:
```bash
flutter run
```

### Build Release Binaries

For Windows, run the build helper from the repository root after bootstrapping:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build_launcher_windows.ps1 -Offline
```

The helper builds the Rust bridge with the local Outpost runtime, prepares plugin directory
junctions for the enabled desktop platforms, and reuses the Visual Studio generator
and CMake executable from the build cache. This avoids the generator mismatch when
Visual Studio 2022 and 2026 are both installed. It builds the application and its
FFI plugins before installing the runtime files into
`Launcher/build/windows/x64/runner/Release` with an explicit install prefix.

The folder includes `setup_outpost.bat` and `allow_lan_firewall.ps1` from `tool`,
the license, the rebuilt `rust_lib.dll`, the previously built
`Module/bazel-bin/Kyber.dll`, its native
Vivox DLL dependency, and the local archive libraries. Build the module first if that DLL does not exist or its
source has changed. `build-manifest.json` records the packaged binary hashes.
Logs are written to `Launcher/build/logs/windows-release`.

`-Offline` tells Cargo to use its dependency cache. Omit it if Rust dependencies
need to be downloaded. Flutter dependencies and generated bindings must already
exist; the helper does not run `pub get` or change the installed Flutter SDK.
Distribute the complete `Release` folder, including `data`, with the executable.
For a portable game installation, merge its contents into the game folder,
preserving the game's existing files. The launcher detects
`starwarsbattlefrontii.exe` beside itself before checking the Windows registry.
The launcher uses the offline emulator. Game preparation and a valid local Denuvo activation are
prerequisites, as described in [README.md](README.md).

Game launch currently supports Windows only.

## CLI (Flutter)

### Building the CLI

```powershell
cd CLI
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter_rust_bridge_codegen generate
cargo build --release --manifest-path rust/Cargo.toml
New-Item -ItemType Directory -Path build/windows-x64 -Force
dart compile exe bin/kyber_cli.dart -o build/windows-x64/kyber_cli.exe
Copy-Item rust/target/release/rust_lib.dll build/windows-x64
Copy-Item ../Module/bazel-bin/Kyber.dll build/windows-x64
Copy-Item ../Module/ThirdParty/vivox/SDK/Libraries/Release/x64/vivoxsdk.dll build/windows-x64
```

Build the module first. These commands output the portable CLI to
`CLI/build/windows-x64`.

### Using the Built CLI

Keep `rust_lib.dll`, `Kyber.dll`, and `vivoxsdk.dll` beside `kyber_cli.exe`.
The CLI detects the bundled module before falling back to its shared data folder.
An explicit `--module-path` takes priority.

The CLI uses `Packages/kyber_runtime`, shared with the Launcher. No Maxima
bootstrap or background service is required. Game launch currently supports
Windows and requires a prepared offline game installation and bundled Kyber DLL.

------

## Module (C++)

### Building the KYBER Module

The KYBER Module can only be compiled on Windows, with MSVC.

First, install [bazelisk](https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-windows-amd64.exe) and drop it into your `PATH` as `bazel.exe`.

There is a bug with the gRPC client version we're using in combination with Bazel's long build paths, which makes some build paths extend past the legacy Windows path limit. To work around this, make a folder named `bz` at the root of your drive. We'll be using this folder to store bazel's intermediary files.

Ensure you have [MSYS2](https://www.msys2.org/) installed to `C:\msys64`.

Run `bazel --output_user_root="C:\bz" build --config=release Kyber`. This will take a while. Once it's done, you should have `Module/bazel-bin/Kyber.dll`. You may alternatively run the `build.bat` file in the root by running `.\build.bat` and modifying the path to the correct drive.

**Important:** The module requires the `--config=release` flag. Building without it (i.e., in debug mode) will lead to crashes.

### Using the Built Module

The LAN Launcher loads `Kyber.dll` and `vivoxsdk.dll` beside its executable.
Run `tool/build_launcher_windows.ps1 -Offline` to package the rebuilt module in
`Launcher/build/windows/x64/runner/Release`, or copy the module there manually.
The copy in `C:/ProgramData/Kyber/Module` is only a fallback when no bundled DLL
exists. See [README.md](README.md) for game detection and offline preparation.

### Code Completion

The KYBER module is primarily developed using Visual Studio Code with the clangd extension. `compile_commands.json` can be generated by running `clangd/refresh.bat` while inside the `Module` folder.

## GitHub Actions

- **Build Outpost module** builds the Windows module and its runtime dependency.
  It is also reused by the frontend workflows, so their DLL comes from the same revision.
- **Build Outpost launcher** generates bindings and assets, verifies the local
  runtime and networking, and uploads the complete portable Release folder.
- **Build Outpost CLI** generates its bindings, builds the Windows CLI, bundles
  the Rust library and module, and checks the packaged executable with `--help`.

Run a workflow manually from the repository's Actions tab, or let its path filters
run it on a push or pull request. Download the package from the completed run's
artifacts. The workflows use standard Windows runners and require no custom
repository secrets, signing account, or Kyber publishing service.

The shared action in `.github/actions/setup-frontend` pins the tested Flutter
revision, Rust nightly, Protoc, and Rust/Dart code generators. Update that action
when changing build tool versions. CI packages are portable unsigned builds.
