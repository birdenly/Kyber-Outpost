[CmdletBinding()]
param(
    [switch]$Offline,
    [ValidateRange(1, 32)][int]$Jobs = 4
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$setupBat = Join-Path $PSScriptRoot 'setup_outpost.bat'
if (!(Test-Path -LiteralPath $setupBat -PathType Leaf)) {
    throw "Setup script is missing: $setupBat"
}
$launcherRoot = Join-Path $repoRoot 'Launcher'
$buildRoot = Join-Path $launcherRoot 'build\windows\x64'
$releaseRoot = Join-Path $buildRoot 'runner\Release'
$logRoot = Join-Path $launcherRoot 'build\logs\windows-release'
$previousPath = $env:PATH
$previousFlutterRoot = $env:FLUTTER_ROOT
$previousCargoOffline = $env:CARGO_NET_OFFLINE

# CMake's install target replaces flutter_assets recursively. Keep its prefix
# explicitly inside this workspace, including when reusing an older CMake cache.
if (![IO.Path]::GetFullPath($releaseRoot).StartsWith(
    $launcherRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The release directory must stay inside Launcher.'
}
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Invoke-BuildCommand {
    param([string]$Name, [string]$Executable, [string[]]$ArgumentList,
        [switch]$AllowFailure)
    $logPath = Join-Path $logRoot "$Name.log"
    Write-Host "Building $Name..."
    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell turns native stderr (including compiler warnings)
        # into ErrorRecords. The native exit code determines success.
        $ErrorActionPreference = 'Continue'
        & $Executable @ArgumentList *> $logPath
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0 -and !$AllowFailure) {
        Get-Content -LiteralPath $logPath -Tail 35 | Write-Host
        throw "$Name failed ($exitCode). See $logPath"
    }
    return [PSCustomObject]@{ ExitCode = $exitCode; LogPath = $logPath }
}

function Initialize-PluginJunctions {
    $metadataFile = Join-Path $launcherRoot '.flutter-plugins-dependencies'
    if (!(Test-Path -LiteralPath $metadataFile)) {
        throw 'Flutter dependencies are missing. Bootstrap the workspace first (see BUILDING.md).'
    }
    $metadata = Get-Content -LiteralPath $metadataFile -Raw | ConvertFrom-Json
    # Flutter prepares both enabled desktop platforms even for a Windows build.
    foreach ($platformName in @('windows', 'linux')) {
        if (!(Test-Path -LiteralPath (Join-Path $launcherRoot $platformName))) {
            continue
        }
        $linkRoot = Join-Path $launcherRoot "$platformName\flutter\ephemeral\.plugin_symlinks"
        New-Item -ItemType Directory -Path $linkRoot -Force | Out-Null
        foreach ($plugin in $metadata.plugins.$platformName) {
            if ($plugin.name -notmatch '^[a-zA-Z0-9_]+$') {
                throw 'Invalid plugin name in Flutter metadata.'
            }
            $linkPath = Join-Path $linkRoot $plugin.name
            $targetPath = [IO.Path]::GetFullPath($plugin.path).TrimEnd('\')
            if (!(Test-Path -LiteralPath $targetPath -PathType Container)) {
                throw "Plugin source is missing: $($plugin.name). Restore Flutter dependencies first."
            }
            $link = Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
            if ($link) {
                if (!($link.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    throw "Expected a plugin link, found a regular file or directory: $linkPath"
                }
                $existingTarget = [IO.Path]::GetFullPath([string]$link.Target[0]).TrimEnd('\')
                if ($existingTarget -eq $targetPath) {
                    continue
                }
                # Remove only the link; never recurse into the dependency cache.
                [IO.Directory]::Delete($linkPath, $false)
            }
            New-Item -ItemType Junction -Path $linkPath -Target $targetPath | Out-Null
        }
    }
}

Push-Location $launcherRoot
try {
    $cargoDirectory = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cargo\bin'
    if (Test-Path -LiteralPath $cargoDirectory) {
        $env:PATH = "$cargoDirectory;$env:PATH"
    }
    $cargo = (Get-Command cargo -ErrorAction Stop).Source
    $flutter = (Get-Command flutter -ErrorAction Stop).Source
    $env:FLUTTER_ROOT = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($flutter)) '..'))
    $cargoOptions = @('build', '--release')
    if ($Offline) {
        $cargoOptions += '--offline'
        $env:CARGO_NET_OFFLINE = 'true'
    }
    $null = Invoke-BuildCommand -Name 'rust-bridge' -Executable $cargo -ArgumentList (
        $cargoOptions + @('--manifest-path', (Join-Path $launcherRoot 'rust\Cargo.toml')))

    if (!(Get-Command nuget -ErrorAction SilentlyContinue)) {
        New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
        $nugetExe = Join-Path $buildRoot 'nuget.exe'
        if (!(Test-Path -LiteralPath $nugetExe -PathType Leaf)) {
            Write-Host 'Downloading nuget.exe for flutter_inappwebview_windows...'
            Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $nugetExe
        }
        $env:PATH = "$buildRoot;$env:PATH"
    }

    Initialize-PluginJunctions
    $flutterOptions = @('--suppress-analytics', 'build', 'windows', '--release', '--no-pub', '--config-only')
    $prepared = Invoke-BuildCommand -Name 'flutter-config' -Executable $flutter -ArgumentList $flutterOptions -AllowFailure
    if ($prepared.ExitCode -ne 0 -and
        (Select-String -LiteralPath $prepared.LogPath -SimpleMatch 'symlink support' -Quiet)) {
        # A changed dependency list can cause Flutter to recreate its links.
        Initialize-PluginJunctions
        $prepared = Invoke-BuildCommand -Name 'flutter-config' -Executable $flutter -ArgumentList $flutterOptions -AllowFailure
    }
    if ($prepared.ExitCode -ne 0 -and !(Select-String -LiteralPath $prepared.LogPath -SimpleMatch (
        'Does not match the generator used previously') -Quiet)) {
        Get-Content -LiteralPath $prepared.LogPath -Tail 35 | Write-Host
        throw "Flutter configuration failed. See $($prepared.LogPath)"
    }

    $cachePath = Join-Path $buildRoot 'CMakeCache.txt'
    $cache = Get-Content -LiteralPath $cachePath
    $generator = ($cache | Select-String '^CMAKE_GENERATOR:INTERNAL=(.+)$').Matches.Groups[1].Value
    $cmake = ($cache | Select-String '^CMAKE_COMMAND:INTERNAL=(.+)$').Matches.Groups[1].Value
    if (!$generator -or !(Test-Path -LiteralPath $cmake)) {
        throw "No usable CMake toolchain was found in $cachePath"
    }
    Write-Host "Using $generator and $cmake"
    if (Test-Path -LiteralPath $releaseRoot) {
        Remove-Item -LiteralPath $releaseRoot -Recurse -Force
    }
    $null = Invoke-BuildCommand -Name 'cmake-config' -Executable $cmake -ArgumentList @(
        '-S', (Join-Path $launcherRoot 'windows'), '-B', $buildRoot, '-G', $generator,
        '-A', 'x64', '-DFLUTTER_TARGET_PLATFORM=windows-x64', "-DCMAKE_INSTALL_PREFIX:PATH=$releaseRoot")
    # flutter_inappwebview_windows restores WebView2/WIL/nlohmann.json from NuGet
    # in a separate target that its plugin library does not depend on. Building
    # only kyber_launcher on a clean machine would skip it, so restore first.
    $null = Invoke-BuildCommand -Name 'plugin-deps' -Executable $cmake -ArgumentList @(
        '--build', $buildRoot, '--config', 'Release', '--target', 'flutter_inappwebview_windows_DEPS')
    # Build the complete target graph (same as `flutter build windows`) so every
    # plugin and generated target is built, not only kyber_launcher's direct deps.
    $null = Invoke-BuildCommand -Name 'launcher' -Executable $cmake -ArgumentList @(
        '--build', $buildRoot, '--config', 'Release', '--target', 'ALL_BUILD', '--parallel', "$Jobs")
    $null = Invoke-BuildCommand -Name 'install' -Executable $cmake -ArgumentList @(
        '--install', $buildRoot, '--config', 'Release', '--component', 'Runtime', '--prefix', $releaseRoot)

    $runtimeFiles = @(
        $setupBat,
        (Join-Path $PSScriptRoot 'allow_lan_firewall.ps1'),
        (Join-Path $repoRoot 'LICENSE'),
        (Join-Path $launcherRoot 'rust\target\release\rust_lib.dll'),
        (Join-Path $repoRoot 'Module\bazel-bin\Kyber.dll'),
        (Join-Path $launcherRoot 'third_party\libs\UnRAR.dll'),
        (Join-Path $launcherRoot 'third_party\libs\7z.dll')
    )
    foreach ($source in $runtimeFiles) {
        if (!(Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Required runtime file is missing: $source"
        }
        $destination = Join-Path $releaseRoot ([IO.Path]::GetFileName($source))
        Copy-Item -LiteralPath $source -Destination $destination -Force
        if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
            throw "Runtime copy failed verification: $destination"
        }
    }
    foreach ($required in @('kyber_launcher.exe', 'flutter_windows.dll', 'data\app.so', 'data\icudtl.dat')) {
        if (!(Test-Path -LiteralPath (Join-Path $releaseRoot $required) -PathType Leaf)) {
            throw "The release is incomplete: $required"
        }
    }
    $manifestFiles = @(Get-ChildItem -LiteralPath $releaseRoot -File) + @(
        Get-Item -LiteralPath (Join-Path $releaseRoot 'data\app.so')
        Get-Item -LiteralPath (Join-Path $releaseRoot 'data\icudtl.dat')
    )
    $manifest = $manifestFiles | ForEach-Object {
        if ($_.Name -ne 'build-manifest.json') {
            [PSCustomObject]@{ File = $_.FullName.Substring($releaseRoot.Length + 1); Bytes = $_.Length; SHA256 = (Get-FileHash -LiteralPath $_.FullName).Hash }
        }
    }
    $manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $releaseRoot 'build-manifest.json') -Encoding UTF8
    Write-Host "Release ready: $(Join-Path $releaseRoot 'kyber_launcher.exe')"
} finally {
    $env:PATH = $previousPath
    $env:FLUTTER_ROOT = $previousFlutterRoot
    $env:CARGO_NET_OFFLINE = $previousCargoOffline
    Pop-Location
}
