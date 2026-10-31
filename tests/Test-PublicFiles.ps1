[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Test-PublicFiles.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Find-PublicContentIssues', 'Test-PublicPath') }, $true) | ForEach-Object { Invoke-Expression $_.Extent.Text }
function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }
$examples = @(
    ('ghp_' + ('a' * 36)),
    ('github_pat_' + ('b' * 50)),
    (('eyJ' + ('a' * 20)) + '.' + ('eyJ' + ('b' * 20)) + '.' + ('c' * 20)),
    ('-----BEGIN ' + 'PRIVATE KEY-----'),
    ('client_secret' + ' = "' + ('z' * 20) + '"'),
    ('defaultPassword' + ' = "' + ('z' * 20) + '"'),
    ('<input id="passwordValue" value="' + ('z' * 20) + '">'),
    ('private.person' + '@' + 'business.invalid'),
    (('a' * 8) + '-' + ('b' * 4) + '-' + ('c' * 4) + '-' + ('d' * 4) + '-' + ('e' * 12))
)
foreach ($example in $examples) {
    $findings = @(Find-PublicContentIssues -Text $example -Path 'fixture.txt')
    Assert-True ($findings.Count -gt 0) 'A sensitive pattern was not detected.'
    Assert-True (-not ($findings -join ' ').Contains($example)) 'Sensitive text was printed in findings.'
}
Assert-True (@(Find-PublicContentIssues -Text 'sample@contoso.com user@odata.bind 11111111-1111-1111-1111-111111111111' -Path 'fixture.txt').Count -eq 0) 'Safe sample/schema content was rejected.'
foreach ($path in @('.env', '.env.local', '.local/password-reset.json', 'exports/result.csv', 'dist/output.zip', 'tool.lnk', 'secret.pem', '.update-backup/file.ps1', 'browser-profile-abc/Preferences', 'AGENTS.md')) {
    Assert-True (-not (Test-PublicPath $path)) 'A machine-local or private path was accepted.'
}
foreach ($path in @('README.md', 'CHANGELOG.md', '.gitignore', 'bulk-channel-members.csv', 'tests/member-picker.test.cjs', 'favicon-16.png')) {
    Assert-True (Test-PublicPath $path) 'A public source/sample path was rejected.'
}
Write-Output 'PASS public-file audit detects sensitive patterns, redacts values, permits samples/schema names and blocks private paths.'
