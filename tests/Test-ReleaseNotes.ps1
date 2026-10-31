[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Start-PrivateChannelMembersUI.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ReleaseNotes' }, $true)
Invoke-Expression $function.Extent.Text
function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }
$script:remoteCalls = 0
$script:failRemote = $false
function Invoke-RestMethod {
    param($Uri, $TimeoutSec, $Headers)
    $script:remoteCalls++
    Assert-True ($Uri -ceq 'https://raw.githubusercontent.com/huynhnguyenday/tool-MS365/main/CHANGELOG.md') 'Unexpected release source.'
    Assert-True ($TimeoutSec -eq 8) 'Network request must have a bounded timeout.'
    Assert-True ($Headers.Count -eq 1 -and $Headers.ContainsKey('User-Agent')) 'Release notes must not send credentials.'
    if ($script:failRemote) { throw 'Mock network unavailable' }
    return "## 1.2.0 - 2026-11-01`n- Sample feature"
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('teams-release-notes-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    [IO.File]::WriteAllText((Join-Path $fixture 'VERSION'), '1.1.0')
    [IO.File]::WriteAllText((Join-Path $fixture 'CHANGELOG.md'), "## 1.1.0 - 2026-10-31`n- Sample local fix", [Text.Encoding]::UTF8)
    $local = Get-ReleaseNotes -RootDirectory $fixture
    Assert-True ($local.currentVersion -eq '1.1.0' -and $local.localMarkdown.Contains('Sample local fix')) 'Local notes/version were not loaded.'
    Assert-True ($script:remoteCalls -eq 0 -and -not $local.remoteMarkdown) 'Local read must work without a network request.'
    [IO.File]::WriteAllText((Join-Path $fixture 'CHANGELOG.md'), "## 1.1.0 - 2026-10-31`n- Updated local note", [Text.Encoding]::UTF8)
    $updated = Get-ReleaseNotes -RootDirectory $fixture
    Assert-True ($updated.localMarkdown.Contains('Updated local note') -and -not $updated.localMarkdown.Contains('Sample local fix')) 'Each request must reread the current changelog without restarting the server.'
    [IO.File]::WriteAllText((Join-Path $fixture 'CHANGELOG.md'), "## 1.1.0 - 2026-10-31`n- Sample local fix", [Text.Encoding]::UTF8)
    $remote = Get-ReleaseNotes -RootDirectory $fixture -IncludeRemote
    Assert-True ($remote.remoteMarkdown.Contains('1.2.0') -and $remote.localMarkdown.Contains('Sample local fix')) 'Remote notes must preserve local history.'
    $script:failRemote = $true
    $offline = Get-ReleaseNotes -RootDirectory $fixture -IncludeRemote
    Assert-True ($offline.warning -and $offline.localMarkdown.Contains('Sample local fix') -and -not $offline.remoteMarkdown) 'Remote failure must fall back to local notes.'
    Remove-Item -LiteralPath (Join-Path $fixture 'CHANGELOG.md')
    $missing = Get-ReleaseNotes -RootDirectory $fixture
    Assert-True ($missing.warning -and -not $missing.localMarkdown) 'Missing local history should return a useful warning.'
    Write-Host 'PASS: local release notes without Graph/network, fixed remote source, timeout, no credentials, remote success, offline fallback and missing-file handling.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
