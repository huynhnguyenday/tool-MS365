[CmdletBinding()]
param([string]$OutputDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $PSScriptRoot 'dist' }
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION must use major.minor.patch format.' }
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'UPDATE-MANIFEST.txt') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
if (@($manifest | Select-Object -Unique).Count -ne @($manifest).Count) { throw 'Duplicate update manifest entries.' }
$samplePath = Join-Path $PSScriptRoot 'bulk-channel-members.csv'
if ((Get-Content -LiteralPath $samplePath -TotalCount 1).Trim() -ne 'Email') { throw 'The packaged CSV must have only the Email column.' }
$sampleUsers = @(Import-Csv -LiteralPath $samplePath)
if (-not $sampleUsers.Count -or @($sampleUsers | Where-Object { $_.Email -notmatch '^[A-Za-z0-9._%+-]+@contoso\.com$' }).Count) { throw 'The packaged CSV must contain sample @contoso.com addresses only.' }
$tempDirectory = [IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
$staging = Join-Path $tempDirectory ("teams-channel-package-" + [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $staging "TeamsChannelManager-$version"
$zipPath = Join-Path $OutputDirectory "TeamsChannelManager-$version.zip"

try {
    New-Item -ItemType Directory -Path $packageRoot, $OutputDirectory -Force | Out-Null
    foreach ($relativePath in $manifest) {
        if ([IO.Path]::IsPathRooted($relativePath) -or $relativePath.Contains('..') -or $relativePath -match '[:*?<>|"]' -or $relativePath -match '(?i)\.(csv|lnk|log|pfx|p12|pem|key|cer|crt|der|bak|backup)$' -or $relativePath -match '(^|[/\\])\.') { throw "Unsafe program manifest entry: $relativePath" }
        $source = Join-Path $PSScriptRoot $relativePath
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing package file: $relativePath" }
        $destination = Join-Path $packageRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    Copy-Item -LiteralPath $samplePath -Destination (Join-Path $packageRoot 'bulk-channel-members.csv') -Force
    Compress-Archive -Path $packageRoot -DestinationPath $zipPath -Force
    Write-Host "Created $zipPath"
}
finally {
    if (Test-Path -LiteralPath $staging) {
        $resolvedStaging = [IO.Path]::GetFullPath($staging)
        if ([IO.Path]::GetDirectoryName($resolvedStaging) -ine $tempDirectory -or [IO.Path]::GetFileName($resolvedStaging) -notmatch '^teams-channel-package-[a-f0-9]{32}$' -or ((Get-Item -LiteralPath $resolvedStaging).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Refusing to delete an unexpected package staging path.' }
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
    }
}
