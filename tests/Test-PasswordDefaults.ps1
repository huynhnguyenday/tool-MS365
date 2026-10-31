$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$root = Split-Path $PSScriptRoot -Parent
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Start-PrivateChannelMembersUI.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-PasswordResetSettings' }, $true) | ForEach-Object { Invoke-Expression $_.Extent.Text }
$fixture = [IO.Path]::GetFullPath((Join-Path $root ('password-default-test-' + [guid]::NewGuid().ToString('N') + '.tmp')))
try {
    New-Item -ItemType Directory -Path (Join-Path $fixture '.local') -Force | Out-Null
    if ((Get-PasswordResetSettings -RootDirectory $fixture).defaultPassword -ne '') { throw 'Fresh installs must not contain a default credential' }
    $sample = @('Sample', 'Local', '123!') -join '-'
    $settingsPath = Join-Path $fixture '.local/password-reset.json'
    [IO.File]::WriteAllText($settingsPath, (@{ defaultPassword = $sample } | ConvertTo-Json))
    if ((Get-PasswordResetSettings -RootDirectory $fixture).defaultPassword -cne $sample) { throw 'Local setting was not loaded' }
    [IO.File]::WriteAllText($settingsPath, '{ defaultPassword: INVALID_PRIVATE_VALUE }')
    $failed = $false
    try { Get-PasswordResetSettings -RootDirectory $fixture | Out-Null } catch { $failed = $true; if ($_.Exception.Message.Contains('INVALID_PRIVATE_VALUE')) { throw 'Raw local settings leaked in error' } }
    if (!$failed) { throw 'Malformed settings accepted' }
    Write-Output 'PASS password defaults: clean fresh install, local-only setting and redacted malformed-config error.'
}
finally {
    if ([IO.Path]::GetDirectoryName($fixture) -ine [IO.Path]::GetFullPath($root) -or [IO.Path]::GetFileName($fixture) -notmatch '^password-default-test-[a-f0-9]{32}\.tmp$') { throw 'Refusing unexpected fixture cleanup' }
    if (Test-Path -LiteralPath $fixture) {
        if ((Get-Item -LiteralPath $fixture).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unexpected fixture reparse point' }
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
