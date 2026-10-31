[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Apply,
    [string]$Repository = 'huynhnguyenday/tool-MS365',
    [string]$InstallDirectory = '',
    [int]$ParentProcessId = 0,
    [int]$Port = 8765,
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if ([string]::IsNullOrWhiteSpace($InstallDirectory)) { $InstallDirectory = $PSScriptRoot }

function Get-InstalledVersion {
    $path = Join-Path $InstallDirectory 'VERSION'
    if (-not (Test-Path -LiteralPath $path)) { return [version]'0.0.0' }
    return [version]((Get-Content -LiteralPath $path -Raw).Trim())
}

function Get-RemoteVersion {
    $uri = "https://raw.githubusercontent.com/$Repository/main/VERSION?cache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    return [version]((Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent' = 'TeamsChannelManager-Updater' }).Trim())
}

$installed = Get-InstalledVersion
$latest = Get-RemoteVersion
$status = [ordered]@{
    repository = $Repository
    currentVersion = $installed.ToString()
    latestVersion = $latest.ToString()
    updateAvailable = $latest -gt $installed
}

if ($CheckOnly) {
    $status | ConvertTo-Json -Compress
    exit 0
}

if (-not $Apply) { throw 'Specify -CheckOnly or -Apply.' }
if ($latest -le $installed) {
    Write-Host "Version $installed is already current."
    exit 0
}

if ($ParentProcessId -gt 0) {
    Wait-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("teams-channel-update-" + [guid]::NewGuid().ToString('N'))
$zipPath = Join-Path $tempRoot 'source.zip'
$extractPath = Join-Path $tempRoot 'source'
$backupRoot = Join-Path $InstallDirectory '.update-backup'
$backupPath = Join-Path $backupRoot ("v$installed-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))

try {
    New-Item -ItemType Directory -Path $tempRoot, $extractPath, $backupPath -Force | Out-Null
    Invoke-WebRequest -Uri "https://github.com/$Repository/archive/refs/heads/main.zip" -OutFile $zipPath -Headers @{ 'User-Agent' = 'TeamsChannelManager-Updater' }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
    $sourceRoot = Get-ChildItem -LiteralPath $extractPath -Directory | Select-Object -First 1
    if (-not $sourceRoot) { throw 'Downloaded package does not contain a project directory.' }
    $manifestPath = Join-Path $sourceRoot.FullName 'UPDATE-MANIFEST.txt'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Downloaded package is missing UPDATE-MANIFEST.txt.' }
    $files = @(Get-Content -LiteralPath $manifestPath | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if (-not $files.Count -or @($files | Select-Object -Unique).Count -ne $files.Count) { throw 'Empty or duplicate update manifest.' }
    foreach ($relativePath in $files) {
        if ([System.IO.Path]::IsPathRooted($relativePath) -or $relativePath.Contains('..') -or $relativePath -match '[:*?<>|"\x00-\x1f]' -or $relativePath -match '(^|[/\\])\.' -or $relativePath -match '(?i)\.(csv|lnk|log|pfx|p12|pem|key|cer|crt|der|bak|backup)$') { throw "Unsafe manifest path: $relativePath" }
        $source = Join-Path $sourceRoot.FullName $relativePath
        $target = Join-Path $InstallDirectory $relativePath
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Package file missing: $relativePath" }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $backupFile = Join-Path $backupPath $relativePath
            $backupDirectory = Split-Path -Parent $backupFile
            New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $backupFile -Force
        }
    }
    foreach ($relativePath in $files) {
        $source = Join-Path $sourceRoot.FullName $relativePath
        $target = Join-Path $InstallDirectory $relativePath
        $targetDirectory = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
    & (Join-Path $InstallDirectory 'scripts/Repair-LegacyLayout.ps1') -InstallDirectory $InstallDirectory -BackupDirectory $backupPath
    Write-Host "Updated Teams Channel Manager from $installed to $latest. Backup: $backupPath"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
        if ([IO.Path]::GetDirectoryName($resolvedTempRoot) -ine [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') -or [IO.Path]::GetFileName($resolvedTempRoot) -notmatch '^teams-channel-update-[a-f0-9]{32}$' -or ((Get-Item -LiteralPath $resolvedTempRoot).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unexpected updater temporary directory.' }
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}

if ($Restart) {
    $launcher = Join-Path $InstallDirectory 'app/Start-PrivateChannelMembersUI.ps1'
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoLogo', '-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $launcher + '"'), '-Port', $Port) -WorkingDirectory $InstallDirectory -WindowStyle Hidden
}
