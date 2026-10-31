$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path $PSScriptRoot -Parent) 'Start-PrivateChannelMembersUI.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-GraphPages' }, $true) | ForEach-Object { Invoke-Expression $_.Extent.Text }
$handler = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq "`$path -eq '/api/password-users' -and `$method -eq 'GET'" }, $true)
$text = $handler.Clauses[0].Item2.Extent.Text
$run = [scriptblock]::Create($text.Substring(1, $text.Length - 2))
$script:calls = @(); $script:result = $null; $script:failSecondPage = $false
function Invoke-MembershipGraphRequest {
    param($Method, $Uri, $Headers, $Trace)
    if ($Method -ne 'GET') { throw 'Directory access must be read-only' }
    $script:calls += $Uri
    if ($Uri -match 'skiptoken=next') {
        if ($script:failSecondPage) { throw 'Mock second-page failure' }
        return @{ value = @(@{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Alpha'; mail = 'alpha@contoso.com'; userPrincipalName = 'alpha@contoso.com' }) }
    }
    if ($Uri -notmatch '\$orderby=displayName' -or $Uri -notmatch '\$select=id,displayName,mail,userPrincipalName') { throw 'Unexpected directory query' }
    return @{ value = @(@{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'Zulu'; mail = 'zulu@contoso.com'; userPrincipalName = 'zulu@contoso.com' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=next' }
}
function Send-JsonResponse { param($Context, $Value) $script:result = $Value; throw 'CAPTURED' }
try { & $run } catch { if ($_.Exception.Message -ne 'CAPTURED') { throw } }
if ($script:calls.Count -ne 2 -or $script:result.users.Count -ne 2) { throw 'All directory pages must be returned' }
if ($script:result.users[0].displayName -ne 'Alpha' -or $script:result.users[1].displayName -ne 'Zulu') { throw 'Alphabetical ordering failed' }
if ($script:result.users[0].email -ne 'alpha@contoso.com') { throw 'Email mapping failed' }
$script:result = $null; $script:failSecondPage = $true; $rejected = $false
try { & $run } catch { $rejected = $_.Exception.Message -eq 'Mock second-page failure' }
if (!$rejected -or $null -ne $script:result) { throw 'Incomplete directory must not be returned as a success' }
Write-Output 'Password directory mocked checks passed: pagination, alphabetical order, basic profile fields, read-only and partial-load failure.'
