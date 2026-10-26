[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$CsvPath,

    [string]$TeamId,

    [string]$OutputPath,

    [switch]$Apply,

    [switch]$SelectChannels,

    [switch]$ListChannels
)

$ErrorActionPreference = 'Stop'

$requiredColumns = @('TeamId', 'ChannelId', 'UserPrincipalName')

function Get-GraphCollection {
    param([Parameter(Mandatory = $true)][string]$Uri)

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri

    while ($next) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
        foreach ($item in $page.value) {
            $items.Add($item)
        }
        $next = $page.'@odata.nextLink'
    }

    return $items.ToArray()
}

function Get-GraphSegment {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [uri]::EscapeDataString($Value)
}

if ($ListChannels -and ($SelectChannels -or $Apply -or -not [string]::IsNullOrWhiteSpace($CsvPath))) {
    throw 'Use -ListChannels by itself with -TeamId; do not combine it with a CSV, -SelectChannels, or -Apply.'
}
if (-not $ListChannels -and [string]::IsNullOrWhiteSpace($CsvPath)) {
    throw 'Specify -CsvPath, or use -ListChannels with -TeamId to list private channels.'
}
if (($ListChannels -or $SelectChannels) -and [string]::IsNullOrWhiteSpace($TeamId)) {
    throw 'Specify the parent team GUID with -TeamId.'
}
if ($Apply -and -not $SelectChannels -and $ListChannels) {
    throw '-Apply cannot be used with -ListChannels.'
}

$rows = @()
$actualColumns = @()
if (-not $ListChannels) {
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        throw "CSV file not found: $CsvPath"
    }

    $rows = @(Import-Csv -LiteralPath $CsvPath)
    if ($rows.Count -eq 0) {
        throw 'The CSV has no data rows.'
    }

    $actualColumns = @($rows[0].PSObject.Properties.Name)
    if ($SelectChannels) {
        if ('UserPrincipalName' -notin $actualColumns -and 'Email' -notin $actualColumns) {
            throw 'The CSV must contain a UserPrincipalName or Email column when using -SelectChannels.'
        }
    }
    else {
        $missingColumns = @($requiredColumns | Where-Object { $_ -notin $actualColumns })
        if ($missingColumns.Count -gt 0) {
            throw "CSV is missing required columns: $($missingColumns -join ', ')"
        }
    }
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw 'Microsoft.Graph.Authentication is not installed. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser'
}

$scopes = @('Channel.ReadBasic.All')
if (-not $ListChannels) {
    $scopes += @('ChannelMember.Read.All', 'TeamMember.Read.All', 'User.ReadBasic.All')
    if ($Apply) {
        $scopes += 'ChannelMember.ReadWrite.All'
    }
}

Import-Module Microsoft.Graph.Authentication
Connect-MgGraph -Scopes $scopes -NoWelcome | Out-Null

$parsedTeamId = [guid]::Empty
if (($ListChannels -or $SelectChannels) -and -not [guid]::TryParse($TeamId, [ref]$parsedTeamId)) {
    throw 'TeamId must be a valid GUID.'
}

if ($ListChannels -or $SelectChannels) {
    $teamChannelsUri = "https://graph.microsoft.com/v1.0/teams/$TeamId/channels?`$select=id,displayName,membershipType"
    $privateChannels = @(Get-GraphCollection -Uri $teamChannelsUri | Where-Object { $_.membershipType -eq 'private' } | Sort-Object displayName)
    if ($privateChannels.Count -eq 0) {
        throw 'No private channels were returned for this team. Check the team ID, Graph permissions, and that the team has private channels.'
    }
}

if ($ListChannels) {
    Write-Host "Private channels in team $TeamId`:`n"
    $privateChannels | Select-Object displayName, id | Format-Table -AutoSize
    return
}

if ($SelectChannels) {
    Write-Host "Private channels in team $TeamId`:`n"
    for ($index = 0; $index -lt $privateChannels.Count; $index++) {
        Write-Host ("[{0}] {1}" -f ($index + 1), $privateChannels[$index].displayName)
    }

    $selection = Read-Host 'Enter channel numbers separated by commas (for example: 1,3)'
    $selectedIndexes = @($selection -split '[,;\s]+' | Where-Object { $_ -ne '' })
    if ($selectedIndexes.Count -eq 0) {
        throw 'No channels were selected.'
    }

    $selectedChannels = [System.Collections.Generic.List[object]]::new()
    foreach ($selectedIndex in $selectedIndexes) {
        $number = 0
        if (-not [int]::TryParse($selectedIndex, [ref]$number) -or $number -lt 1 -or $number -gt $privateChannels.Count) {
            throw "Invalid channel selection '$selectedIndex'. Enter numbers from 1 to $($privateChannels.Count)."
        }
        $selectedChannel = $privateChannels[$number - 1]
        if (-not ($selectedChannels | Where-Object { $_.id -eq $selectedChannel.id })) {
            $selectedChannels.Add($selectedChannel)
        }
    }

    $userColumn = if ('UserPrincipalName' -in $actualColumns) { 'UserPrincipalName' } else { 'Email' }
    $userAddresses = @($rows | ForEach-Object { ([string]$_.$userColumn).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    if ($userAddresses.Count -eq 0) {
        throw 'The CSV contains no email addresses or UPNs.'
    }

    $assignments = [System.Collections.Generic.List[object]]::new()
    foreach ($selectedChannel in $selectedChannels) {
        foreach ($userAddress in $userAddresses) {
            $assignments.Add([pscustomobject]@{
                TeamId = $TeamId
                ChannelId = $selectedChannel.id
                UserPrincipalName = $userAddress
            })
        }
    }
    $rows = $assignments.ToArray()
    Write-Host "`nSelected $($selectedChannels.Count) private channel(s) and $($userAddresses.Count) user(s): $($rows.Count) assignment(s).`n"
}

$teamMembersById = @{}
$channelMembersById = @{}
$channelsById = @{}
$usersByUpn = @{}
$plannedKeys = @{}
$results = [System.Collections.Generic.List[object]]::new()

foreach ($row in $rows) {
    $teamId = ([string]$row.TeamId).Trim()
    $channelId = ([string]$row.ChannelId).Trim()
    $upn = ([string]$row.UserPrincipalName).Trim()
    $result = [ordered]@{
        TeamId = $teamId
        ChannelId = $channelId
        ChannelName = ''
        UserPrincipalName = $upn
        Status = ''
        Detail = ''
    }

    if ([string]::IsNullOrWhiteSpace($teamId) -or
        [string]::IsNullOrWhiteSpace($channelId) -or
        [string]::IsNullOrWhiteSpace($upn)) {
        $result.Status = 'InvalidRow'
        $result.Detail = 'TeamId, ChannelId, and UserPrincipalName are all required.'
        $results.Add([pscustomobject]$result)
        continue
    }

    $parsedTeamId = [guid]::Empty
    if (-not [guid]::TryParse($teamId, [ref]$parsedTeamId)) {
        $result.Status = 'InvalidRow'
        $result.Detail = 'TeamId must be a valid GUID.'
        $results.Add([pscustomobject]$result)
        continue
    }

    try {
        $channelKey = "$teamId|$channelId"
        if (-not $channelsById.ContainsKey($channelKey)) {
            $encodedChannelId = Get-GraphSegment $channelId
            $channelUri = "https://graph.microsoft.com/v1.0/teams/$teamId/channels/$encodedChannelId`?`$select=id,displayName,membershipType"
            $channelsById[$channelKey] = Invoke-MgGraphRequest -Method GET -Uri $channelUri -OutputType PSObject
        }

        $channel = $channelsById[$channelKey]
        $result.ChannelName = $channel.displayName
        if ($channel.membershipType -ne 'private') {
            $result.Status = 'NotPrivate'
            $result.Detail = "Channel membershipType is '$($channel.membershipType)', not private."
            $results.Add([pscustomobject]$result)
            continue
        }

        if (-not $teamMembersById.ContainsKey($teamId)) {
            $teamMembersById[$teamId] = @{}
            $teamUri = "https://graph.microsoft.com/v1.0/teams/$teamId/members?`$select=userId,email,displayName"
            foreach ($member in Get-GraphCollection -Uri $teamUri) {
                if ($member.userId) {
                    $teamMembersById[$teamId][$member.userId] = $true
                }
            }
        }

        $normalizedUpn = $upn.ToLowerInvariant()
        if (-not $usersByUpn.ContainsKey($normalizedUpn)) {
            $escapedAddress = $upn.Replace("'", "''")
            $filter = "userPrincipalName eq '$escapedAddress' or mail eq '$escapedAddress'"
            $encodedFilter = [uri]::EscapeDataString($filter)
            $userUri = "https://graph.microsoft.com/v1.0/users?`$filter=$encodedFilter&`$select=id,userPrincipalName,mail"
            $userMatches = @(Get-GraphCollection -Uri $userUri)
            $exactUpnMatch = @($userMatches | Where-Object { $_.userPrincipalName -ieq $upn })
            if ($exactUpnMatch.Count -eq 1) {
                $usersByUpn[$normalizedUpn] = $exactUpnMatch[0]
            }
            else {
                $exactMailMatches = @($userMatches | Where-Object { $_.mail -ieq $upn })
                if ($exactMailMatches.Count -eq 1) {
                    $usersByUpn[$normalizedUpn] = $exactMailMatches[0]
                }
                elseif ($userMatches.Count -eq 0) {
                    throw "No user was found for '$upn' by UPN or mail address."
                }
                else {
                    throw "The address '$upn' matched multiple users. Use the exact userPrincipalName instead."
                }
            }
        }
        $user = $usersByUpn[$normalizedUpn]

        if (-not $teamMembersById[$teamId].ContainsKey($user.id)) {
            $result.Status = 'NotInTeam'
            $result.Detail = 'Add this user to the parent team first; this tool does not change team membership.'
            $results.Add([pscustomobject]$result)
            continue
        }

        if (-not $channelMembersById.ContainsKey($channelKey)) {
            $channelMembersById[$channelKey] = @{}
            $membersUri = "https://graph.microsoft.com/v1.0/teams/$teamId/channels/$(Get-GraphSegment $channelId)/members?`$select=userId,displayName,email"
            foreach ($member in Get-GraphCollection -Uri $membersUri) {
                if ($member.userId) {
                    $channelMembersById[$channelKey][$member.userId] = $true
                }
            }
        }

        $planKey = "$channelKey|$($user.id)"
        if ($channelMembersById[$channelKey].ContainsKey($user.id)) {
            $result.Status = 'AlreadyMember'
            $result.Detail = 'The user is already a member of this private channel.'
        }
        elseif ($plannedKeys.ContainsKey($planKey)) {
            $result.Status = 'DuplicateInput'
            $result.Detail = 'This user and channel pair appears more than once in the CSV.'
        }
        elseif (-not $Apply) {
            $plannedKeys[$planKey] = $true
            $result.Status = 'WouldAdd'
            $result.Detail = 'Preview only. Rerun with -Apply to add this user.'
        }
        elseif ($PSCmdlet.ShouldProcess("$upn in $($channel.displayName)", 'Add private channel member')) {
            $body = @{
                '@odata.type' = '#microsoft.graph.aadUserConversationMember'
                roles = @()
                'user@odata.bind' = "https://graph.microsoft.com/v1.0/users('$($user.id)')"
            }
            $membersUri = "https://graph.microsoft.com/v1.0/teams/$teamId/channels/$(Get-GraphSegment $channelId)/members"
            Invoke-MgGraphRequest -Method POST -Uri $membersUri -Body ($body | ConvertTo-Json -Depth 5) -ContentType 'application/json' | Out-Null
            $channelMembersById[$channelKey][$user.id] = $true
            $plannedKeys[$planKey] = $true
            $result.Status = 'Added'
            $result.Detail = 'Member added successfully.'
        }
        else {
            $result.Status = 'Skipped'
            $result.Detail = 'The operation was declined or suppressed by WhatIf.'
        }
    }
    catch {
        $result.Status = 'Error'
        $result.Detail = $_.Exception.Message
    }

    $results.Add([pscustomobject]$result)
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $directory = Split-Path -Parent (Resolve-Path -LiteralPath $CsvPath)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path $directory "private-channel-results-$timestamp.csv"
}

$resolvedInputPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CsvPath).Path)
$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if ($resolvedInputPath -eq $resolvedOutputPath) {
    throw 'OutputPath must not point to the input CSV.'
}
if (Test-Path -LiteralPath $resolvedOutputPath) {
    throw "Output file already exists: $resolvedOutputPath"
}

$results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding utf8
$results | Format-Table -AutoSize
Write-Host "Results saved to: $OutputPath"