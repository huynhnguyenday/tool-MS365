$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path $PSScriptRoot -Parent) 'Start-PrivateChannelMembersUI.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Add-MembershipTrace' }, $true) | ForEach-Object { Invoke-Expression $_.Extent.Text }
$handler = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq "`$path -eq '/api/password-reset' -and `$method -eq 'POST'" }, $true)
$text = $handler.Clauses[0].Item2.Extent.Text
$run = [scriptblock]::Create($text.Substring(1, $text.Length - 2))
$script:calls = @()
$graphContext = @{ Scopes = @('User-PasswordProfile.ReadWrite.All') }
function Read-JsonBody { param($Request) $script:body }
function Send-JsonResponse { param($Context, $Value) $script:result = $Value; throw 'CAPTURED' }
function Invoke-MgGraphRequest {
    param($Method, $Uri, $Body, $ContentType)
    if ($Method -ne 'PATCH' -or $ContentType -ne 'application/json') { throw 'Unexpected request' }
    $script:calls += @{ uri = $Uri; payload = ($Body | ConvertFrom-Json) }
    if ($Uri.EndsWith('33333333-3333-3333-3333-333333333333')) {
        $failure = [System.Exception]::new('Mock permission failure ' + ($Body | ConvertFrom-Json).passwordProfile.password)
        $failure | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 403 })
        throw $failure
    }
}
function Invoke-Case { try { & $run } catch { if ($_.Exception.Message -ne 'CAPTURED') { throw } } }
$first = '22222222-2222-2222-2222-222222222222'
$second = '33333333-3333-3333-3333-333333333333'
$samplePassword = @('Sample', 'Initial', '123!') -join '-'
$script:body = @{ confirmed = $true; userIds = @($first, $second, $first); password = $samplePassword }
Invoke-Case
if ($script:calls.Count -ne 2 -or $script:result.results.Count -ne 2) { throw 'Deduplication failed' }
if (!$script:result.results[0].success -or $script:result.results[1].success) { throw 'Partial failure handling failed' }
if (!$script:result.results[1].message.Contains('HTTP 403')) { throw 'Safe HTTP status missing from failure details' }
foreach ($item in $script:result.results) {
    if ($item.trace.Count -ne 2 -or $item.trace[0].sequence -ne 1 -or $item.trace[1].sequence -ne 2) { throw 'Each person must have an ordered request/result trace' }
    if ($item.trace[0].command -notmatch 'PATCH' -or !$item.trace[0].command.Contains($item.id) -or !$item.trace[0].command.Contains('[REDACTED]')) { throw 'Missing redacted Graph command' }
    if (!$item.trace[0].time -or !$item.trace[1].time) { throw 'Missing trace timestamps' }
    $expected = if ($item.success) { 'success' } else { 'error' }
    if ($item.trace[1].status -ne $expected) { throw 'Trace result does not match Graph outcome' }
}
if (($script:result | ConvertTo-Json -Depth 10).Contains($script:calls[0].payload.passwordProfile.password)) { throw 'Actual password leaked in trace or error' }
if ($script:calls[0].payload.passwordProfile.forceChangePasswordNextSignIn -ne $false) { throw 'Next sign-in change must default to off' }
$customPassword = @('Sample', 'Custom', '123!') -join '-'
$script:calls = @()
$script:body = @{ confirmed = $true; userIds = @($first, $second); password = $customPassword }
Invoke-Case
if ($script:calls[0].payload.passwordProfile.password -cne $customPassword) { throw 'Custom password ignored' }
if (($script:result | ConvertTo-Json -Depth 6).Contains($customPassword)) { throw 'Custom password leaked in response' }
$script:calls = @()
$script:body = @{ confirmed = $true; userIds = @($first); password = $samplePassword; forceChangePasswordNextSignIn = $false }
Invoke-Case
if ($script:calls[0].payload.passwordProfile.forceChangePasswordNextSignIn -ne $false) { throw 'Unchecked option ignored' }
$script:calls = @()
$script:body = @{ confirmed = $true; userIds = @($first); password = $samplePassword; forceChangePasswordNextSignIn = $true }
Invoke-Case
if ($script:calls[0].payload.passwordProfile.forceChangePasswordNextSignIn -ne $true) { throw 'Checked option ignored' }
if (($script:result | ConvertTo-Json -Depth 10) -match 'Mock permission failure|Authorization:|Bearer ') { throw 'Sensitive request/error leaked' }
foreach ($case in @(
    @{ confirmed = $false; userIds = @($first); password = $samplePassword },
    @{ confirmed = 'true'; userIds = @($first); password = $samplePassword },
    @{ confirmed = $true; userIds = @($first, 'invalid'); password = $samplePassword },
    @{ confirmed = $true; userIds = @(); password = $samplePassword }
    @{ confirmed = $true; userIds = @($first); password = $samplePassword; forceChangePasswordNextSignIn = 'false' }
    @{ confirmed = $true; userIds = @($first) }
    @{ confirmed = $true; userIds = @($first); password = '' }
    @{ confirmed = $true; userIds = @($first); password = '   ' }
    @{ confirmed = $true; userIds = @($first); password = 123 }
)) {
    $script:body = $case; $script:calls = @(); $rejected = $false
    try { Invoke-Case } catch { $rejected = $true }
    if (!$rejected -or $script:calls.Count) { throw 'Unsafe request accepted' }
}
$script:body = @{ confirmed = $true; userIds = @($first); password = $samplePassword }
$graphContext.Scopes = @(); $rejected = $false
try { Invoke-Case } catch { $rejected = $true }
if (!$rejected -or $script:calls.Count) { throw 'Missing permission accepted' }
Write-Output 'Password reset mocked checks passed.'
