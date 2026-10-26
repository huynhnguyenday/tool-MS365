[CmdletBinding()]
param([string]$OutputDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $PSScriptRoot 'dist' }
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'UPDATE-MANIFEST.txt') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("teams-channel-package-" + [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $staging "TeamsChannelManager-$version"
$zipPath = Join-Path $OutputDirectory "TeamsChannelManager-$version.zip"

try {
    New-Item -ItemType Directory -Path $packageRoot, $OutputDirectory -Force | Out-Null
    foreach ($relativePath in $manifest) {
        $source = Join-Path $PSScriptRoot $relativePath
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing package file: $relativePath" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $packageRoot $relativePath) -Force
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bulk-channel-members.csv') -Destination (Join-Path $packageRoot 'bulk-channel-members.csv') -Force
    Compress-Archive -Path $packageRoot -DestinationPath $zipPath -Force
    Write-Host "Created $zipPath"
}
finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
