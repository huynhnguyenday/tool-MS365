[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fixturePath = [IO.Path]::GetFullPath((Join-Path $root ('package-test-' + [guid]::NewGuid().ToString('N') + '.tmp')))
function Assert-FixturePath {
    if ([IO.Path]::GetDirectoryName($fixturePath) -ine [IO.Path]::GetFullPath($root) -or [IO.Path]::GetFileName($fixturePath) -notmatch '^package-test-[a-f0-9]{32}\.tmp$') { throw 'Unexpected package test path.' }
}
Assert-FixturePath
New-Item -ItemType Directory -Path $fixturePath | Out-Null
$caseNumber = 0
function Invoke-FixtureBuild {
    $script:caseNumber++
    $output = Join-Path $fixturePath ('out-' + $script:caseNumber)
    & (Join-Path $fixturePath 'Build-Package.ps1') -OutputDirectory $output | Out-Null
    return Join-Path $output 'TeamsChannelManager-1.1.0.zip'
}
function Assert-BuildRejected {
    $rejected = $false
    try { Invoke-FixtureBuild | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unsafe package input was accepted.' }
}
try {
    Copy-Item -LiteralPath (Join-Path $root 'Build-Package.ps1') -Destination (Join-Path $fixturePath 'Build-Package.ps1')
    Set-Content -LiteralPath (Join-Path $fixturePath 'VERSION') -Value '1.1.0' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fixturePath 'UPDATE-MANIFEST.txt') -Value 'README.md' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fixturePath 'README.md') -Value 'Sample package fixture.' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fixturePath 'bulk-channel-members.csv') -Value @('Email', 'sample@contoso.com') -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fixturePath 'not-allowlisted.txt') -Value 'This file must not be packaged.' -Encoding ASCII
    $zipPath = Invoke-FixtureBuild
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $files = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
        if ($files.Count -ne 2 -or ($files | Where-Object { $_.FullName -like '*not-allowlisted*' })) { throw 'ZIP did not follow allowlist.' }
    }
    finally { $zip.Dispose() }
    foreach ($badManifest in @('../outside.ps1', 'data.csv', '.env', 'C:\outside.ps1', 'README.md:stream')) {
        Set-Content -LiteralPath (Join-Path $fixturePath 'UPDATE-MANIFEST.txt') -Value $badManifest -Encoding ASCII
        Assert-BuildRejected
    }
    Set-Content -LiteralPath (Join-Path $fixturePath 'UPDATE-MANIFEST.txt') -Value @('README.md', 'README.md') -Encoding ASCII
    Assert-BuildRejected
    Set-Content -LiteralPath (Join-Path $fixturePath 'UPDATE-MANIFEST.txt') -Value 'README.md' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fixturePath 'bulk-channel-members.csv') -Value @('Email', 'sample@example.com') -Encoding ASCII
    Assert-BuildRejected
    Set-Content -LiteralPath (Join-Path $fixturePath 'bulk-channel-members.csv') -Value @('Email,Name', 'sample@contoso.com,Sample') -Encoding ASCII
    Assert-BuildRejected
    Write-Output 'PASS package allowlist, traversal/private-path rejection, duplicate rejection and sample-only CSV enforcement.'
}
finally {
    Assert-FixturePath
    if (Test-Path -LiteralPath $fixturePath) {
        if ((Get-Item -LiteralPath $fixturePath).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unexpected reparse point in package test path.' }
        Remove-Item -LiteralPath $fixturePath -Recurse -Force
    }
}
