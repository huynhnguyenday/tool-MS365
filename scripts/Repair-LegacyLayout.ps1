[CmdletBinding()]
param(
    [string]$InstallDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$BackupDirectory = ''
)

$ErrorActionPreference = 'Stop'
$InstallDirectory = [IO.Path]::GetFullPath($InstallDirectory)
if (-not (Test-Path -LiteralPath (Join-Path $InstallDirectory 'app/Start-PrivateChannelMembersUI.ps1') -PathType Leaf)) { throw 'New application layout is missing.' }
if (-not $BackupDirectory) {
    $BackupDirectory = Join-Path $InstallDirectory ('.update-backup/layout-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
}
$manifest = @(Get-Content -LiteralPath (Join-Path $InstallDirectory 'UPDATE-MANIFEST.txt') | ForEach-Object { $_.Trim() })
# Keep the old root icon for existing renamed/Desktop shortcuts.
$retiredFiles = @('Start-PrivateChannelMembersUI.ps1', 'private-channel-members.html', 'private-channel-members.css', 'fontawesome.min.css', 'fontawesome-solid.min.css', 'fa-solid-900.woff2', 'FONT-AWESOME-LICENSE.txt', 'favicon.ico', 'favicon-16.png', 'favicon-32.png', 'Create-TeamsChannelManagerShortcut.ps1', 'Add-PrivateChannelMembers.ps1', 'Build-Package.ps1')
foreach ($relativePath in $retiredFiles) {
    $oldFile = Join-Path $InstallDirectory $relativePath
    if ($relativePath -notin $manifest -and (Test-Path -LiteralPath $oldFile -PathType Leaf)) {
        if ((Get-Item -LiteralPath $oldFile).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing to migrate linked file: $relativePath" }
        New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        Copy-Item -LiteralPath $oldFile -Destination (Join-Path $BackupDirectory $relativePath) -Force
        Remove-Item -LiteralPath $oldFile -Force
    }
}
