param(
    [Parameter(Mandatory = $true)][string]$GameExecutable,
    [Parameter(Mandatory = $true)][string]$LauncherExecutable
)

$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator confirmation is required to apply the LAN firewall rules.'
}
$gamePath = (Get-Item -LiteralPath $GameExecutable).FullName
$launcherPath = (Get-Item -LiteralPath $LauncherExecutable).FullName
if ([IO.Path]::GetFileName($gamePath) -ine 'starwarsbattlefrontii.exe' -or
    [IO.Path]::GetFileName($launcherPath) -ine 'kyber_launcher.exe') {
    throw 'Unexpected executable name; no firewall rules were changed.'
}
$backupRoot = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($gamePath))) 'Backups'
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$blocked = @()
foreach ($programPath in @($gamePath, $launcherPath)) {
    $filters = Get-NetFirewallApplicationFilter -Program $programPath -ErrorAction SilentlyContinue
    foreach ($filter in $filters) {
        $blocked += @(Get-NetFirewallRule -AssociatedNetFirewallApplicationFilter $filter |
            Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Block' -and $_.Enabled -eq 'True' } |
            Select-Object Name, Enabled)
    }
}
$backupPath = Join-Path $backupRoot ('firewall-before-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
@($blocked) | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $backupPath -Encoding UTF8
foreach ($rule in $blocked) {
    Disable-NetFirewallRule -Name $rule.Name | Out-Null
}

$rules = @(
    @{ Name = 'KyberLAN-Game-UDP-LocalSubnet'; Program = $gamePath; Protocol = 'UDP'; LocalPort = @('25100', '25200-25350') },
    @{ Name = 'KyberLAN-Discovery-UDP-LocalSubnet'; Program = $launcherPath; Protocol = 'UDP'; LocalPort = @('25201') },
    @{ Name = 'KyberLAN-ModServer-TCP-LocalSubnet'; Program = $launcherPath; Protocol = 'TCP'; LocalPort = @('25202-25352') }
)
# VPN peers can be routed addresses outside the adapter's local subnet.
$lanAddresses = @(
    'LocalSubnet', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16',
    '25.0.0.0/8', '26.0.0.0/8', '100.64.0.0/10'
)
foreach ($rule in $rules) {
    $parameters = @{
        Name = $rule.Name
        Program = $rule.Program
        Protocol = $rule.Protocol
        LocalPort = $rule.LocalPort
        RemoteAddress = $lanAddresses
        Direction = 'Inbound'
        Action = 'Allow'
        Profile = 'Any'
        Enabled = 'True'
    }
    if (Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue) {
        Set-NetFirewallRule @parameters | Out-Null
    } else {
        New-NetFirewallRule @parameters -DisplayName $rule.Name -Group 'KyberLAN LAN Only' | Out-Null
    }
}
[PSCustomObject]@{
    Applied = $true
    Backup = $backupPath
    Rules = @($rules | ForEach-Object { $_.Name })
} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $backupRoot 'firewall-result.json') -Encoding UTF8
