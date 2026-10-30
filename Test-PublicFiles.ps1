[CmdletBinding()]
param([string]$PackagePath = '')

$ErrorActionPreference = 'Stop'
function Find-PublicContentIssues {
    param([string]$Text, [string]$Path)
    $issues = [System.Collections.Generic.List[string]]::new()
    $rules = @{
        'private key' = '-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----'
        'GitHub token' = '\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b'
        'JWT token' = '\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b'
        'literal credential' = '(?i)\b(?:client[_-]?secret|access[_-]?token|refresh[_-]?token|api[_-]?key|password)\b\s*[=:]\s*["''][^"''\r\n]{8,}["'']'
    }
    $lines = $Text -split '\r?\n'
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        foreach ($rule in $rules.Keys) {
            if ($line -match $rules[$rule]) { $issues.Add("$Path`:$($index + 1): $rule") }
        }
        foreach ($match in [regex]::Matches($line, '(?i)(?<![A-Z0-9._%+-])[A-Z0-9._%+-]+@([A-Z0-9.-]+\.[A-Z]{2,})')) {
            if ($match.Value -ceq 'user@odata.bind') { continue } # Microsoft Graph JSON property, not an email.
            $domain = $match.Groups[1].Value
            if ($domain -notmatch '^(?i:contoso\.com|example\.(?:com|org|net)|(?:users\.)?noreply\.github\.com)$') { $issues.Add("$Path`:$($index + 1): non-sample email") }
        }
        foreach ($match in [regex]::Matches($line, '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b')) {
            if ($match.Value -notmatch '^([0-9])\1{7}-\1{4}-\1{4}-\1{4}-\1{12}$') { $issues.Add("$Path`:$($index + 1): non-placeholder resource/tenant ID") }
        }
    }
    return $issues.ToArray()
}
function Test-PublicPath {
    param([string]$Path)
    $normalized = $Path.Replace('\', '/')
    if ($normalized -match '(?i)(^|/)(dist|\.update-backup|\.git|\.codex|\.agents|\.auth|\.secrets|node_modules|__pycache__|.*browser.*profile[^/]*)/' -or
        $normalized -match '(?i)(^|/)(AGENTS\.md|UXUI-AGENT\.md|\.env(?:\..*)?|Thumbs\.db|Desktop\.ini)$' -or
        $normalized -match '(?i)\.(lnk|tmp|log|bak|backup|old|pfx|p12|pem|key|cer|crt|der|zip|7z)$') { return $false }
    if ($normalized -match '(?i)\.csv$' -and $normalized -cne 'bulk-channel-members.csv') { return $false }
    return $true
}
function Test-PublicTextFile {
    param([string]$Path)
    return [IO.Path]::GetExtension($Path) -notin @('.png', '.ico', '.woff2')
}

$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid VERSION.' }
$changelog = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'CHANGELOG.md') -Raw -Encoding UTF8
if ($changelog -notmatch ('(?m)^##\s+' + [regex]::Escape($version) + '\s')) { throw 'Current version is missing from CHANGELOG.md.' }
$manifest = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'UPDATE-MANIFEST.txt') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
if ($manifest.Count -ne @($manifest | Select-Object -Unique).Count) { throw 'Duplicate manifest paths.' }
foreach ($file in $manifest) {
    if ([IO.Path]::IsPathRooted($file) -or $file.Contains('..') -or $file -match '[:*?<>|"]' -or -not (Test-PublicPath $file) -or $file -match '(?i)\.csv$') { throw "Unsafe program manifest path: $file" }
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) { throw "Missing manifest file: $file" }
}
$sample = @(Import-Csv -LiteralPath (Join-Path $PSScriptRoot 'bulk-channel-members.csv'))
if ((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bulk-channel-members.csv') -TotalCount 1).Trim() -ne 'Email') { throw 'Sample CSV must have only the Email column.' }
if (-not $sample.Count -or @($sample | Where-Object { $_.Email -notmatch '^[A-Za-z0-9._%+-]+@contoso\.com$' }).Count) { throw 'Sample CSV contains non-sample users.' }

$publicFiles = @(git -C $PSScriptRoot ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate tracked/untracked public Git files.' }
$issues = [System.Collections.Generic.List[string]]::new()
$trackedIgnored = @(git -C $PSScriptRoot ls-files --cached --ignored --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect tracked files matching private/local ignore rules.' }
foreach ($file in $trackedIgnored) { $issues.Add("${file}: tracked file matches a private/local ignore rule; remove it from Git tracking") }
foreach ($file in ($publicFiles | Select-Object -Unique)) {
    if (-not (Test-PublicPath $file)) { $issues.Add("${file}: machine-local/private path must not be tracked"); continue }
    $path = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    if (Test-PublicTextFile $file) {
        foreach ($issue in @(Find-PublicContentIssues -Text ([IO.File]::ReadAllText($path)) -Path $file)) { $issues.Add($issue) }
    }
}
$emails = @(git -C $PSScriptRoot log -1 '--format=%ae%n%ce')
if ($LASTEXITCODE -ne 0 -or $emails.Count -ne 2 -or @($emails | Where-Object { $_ -notmatch '@(?:users\.)?noreply\.github\.com$' }).Count) { $issues.Add('Latest commit author/committer must use GitHub noreply email before public push.') }

if ($PackagePath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $PackagePath).Path)
    try {
        $expectedFiles = @($manifest) + @('bulk-channel-members.csv')
        $seen = [System.Collections.Generic.List[string]]::new()
        $prefix = "TeamsChannelManager-$version/"
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name.EndsWith('/')) { continue }
            if (-not $name.StartsWith($prefix, [StringComparison]::Ordinal)) { $issues.Add('ZIP has an unexpected root directory.'); continue }
            $relative = $name.Substring($prefix.Length)
            if ($relative -notin $expectedFiles -or $relative -in $seen) { $issues.Add("ZIP/$relative`: unexpected or duplicate package file") }
            $seen.Add($relative)
            if ($relative -in $expectedFiles) {
                $entryStream = $entry.Open()
                $hasher = [Security.Cryptography.SHA256]::Create()
                try {
                    $archiveHash = [BitConverter]::ToString($hasher.ComputeHash($entryStream)).Replace('-', '')
                    if ($archiveHash -ne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $relative) -Algorithm SHA256).Hash) { $issues.Add("ZIP/$relative`: differs from checked source file") }
                }
                finally { $entryStream.Dispose(); $hasher.Dispose() }
            }
            if (Test-PublicTextFile $relative) {
                $reader = [IO.StreamReader]::new($entry.Open())
                try { foreach ($issue in @(Find-PublicContentIssues -Text $reader.ReadToEnd() -Path "ZIP/$relative")) { $issues.Add($issue) } }
                finally { $reader.Dispose() }
            }
        }
        foreach ($expected in $expectedFiles) { if ($expected -notin $seen) { $issues.Add("ZIP/$expected`: missing package file") } }
    }
    finally { $archive.Dispose() }
}
if ($issues.Count) {
    foreach ($issue in ($issues | Select-Object -Unique)) { Write-Output $issue }
    throw 'Public-file verification failed. Values are intentionally omitted from findings.'
}
Write-Output "PASS: public Git files, secret/email/resource-ID checks, noreply metadata, v$version changelog, update manifest and sample CSV."
if ($PackagePath) { Write-Output 'PASS: ZIP contains exactly the allowlisted program files plus sample CSV; packaged text scan is clean.' }
