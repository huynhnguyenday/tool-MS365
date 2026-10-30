[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Start-PrivateChannelMembersUI.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$names = @('Add-MembershipTrace', 'Invoke-MembershipGraphRequest', 'Invoke-ExistingMembershipChange', 'Get-ScopedMembershipUsers', 'Get-GraphPages', 'Get-GraphPathValue', 'Get-GraphErrorText')
$ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names }, $true) | ForEach-Object { Invoke-Expression $_.Extent.Text }
$handler = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -eq "`$path -eq '/api/members' -and `$method -eq 'POST'" }, $true)
$handlerText = $handler.Clauses[0].Item2.Extent.Text
$handlerScript = [scriptblock]::Create($handlerText.Substring(1, $handlerText.Length - 2))
$script:calls = [System.Collections.Generic.List[object]]::new()
$uid = '22222222-2222-2222-2222-222222222222'
$otherUid = '33333333-3333-3333-3333-333333333333'

function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Read-JsonBody { param($Request) return $script:body }
function Send-JsonResponse { param($Context, $Value) $script:response = $Value; throw 'TEST_RESPONSE_CAPTURED' }
function Start-Sleep { param($Seconds) }
function Invoke-MgGraphRequest {
    param($Method, $Uri, $Body, $ContentType, $OutputType, $Headers)
    $script:calls.Add(@{ method = $Method; uri = $Uri; body = $Body })
    if ($script:failWrite -and $Method -ne 'GET') { throw 'Mock Graph write failure' }
    if ($script:failFirstMember -and $Method -ne 'GET' -and $Uri -match 'membership%2F%2Bid%3D$') { throw 'Mock first member failure' }
    if ($Method -ne 'GET') { return @{} }
    if ($script:paging -and $Uri -match '\?page=2$') { return @{ value = @(@{ userId = $otherUid; id = 'owner-membership'; displayName = 'Sample Owner'; email = 'owner@contoso.com'; roles = @('owner') }) } }
    if ($script:paging -and $Uri -match '/members$') {
        return @{ value = @(@{ userId = $uid; id = 'member-membership'; displayName = 'Sample Member'; email = 'member@contoso.com'; roles = @() }); '@odata.nextLink' = "$Uri`?page=2" }
    }
    if ($Uri -match '/channels\?') { return @{ value = @(@{ id = 'sample-channel'; displayName = 'Sample channel'; membershipType = 'private' }) } }
    if ($Uri -match '/channels/.+/members') { return @{ value = $script:channelMembers } }
    return @{ value = $script:teamMembers }
}
function Reset-Case([string]$Operation = 'add', [bool]$Private = $false) {
    $script:response = $null
    $script:calls.Clear()
    $script:failWrite = $false
    $script:failFirstMember = $false
    $script:paging = $false
    $script:teamMembers = @(@{ userId = $uid; id = 'membership/+id='; roles = @() })
    $script:channelMembers = @(@{ userId = $uid; id = 'channel/+id='; roles = @() })
    $script:body = @{
        operation = $Operation; confirmed = $true
        teamId = '11111111-1111-1111-1111-111111111111'
        users = @(@{ id = $uid; userPrincipalName = 'sample@contoso.com' })
        assignments = @(); teamAssignments = @(@{ userId = $uid; role = 'member' })
    }
    if ($Private) {
        $script:body.teamAssignments = @()
        $script:body.assignments = @(@{ channelId = 'sample-channel'; userId = $uid; role = 'member' })
    }
}
function Invoke-Case {
    try { & $handlerScript }
    catch { if ($_.Exception.Message -ne 'TEST_RESPONSE_CAPTURED') { throw } }
    Assert-True ($null -ne $script:response) 'No response captured.'
}
function Assert-Rejected {
    $rejected = $false
    try { & $handlerScript } catch { $rejected = $_.Exception.Message -ne 'TEST_RESPONSE_CAPTURED' }
    Assert-True $rejected 'Unsafe request was accepted.'
    Assert-True ($script:calls.Count -eq 0) 'Rejected request contacted Graph.'
}

foreach ($private in @($false, $true)) {
    Reset-Case 'remove' $private
    Invoke-Case
    Assert-True ($response.results[0].status -eq 'Removed') 'Remove failed.'
    $write = @($calls | Where-Object method -eq 'DELETE')
    Assert-True ($write.Count -eq 1 -and $null -eq $write[0].body) 'DELETE must have no body.'
    Assert-True ($write[0].uri -match '%2F%2Bid%3D$') 'Membership ID must be resolved and encoded.'
    Assert-True (($write[0].uri -match '/channels/') -eq $private) 'Wrong removal scope.'
    Assert-True (@($calls | Where-Object method -eq 'POST').Count -eq 0) 'Removal added a member.'

    Reset-Case 'update' $private
    if ($private) { $body.assignments[0].role = 'owner' } else { $body.teamAssignments[0].role = 'owner' }
    Invoke-Case
    $write = @($calls | Where-Object method -eq 'PATCH')
    Assert-True ($response.results[0].status -eq 'Updated' -and $write.Count -eq 1) 'Promotion failed.'
    Assert-True ((($write[0].body | ConvertFrom-Json).roles -join ',') -eq 'owner') 'Incorrect Owner payload.'
    Assert-True (($write[0].uri -match '/channels/') -eq $private) 'Wrong update scope.'

    Reset-Case 'update' $private
    $owner = @{ userId = $uid; id = 'first-owner'; roles = @('owner') }
    $other = @{ userId = $otherUid; id = 'other-owner'; roles = @('owner') }
    if ($private) { $script:channelMembers = @($owner, $other) } else { $script:teamMembers = @($owner, $other) }
    Invoke-Case
    $write = @($calls | Where-Object method -eq 'PATCH')
    Assert-True ($response.results[0].status -eq 'Updated' -and @((($write[0].body | ConvertFrom-Json).roles)).Count -eq 0) 'Demotion needs empty roles.'

    foreach ($op in @('remove', 'update')) {
        Reset-Case $op $private
        $owner = @{ userId = $uid; id = 'last-owner'; roles = @('owner') }
        if ($private) { $script:channelMembers = @($owner) } else { $script:teamMembers = @($owner) }
        Invoke-Case
        Assert-True ($response.results[0].status -eq 'Error') 'Last Owner change allowed.'
        Assert-True (@($calls | Where-Object method -ne 'GET').Count -eq 0) 'Last Owner protection wrote to Graph.'
    }

    Reset-Case 'remove' $private
    $script:teamMembers = @(); $script:channelMembers = @()
    Invoke-Case
    Assert-True ($response.results[0].status -eq 'AlreadyAbsent') 'Missing member removal must skip.'
    Assert-True (@($calls | Where-Object method -ne 'GET').Count -eq 0) 'Missing member removal wrote to Graph.'

    Reset-Case 'update' $private
    $script:teamMembers = @(); $script:channelMembers = @()
    Invoke-Case
    Assert-True ($response.results[0].status -eq 'NotMember') 'Missing member update must fail without adding.'
    Assert-True (@($calls | Where-Object method -ne 'GET').Count -eq 0) 'Missing member update wrote to Graph.'

    Reset-Case 'update' $private
    Invoke-Case
    Assert-True ($response.results[0].status -eq 'Unchanged') 'Unchanged role must skip.'

    Reset-Case 'update' $private
    $guest = @{ userId = $uid; id = 'guest-member'; roles = @('guest') }
    if ($private) { $script:channelMembers = @($guest); $body.assignments[0].role = 'owner' }
    else { $script:teamMembers = @($guest); $body.teamAssignments[0].role = 'owner' }
    Invoke-Case
    Assert-True ($response.results[0].status -eq 'Error') 'Guest promotion allowed.'
    Assert-True (@($calls | Where-Object method -ne 'GET').Count -eq 0) 'Guest promotion sent a write.'

    Reset-Case 'remove' $private
    $body.validateOnly = $true
    Invoke-Case
    Assert-True ($response.validated -and @($calls | Where-Object method -ne 'GET').Count -eq 0) 'Validation performed a write.'

    Reset-Case 'remove' $private
    $script:failWrite = $true
    Invoke-Case
    Assert-True ($response.results[0].status -eq 'Error') 'Graph error not returned.'
    Assert-True (@($response.trace | Where-Object { $_.status -eq 'error' -and $_.command -match '-Method DELETE' }).Count -eq 1) 'Failed command not logged.'
}

Reset-Case 'remove'
$body.confirmed = $false
Assert-Rejected
Reset-Case 'update'
$body.confirmed = 'true'
Assert-Rejected
Reset-Case 'unsupported'
Assert-Rejected
Reset-Case 'remove' $true
$body.teamAssignments = @(@{ userId = $uid; role = 'member' })
Assert-Rejected

# Batch removal must leave an Owner after earlier successful removals.
Reset-Case 'remove'
$script:teamMembers = @(@{ userId = $uid; id = 'owner1'; roles = @('owner') }, @{ userId = $otherUid; id = 'owner2'; roles = @('owner') })
$body.users += @{ id = $otherUid; userPrincipalName = 'sample2@contoso.com' }
$body.teamAssignments += @{ userId = $otherUid; role = 'member' }
Invoke-Case
Assert-True ($response.results[0].status -eq 'Removed' -and $response.results[1].status -eq 'Error') 'Batch removed every Owner.'

Reset-Case 'update'
$script:failFirstMember = $true
$script:teamMembers += @{ userId = $otherUid; id = 'other-membership'; roles = @() }
$body.users += @{ id = $otherUid; userPrincipalName = 'sample2@contoso.com' }
$body.teamAssignments[0].role = 'owner'
$body.teamAssignments += @{ userId = $otherUid; role = 'owner' }
Invoke-Case
Assert-True ($response.results[0].status -eq 'Error' -and $response.results[1].status -eq 'Updated') 'One failure discarded another member result.'

# Preserve the existing add flows and explicit parent-Team confirmation.
Reset-Case 'add'
$script:teamMembers = @()
Invoke-Case
Assert-True ($response.results[0].status -eq 'Added') 'Team add regression.'
Reset-Case 'add' $true
$script:teamMembers = @(); $script:channelMembers = @()
Invoke-Case
Assert-True ($response.needsTeamConfirmation) 'Parent confirmation regression.'
Assert-True (@($calls | Where-Object method -ne 'GET').Count -eq 0) 'Parent added before confirmation.'
Reset-Case 'add' $true
$script:teamMembers = @(); $script:channelMembers = @(); $body.addMissingToTeam = $true
$body.assignments[0].role = 'owner'
Invoke-Case
Assert-True ($response.results[0].status -eq 'Added' -and $response.events[0].role -eq 'member') 'Private-channel add regression.'
$commands = @($response.trace | Where-Object command | ForEach-Object command)
Assert-True ($commands[2] -match '-Method POST' -and $commands[3] -eq 'Start-Sleep -Seconds 2' -and $commands[5] -match '-Method POST') 'Add trace order changed.'

Write-Output 'PASS: Team/channel remove and role updates, scoped membership IDs, confirmation, Owner/Guest protection, no auto-add, errors/traces, dry-run, batch safety, existing add flows.'

foreach ($private in @($false, $true)) {
    Reset-Case
    $script:paging = $true
    $channelId = if ($private) { 'sample-channel' } else { '' }
    $members = @(Get-ScopedMembershipUsers -TeamId $body.teamId -ChannelId $channelId)
    Assert-True ($members.Count -eq 2) 'Member picker did not follow pagination.'
    Assert-True ($members[0].id -eq $uid -and $members[0].membershipId -eq 'member-membership') 'Picker confused membership ID and user ID.'
    Assert-True ($members[0].role -eq 'member' -and $members[1].role -eq 'owner') 'Picker lost current roles.'
    Assert-True ($members[0].userPrincipalName -eq 'member@contoso.com') 'Picker email fallback failed.'
    Assert-True (@($calls | Where-Object { $_.uri -match '/users' -or $_.method -ne 'GET' }).Count -eq 0) 'Picker searched directory or wrote to Graph.'
}
Reset-Case
$rejected = $false
try { Get-ScopedMembershipUsers -TeamId $body.teamId -ChannelId 'unrelated-channel' | Out-Null } catch { $rejected = $true }
Assert-True $rejected 'Picker accepted a channel outside selected Team.'
Assert-True (@($calls | Where-Object uri -match '/members').Count -eq 0) 'Picker read members of an invalid channel.'
Write-Output 'PASS: scoped member picker, pagination, current roles, directory-ID mapping, email fallback, read-only requests and channel validation.'
