[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$script:GraphConnected = $false
$script:AppToken = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
$script:GraphScopes = @(
    'Team.ReadBasic.All'
    'Channel.ReadBasic.All'
    'ChannelMember.Read.All'
    'ChannelMember.ReadWrite.All'
    'TeamMember.Read.All'
    'TeamMember.ReadWriteNonOwnerRole.All'
    'TeamMember.ReadWrite.All'
    'User.ReadBasic.All'
)

function Send-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Value,
        [int]$StatusCode = 200
    )

    $json = ConvertTo-Json -InputObject $Value -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = 'application/json; charset=utf-8'
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.Headers['Cache-Control'] = 'no-store'
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

function Read-JsonBody {
    param([Parameter(Mandatory = $true)]$Request)

    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try {
        $raw = $reader.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        return ($raw | ConvertFrom-Json)
    }
    finally {
        $reader.Dispose()
    }
}

function Add-MembershipTrace {
    param($Trace, [string]$Command, [string]$Status, [string]$Detail)
    if ($null -eq $Trace) { return }
    $Trace.Add(@{
        sequence = $Trace.Count + 1
        time = [DateTimeOffset]::Now.ToString('o')
        command = $Command
        status = $Status
        detail = $Detail
    })
}

function Invoke-MembershipGraphRequest {
    param([string]$Method, [string]$Uri, $Body, $Trace, [hashtable]$Headers = @{})
    $parameters = @{ Method = $Method; Uri = $Uri; OutputType = 'PSObject'; Headers = $Headers }
    # Log only the explicit membership payload, never authentication headers or context.
    $command = "Invoke-MgGraphRequest -Method $Method -Uri '" + $Uri.Replace("'", "''") + "' -OutputType PSObject"
    if ($null -ne $Body) {
        $json = ConvertTo-Json -InputObject $Body -Depth 5 -Compress
        $parameters.Body = $json
        $parameters.ContentType = 'application/json'
        $command += " -Body '" + $json.Replace("'", "''") + "' -ContentType 'application/json'"
    }
    try {
        $response = Invoke-MgGraphRequest @parameters
        $description = if ($Method -eq 'GET') {
            if ($Uri -match '/channels\?') { 'Đọc danh sách kênh và kiểm tra kênh riêng thuộc Team đã chọn.' }
            elseif ($Uri -match '/channels/.+/members') { 'Đọc danh sách thành viên kênh để kiểm tra người dùng đã có sẵn.' }
            else { 'Đọc danh sách thành viên Team để kiểm tra tư cách thành viên và quyền hiện tại.' }
        }
        elseif ($Method -eq 'DELETE') { 'Gỡ thành viên khỏi phạm vi Team hoặc private channel trong URI.' }
        elseif ($Method -eq 'PATCH') { 'Cập nhật quyền của thành viên trong phạm vi Team hoặc private channel trong URI.' }
        elseif ($Uri -match '/channels/.+/members') { 'Thêm người dùng vào private channel với quyền trong payload.' }
        else { 'Thêm người dùng vào Team với quyền trong payload; standard channel được kế thừa.' }
        Add-MembershipTrace -Trace $Trace -Command $command -Status 'success' -Detail $description
        return $response
    }
    catch {
        Add-MembershipTrace -Trace $Trace -Command $command -Status 'error' -Detail (Get-GraphErrorText -ErrorRecord $_)
        throw
    }
}

function Get-ReleaseNotes {
    param([string]$RootDirectory, [switch]$IncludeRemote)
    $notes = @{
        currentVersion = ([IO.File]::ReadAllText((Join-Path $RootDirectory 'VERSION'))).Trim()
        localMarkdown = ''
        remoteMarkdown = ''
        warning = ''
    }
    $localPath = Join-Path $RootDirectory 'CHANGELOG.md'
    if (Test-Path -LiteralPath $localPath -PathType Leaf) {
        $notes.localMarkdown = [IO.File]::ReadAllText($localPath, [Text.Encoding]::UTF8)
    }
    else { $notes.warning = 'Không tìm thấy lịch sử phiên bản trong bản cài đặt.' }
    if ($IncludeRemote) {
        try {
            $uri = 'https://raw.githubusercontent.com/huynhnguyenday/tool-MS365/main/CHANGELOG.md'
            $remote = [string](Invoke-RestMethod -Uri $uri -TimeoutSec 8 -Headers @{ 'User-Agent' = 'TeamsChannelManager-ReleaseNotes' })
            if ($remote.Length -gt 1048576) { throw 'Release notes exceed the supported size.' }
            $notes.remoteMarkdown = $remote
        }
        catch { $notes.warning = 'Chưa tải được ghi chú bản mới từ GitHub. Lịch sử trong bản cài đặt vẫn có thể đọc bên dưới.' }
    }
    return $notes
}

function Get-ScopedMembershipUsers {
    param([string]$TeamId, [string]$ChannelId)
    $parsedTeamId = [guid]::Empty
    if (-not [guid]::TryParse($TeamId, [ref]$parsedTeamId)) { throw 'A valid team ID is required.' }
    $teamPath = "https://graph.microsoft.com/v1.0/teams/$(Get-GraphPathValue $TeamId)"
    $membersUri = "$teamPath/members"
    if ($ChannelId) {
        $channels = @(Get-GraphPages -Uri "$teamPath/channels?`$select=id,membershipType")
        if (-not ($channels | Where-Object { [string]$_.id -eq $ChannelId -and $_.membershipType -eq 'private' })) {
            throw 'Select a private channel belonging to this team.'
        }
        $membersUri = "$teamPath/channels/$(Get-GraphPathValue $ChannelId)/members"
    }
    $users = foreach ($member in Get-GraphPages -Uri $membersUri) {
        if (-not $member.userId) { continue }
        @{
            id = [string]$member.userId
            membershipId = [string]$member.id
            displayName = if ($member.displayName) { [string]$member.displayName } else { [string]$member.userId }
            userPrincipalName = if ($member.userPrincipalName) { [string]$member.userPrincipalName } else { [string]$member.email }
            email = [string]$member.email
            role = if (@($member.roles) -contains 'owner') { 'owner' } else { 'member' }
            isGuest = @($member.roles) -contains 'guest'
        }
    }
    return @($users | Sort-Object @{ Expression = { [string]$_.displayName } }, @{ Expression = { [string]$_.id } })
}

function Invoke-ExistingMembershipChange {
    param(
        [ValidateSet('remove', 'update')][string]$Operation,
        $Assignments, [hashtable]$MembersById, [string]$MembersUri,
        $Users, $Trace, [string]$ScopeName
    )
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($assignment in $Assignments) {
        $userId = [string]$assignment.userId
        $user = $Users | Where-Object { [string]$_.id -eq $userId } | Select-Object -First 1
        $result = @{ channel = $ScopeName; user = [string]$user.userPrincipalName; status = ''; detail = '' }
        try {
            if (-not $MembersById.ContainsKey($userId)) {
                $result.status = if ($Operation -eq 'remove') { 'AlreadyAbsent' } else { 'NotMember' }
                $result.detail = if ($Operation -eq 'remove') { 'Người dùng không thuộc phạm vi này; không gửi lệnh gỡ.' } else { 'Người dùng chưa là thành viên; không thể đổi quyền và không tự động thêm.' }
                Add-MembershipTrace -Trace $Trace -Status 'info' -Detail $result.detail
            }
            else {
                $member = $MembersById[$userId]
                $isOwner = @($member.roles) -contains 'owner'
                $desiredOwner = [string]$assignment.role -eq 'owner'
                if ($Operation -eq 'update' -and $isOwner -eq $desiredOwner) {
                    $result.status = 'Unchanged'
                    $result.detail = 'Quyền hiện tại đã đúng lựa chọn; không gửi lệnh cập nhật.'
                    Add-MembershipTrace -Trace $Trace -Status 'info' -Detail $result.detail
                }
                else {
                    if ($isOwner -and ($Operation -eq 'remove' -or -not $desiredOwner)) {
                        $ownerCount = @($MembersById.Values | Where-Object { @($_.roles) -contains 'owner' }).Count
                        if ($ownerCount -le 1) { throw 'Không thể gỡ hoặc hạ quyền Owner cuối cùng. Hãy chỉ định một Owner khác trước.' }
                    }
                    if ($Operation -eq 'update' -and $desiredOwner -and (@($member.roles) -contains 'guest')) {
                        throw 'Không thể nâng tài khoản Guest thành Owner.'
                    }
                    if ([string]::IsNullOrWhiteSpace([string]$member.id)) { throw 'Microsoft Graph không trả về membership ID; chưa gửi lệnh thay đổi.' }
                    $uri = "$MembersUri/$(Get-GraphPathValue ([string]$member.id))"
                    if ($Operation -eq 'remove') {
                        Invoke-MembershipGraphRequest -Method DELETE -Uri $uri -Trace $Trace | Out-Null
                        $MembersById.Remove($userId)
                        $result.status = 'Removed'
                        $result.detail = 'Đã gỡ thành viên khỏi phạm vi đã chọn.'
                    }
                    else {
                        $roles = [string[]]@()
                        if ($desiredOwner) { $roles = [string[]]@('owner') }
                        $payload = @{ '@odata.type' = '#microsoft.graph.aadUserConversationMember'; roles = $roles }
                        Invoke-MembershipGraphRequest -Method PATCH -Uri $uri -Body $payload -Trace $Trace | Out-Null
                        $MembersById[$userId] = @{ id = [string]$member.id; userId = $userId; roles = $roles }
                        $result.status = 'Updated'
                        $result.detail = "Đã cập nhật quyền thành $($assignment.role)."
                    }
                }
            }
        }
        catch {
            $result.status = 'Error'
            $result.detail = Get-GraphErrorText -ErrorRecord $_
            Add-MembershipTrace -Trace $Trace -Status 'error' -Detail $result.detail
        }
        $results.Add($result)
    }
    return $results.ToArray()
}

function Get-GraphPages {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [hashtable]$Headers = @{},
        $Trace = $null
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $page = Invoke-MembershipGraphRequest -Method GET -Uri $next -Headers $Headers -Trace $Trace
        foreach ($item in $page.value) { $items.Add($item) }
        $next = $page.'@odata.nextLink'
    }
    return $items.ToArray()
}

function Get-GraphPathValue {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [uri]::EscapeDataString($Value)
}

function Get-GraphErrorText {
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    $rawMessage = [string]$ErrorRecord.Exception.Message
    $details = [string]$ErrorRecord.ErrorDetails.Message
    if (-not [string]::IsNullOrWhiteSpace($details)) {
        try {
            $graphError = $details | ConvertFrom-Json
            if ($graphError.error.message) {
                $code = [string]$graphError.error.code
                if ($code) { return "$code`: $($graphError.error.message)" }
                return [string]$graphError.error.message
            }
        }
        catch { }
        return $details
    }

    if ($ErrorRecord.Exception.Response) {
        try {
            $response = $ErrorRecord.Exception.Response
            $status = [int]$response.StatusCode
            if ($response.Content) {
                $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $graphError = $body | ConvertFrom-Json
                if ($graphError.error.message) {
                    return "$($graphError.error.code) (HTTP $status)`: $($graphError.error.message)"
                }
            }
        }
        catch { }
    }

    return $rawMessage
}

function Assert-Connected {
    $context = Get-MgContext
    if (-not $context -or -not $context.Account) {
        $script:GraphConnected = $false
        throw 'Connect to Microsoft 365 first.'
    }
    $script:GraphConnected = $true
    return $context
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw 'Microsoft.Graph.Authentication is missing. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser'
}

Import-Module Microsoft.Graph.Authentication
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$htmlPath = Join-Path $scriptRoot 'private-channel-members.html'
$cssPath = Join-Path $scriptRoot 'private-channel-members.css'
$versionPath = Join-Path $scriptRoot 'VERSION'
$updaterPath = Join-Path $scriptRoot 'Update-TeamsChannelManager.ps1'
if (-not (Test-Path -LiteralPath $htmlPath -PathType Leaf)) {
    throw "UI file not found: $htmlPath"
}
if (-not (Test-Path -LiteralPath $cssPath -PathType Leaf)) {
    throw "UI stylesheet not found: $cssPath"
}

$listener = [System.Net.HttpListener]::new()
$baseUrl = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($baseUrl)
try {
    $listener.Start()
}
catch {
    throw "Could not start local UI at $baseUrl. The port may already be in use. Try: .\Start-PrivateChannelMembersUI.ps1 -Port 8766"
}

$url = "http://127.0.0.1:$Port/"
Write-Host "Private Teams Channel Manager is running at $url"
Write-Host 'This server listens only on this computer. Keep this PowerShell window open; press Ctrl+C to stop it.'
Start-Process $url

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $request = $context.Request
            $path = $request.Url.AbsolutePath.TrimEnd('/').ToLowerInvariant()
            if (-not $path) { $path = '/' }
            $method = $request.HttpMethod.ToUpperInvariant()

            if ($path -eq '/' -and $method -eq 'GET') {
                $html = [System.IO.File]::ReadAllText($htmlPath)
                $html = $html.Replace('__APP_TOKEN__', $script:AppToken)
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
                $context.Response.ContentType = 'text/html; charset=utf-8'
                $context.Response.ContentLength64 = $bytes.Length
                $context.Response.Headers['Cache-Control'] = 'no-store'
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $context.Response.Close()
                continue
            }

            $staticAssets = @{
                '/toolms.ico' = @{ File = 'toolms-shortcut.ico'; ContentType = 'image/x-icon' }
                '/favicon.ico' = @{ File = 'favicon.ico'; ContentType = 'image/x-icon' }
                '/favicon-16.png' = @{ File = 'favicon-16.png'; ContentType = 'image/png' }
                '/favicon-32.png' = @{ File = 'favicon-32.png'; ContentType = 'image/png' }
                '/private-channel-members.css' = @{ File = 'private-channel-members.css'; ContentType = 'text/css; charset=utf-8' }
                '/fontawesome.min.css' = @{ File = 'fontawesome.min.css'; ContentType = 'text/css; charset=utf-8' }
                '/fontawesome-solid.min.css' = @{ File = 'fontawesome-solid.min.css'; ContentType = 'text/css; charset=utf-8' }
                '/fa-solid-900.woff2' = @{ File = 'fa-solid-900.woff2'; ContentType = 'font/woff2' }
            }
            if ($staticAssets.ContainsKey($path) -and $method -eq 'GET') {
                $asset = $staticAssets[$path]
                $bytes = [System.IO.File]::ReadAllBytes((Join-Path $scriptRoot $asset.File))
                $context.Response.ContentType = $asset.ContentType
                $context.Response.ContentLength64 = $bytes.Length
                $context.Response.Headers['Cache-Control'] = 'no-store'
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $context.Response.Close()
                continue
            }

            if ($path -notlike '/api/*') {
                Send-JsonResponse -Context $context -StatusCode 404 -Value @{ error = 'Not found' }
                continue
            }

            if ($request.Headers['X-Tool-Token'] -cne $script:AppToken) {
                Send-JsonResponse -Context $context -StatusCode 403 -Value @{ error = 'Invalid local session token.' }
                continue
            }

            if ($path -eq '/api/status' -and $method -eq 'GET') {
                $graphContext = Get-MgContext
                Send-JsonResponse -Context $context -Value @{
                    connected = [bool]($graphContext -and $graphContext.Account)
                    account = if ($graphContext) { $graphContext.Account } else { $null }
                    tenantId = if ($graphContext) { $graphContext.TenantId } else { $null }
                    membershipOperations = @('add', 'update', 'remove')
                }
                continue
            }

            if ($path -eq '/api/connect' -and $method -eq 'POST') {
                Connect-MgGraph -Scopes $script:GraphScopes -NoWelcome | Out-Null
                $graphContext = Get-MgContext
                if (-not $graphContext -or -not $graphContext.Account) {
                    throw 'Microsoft Graph sign-in did not return an account.'
                }
                $script:GraphConnected = $true
                Send-JsonResponse -Context $context -Value @{
                    connected = $true
                    account = $graphContext.Account
                    tenantId = $graphContext.TenantId
                }
                continue
            }

            if ($path -eq '/api/disconnect' -and $method -eq 'POST') {
                Disconnect-MgGraph | Out-Null
                $script:GraphConnected = $false
                Send-JsonResponse -Context $context -Value @{ connected = $false }
                continue
            }

            if ($path -eq '/api/release-notes' -and $method -eq 'GET') {
                Send-JsonResponse -Context $context -Value (Get-ReleaseNotes -RootDirectory $scriptRoot -IncludeRemote:($request.QueryString['remote'] -eq '1'))
                continue
            }

            if ($path -eq '/api/update/status' -and $method -eq 'GET') {
                if (-not (Test-Path -LiteralPath $updaterPath -PathType Leaf)) { throw 'Updater script is missing.' }
                $updateJson = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $updaterPath -CheckOnly
                if ($LASTEXITCODE -ne 0) { throw 'Could not check GitHub for updates.' }
                Send-JsonResponse -Context $context -Value ($updateJson | ConvertFrom-Json)
                continue
            }

            if ($path -eq '/api/update/apply' -and $method -eq 'POST') {
                if (-not (Test-Path -LiteralPath $updaterPath -PathType Leaf)) { throw 'Updater script is missing.' }
                $arguments = @(
                    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                    '-File', $updaterPath, '-Apply', '-Restart',
                    '-ParentProcessId', $PID, '-Port', $Port
                )
                Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $scriptRoot -WindowStyle Hidden
                Send-JsonResponse -Context $context -Value @{ updating = $true; message = 'Update started. The application will restart automatically.' }
                $listener.Stop()
                continue
            }

            $graphContext = Assert-Connected

            if ($path -eq '/api/teams' -and $method -eq 'GET') {
                # /me/joinedTeams only returns teams where the signed-in user is a
                # direct member. /teams returns the tenant-wide list for supported
                # administrators and uses the already-requested Team.ReadBasic.All
                # delegated permission.
                $teamsUri = 'https://graph.microsoft.com/v1.0/teams?$select=id,displayName,description'
                $teams = @(Get-GraphPages -Uri $teamsUri | Sort-Object displayName)
                Send-JsonResponse -Context $context -Value @{ teams = @($teams | ForEach-Object {
                    @{ id = $_.id; displayName = $_.displayName; description = $_.description }
                }) }
                continue
            }

            if ($path -match '^/api/teams/([^/]+)/channels$' -and $method -eq 'GET') {
                $teamId = [uri]::UnescapeDataString($Matches[1])
                $channelsUri = "https://graph.microsoft.com/v1.0/teams/$(Get-GraphPathValue $teamId)/channels?`$select=id,displayName,description,membershipType"
                $channels = @(Get-GraphPages -Uri $channelsUri | Sort-Object displayName)
                Send-JsonResponse -Context $context -Value @{ channels = @($channels | ForEach-Object {
                    @{ id = $_.id; displayName = $_.displayName; description = $_.description; membershipType = $_.membershipType }
                }) }
                continue
            }

            if ($path -eq '/api/membership-users' -and $method -eq 'GET') {
                $teamId = [string]$request.QueryString['teamId']
                $channelId = [string]$request.QueryString['channelId']
                $users = @(Get-ScopedMembershipUsers -TeamId $teamId -ChannelId $channelId)
                Send-JsonResponse -Context $context -Value @{ users = $users }
                continue
            }

            if ($path -eq '/api/users' -and $method -eq 'GET') {
                $query = [string]$request.QueryString['q']
                if ($query.Length -lt 2) {
                    Send-JsonResponse -Context $context -Value @{ users = @() }
                    continue
                }

                $escaped = $query.Replace("'", "''")
                if ($query.Contains('@')) {
                    $filter = "userPrincipalName eq '$escaped' or mail eq '$escaped'"
                    $encodedFilter = [uri]::EscapeDataString($filter)
                    $usersUri = "https://graph.microsoft.com/v1.0/users?`$filter=$encodedFilter&`$select=id,displayName,mail,userPrincipalName&`$top=15"
                    $users = @(Get-GraphPages -Uri $usersUri)
                }
                else {
                    $nameFilter = [uri]::EscapeDataString("startswith(displayName,'$escaped')")
                    $upnFilter = [uri]::EscapeDataString("startswith(userPrincipalName,'$escaped')")
                    $mailFilter = [uri]::EscapeDataString("startswith(mail,'$escaped')")
                    $users = @()
                    foreach ($filter in @($nameFilter, $upnFilter, $mailFilter)) {
                        $usersUri = "https://graph.microsoft.com/v1.0/users?`$filter=$filter&`$select=id,displayName,mail,userPrincipalName&`$top=15"
                        $users += @(Get-GraphPages -Uri $usersUri)
                    }
                    $users = @($users | Sort-Object id -Unique | Select-Object -First 20)
                }

                Send-JsonResponse -Context $context -Value @{ users = @($users | ForEach-Object {
                    @{ id = $_.id; displayName = $_.displayName; email = $_.mail; userPrincipalName = $_.userPrincipalName }
                }) }
                continue
            }

            if ($path -eq '/api/members' -and $method -eq 'POST') {
                $membershipTrace = [System.Collections.Generic.List[object]]::new()
                $membershipEvents = [System.Collections.Generic.List[object]]::new()
                $body = Read-JsonBody -Request $request
                $operation = [string]$body.operation
                if (-not $operation) { $operation = 'add' }
                if ($operation -notin @('add', 'remove', 'update')) { throw 'Unsupported membership operation.' }
                if ($operation -ne 'add' -and -not [bool]$body.validateOnly -and ($body.confirmed -isnot [bool] -or -not $body.confirmed)) {
                    throw 'Confirm the membership change before submitting it.'
                }
                $teamId = [string]$body.teamId
                $users = @($body.users)
                $assignments = @($body.assignments)
                $teamAssignments = @($body.teamAssignments)
                $channelIds = @($assignments | ForEach-Object { [string]$_.channelId } | Where-Object { $_ } | Select-Object -Unique)
                $isPrivateChannelFlow = $channelIds.Count -gt 0
                $parsedTeamId = [guid]::Empty
                if (-not [guid]::TryParse($teamId, [ref]$parsedTeamId)) { throw 'A valid team ID is required.' }
                if ($users.Count -eq 0) { throw 'Select at least one user.' }
                if ($channelIds.Count -gt 50 -or $users.Count -gt 100) { throw 'This action is limited to 50 channels and 100 users per run.' }
                $selectedUserIds = @($users | ForEach-Object { [string]$_.id })
                if ($isPrivateChannelFlow) {
                    if ($teamAssignments.Count -gt 0) { throw 'Team assignments cannot be combined with private-channel assignments.' }
                    foreach ($assignment in $assignments) {
                        if ([string]$assignment.role -notin @('member', 'owner')) { throw 'Each channel assignment role must be member or owner.' }
                        if ([string]$assignment.userId -notin $selectedUserIds) { throw 'A channel assignment references a user that was not selected.' }
                    }
                }
                else {
                    if ($assignments.Count -gt 0) { throw 'Channel assignments require at least one private channel.' }
                    if ($teamAssignments.Count -ne $users.Count) { throw 'Each selected user must have exactly one team role.' }
                    if (@($teamAssignments | ForEach-Object { [string]$_.userId } | Select-Object -Unique).Count -ne $users.Count) { throw 'Team assignments must contain each selected user exactly once.' }
                    foreach ($assignment in $teamAssignments) {
                        if ([string]$assignment.role -notin @('member', 'owner')) { throw 'Each team role must be member or owner.' }
                        if ([string]$assignment.userId -notin $selectedUserIds) { throw 'A team assignment references a user that was not selected.' }
                    }
                }

                $channelsById = @{}
                if ($channelIds.Count -gt 0) {
                    $channelsUri = "https://graph.microsoft.com/v1.0/teams/$teamId/channels?`$select=id,displayName,membershipType"
                    $availableChannels = @(Get-GraphPages -Uri $channelsUri -Trace $membershipTrace | Where-Object { $_.membershipType -eq 'private' })
                    foreach ($channel in $availableChannels) { $channelsById[$channel.id] = $channel }
                    foreach ($channelId in $channelIds) {
                        if (-not $channelsById.ContainsKey($channelId)) { throw 'One selected channel is not a private channel in this team.' }
                    }
                }

                $teamMembersUri = "https://graph.microsoft.com/v1.0/teams/$teamId/members"
                $teamMemberIds = @{}
                foreach ($member in Get-GraphPages -Uri $teamMembersUri -Trace $membershipTrace) {
                    if ($member.userId) { $teamMemberIds[$member.userId] = $member }
                }

                # Removal and role changes only target existing memberships.
                # Never enter the parent-Team auto-add flow for these actions.
                if ($operation -ne 'add') {
                    if ([bool]$body.validateOnly) {
                        Send-JsonResponse -Context $context -Value @{ validated = $true; results = @(); trace = $membershipTrace.ToArray() }
                        continue
                    }
                    $results = [System.Collections.Generic.List[object]]::new()
                    if (-not $isPrivateChannelFlow) {
                        foreach ($result in @(Invoke-ExistingMembershipChange -Operation $operation -Assignments $teamAssignments -MembersById $teamMemberIds -MembersUri $teamMembersUri -Users $users -Trace $membershipTrace -ScopeName 'Team (standard channels)')) { $results.Add($result) }
                    }
                    else {
                        foreach ($channelId in $channelIds) {
                            $channelMembersUri = "https://graph.microsoft.com/v1.0/teams/$teamId/channels/$(Get-GraphPathValue $channelId)/members"
                            $channelAssignments = @($assignments | Where-Object { [string]$_.channelId -eq $channelId })
                            try {
                                $membersById = @{}
                                foreach ($member in Get-GraphPages -Uri $channelMembersUri -Trace $membershipTrace) {
                                    if ($member.userId) { $membersById[$member.userId] = $member }
                                }
                                foreach ($result in @(Invoke-ExistingMembershipChange -Operation $operation -Assignments $channelAssignments -MembersById $membersById -MembersUri $channelMembersUri -Users $users -Trace $membershipTrace -ScopeName ([string]$channelsById[$channelId].displayName))) { $results.Add($result) }
                            }
                            catch {
                                foreach ($assignment in $channelAssignments) {
                                    $user = $users | Where-Object { [string]$_.id -eq [string]$assignment.userId } | Select-Object -First 1
                                    $results.Add(@{ channel = [string]$channelsById[$channelId].displayName; user = [string]$user.userPrincipalName; status = 'Error'; detail = Get-GraphErrorText -ErrorRecord $_ })
                                }
                            }
                        }
                    }
                    Send-JsonResponse -Context $context -Value @{ operation = $operation; results = $results.ToArray(); trace = $membershipTrace.ToArray() }
                    continue
                }

                # Flow 1: no private channel was selected. Add or update users at
                # team level only. Standard-channel access is inherited from team
                # membership, and each user can be assigned Member or Owner.
                if (-not $isPrivateChannelFlow) {
                    if ([bool]$body.validateOnly) {
                        Send-JsonResponse -Context $context -Value @{ validated = $true; results = @() }
                        continue
                    }
                    $results = [System.Collections.Generic.List[object]]::new()
                    foreach ($assignment in $teamAssignments) {
                        $userId = [string]$assignment.userId
                        $role = [string]$assignment.role
                        $user = $users | Where-Object { [string]$_.id -eq $userId } | Select-Object -First 1
                        $upn = [string]$user.userPrincipalName
                        $desiredRoles = [string[]]@()
                        if ($role -eq 'owner') { $desiredRoles = [string[]]@('owner') }
                        try {
                            if ($teamMemberIds.ContainsKey($userId)) {
                                $existingMember = $teamMemberIds[$userId]
                                $isOwner = @($existingMember.roles) -contains 'owner'
                                if (($role -eq 'owner') -eq $isOwner) {
                                    Add-MembershipTrace -Trace $membershipTrace -Status 'info' -Detail "Người dùng đã thuộc Team với quyền $role; không gửi lệnh thêm hoặc đổi quyền."
                                    $results.Add(@{ channel = 'Team (standard channels)'; user = $upn; status = 'AlreadyMember'; detail = "Already in the team as $role." })
                                    continue
                                }
                                foreach ($result in @(Invoke-ExistingMembershipChange -Operation update -Assignments @($assignment) -MembersById $teamMemberIds -MembersUri $teamMembersUri -Users $users -Trace $membershipTrace -ScopeName 'Team (standard channels)')) { $results.Add($result) }
                            }
                            else {
                                $teamMemberBody = @{
                                    '@odata.type' = '#microsoft.graph.aadUserConversationMember'
                                    roles = $desiredRoles
                                    'user@odata.bind' = "https://graph.microsoft.com/v1.0/users('$userId')"
                                }
                                Invoke-MembershipGraphRequest -Method POST -Uri $teamMembersUri -Body $teamMemberBody -Trace $membershipTrace | Out-Null
                                $results.Add(@{ channel = 'Team (standard channels)'; user = $upn; status = 'Added'; detail = "Added to the team as $role. Standard channels are inherited automatically." })
                            }
                        }
                        catch {
                            $results.Add(@{ channel = 'Team (standard channels)'; user = $upn; status = 'Error'; detail = Get-GraphErrorText -ErrorRecord $_ })
                        }
                    }
                    Send-JsonResponse -Context $context -Value @{ flow = 'team'; results = $results.ToArray(); trace = $membershipTrace.ToArray() }
                    continue
                }

                # Flow 2: private channels were selected. Ensure users are parent-
                # team members (always as Member), after explicit confirmation,
                # before applying the per-channel Member/Owner assignments.
                $missingTeamUsers = @($users | Where-Object {
                    $candidateId = [string]$_.id
                    [string]::IsNullOrWhiteSpace($candidateId) -or -not $teamMemberIds.ContainsKey($candidateId)
                } | Sort-Object id -Unique)
                if ($missingTeamUsers.Count -gt 0 -and -not [bool]$body.addMissingToTeam) {
                    $missingPeople = @($missingTeamUsers | ForEach-Object {
                        @{ id = [string]$_.id; displayName = [string]$_.displayName; userPrincipalName = [string]$_.userPrincipalName; email = [string]$_.email }
                    })
                    Send-JsonResponse -Context $context -Value @{
                        needsTeamConfirmation = $true
                        missingUsers = $missingPeople
                        results = @()
                        message = 'Some selected users are not members of the parent team.'
                    }
                    continue
                }

                if ([bool]$body.validateOnly) {
                    Send-JsonResponse -Context $context -Value @{ validated = $true; results = @() }
                    continue
                }

                $teamAddErrors = @{}
                if ($missingTeamUsers.Count -gt 0) {
                    foreach ($user in $missingTeamUsers) {
                        $userId = [string]$user.id
                        try {
                            $teamRoles = [string[]]@()
                            $teamMemberBody = @{
                                '@odata.type' = '#microsoft.graph.aadUserConversationMember'
                                roles = $teamRoles
                                'user@odata.bind' = "https://graph.microsoft.com/v1.0/users('$userId')"
                            }
                            $teamMemberUri = "https://graph.microsoft.com/v1.0/teams/$teamId/members"
                            Add-MembershipTrace -Trace $membershipTrace -Status 'info' -Detail 'Đã nhận xác nhận thêm người thiếu vào Team cha với quyền Member.'
                            Invoke-MembershipGraphRequest -Method POST -Uri $teamMemberUri -Body $teamMemberBody -Trace $membershipTrace | Out-Null
                            $teamMemberIds[$userId] = @{ userId = $userId; roles = @() }
                            $membershipEvents.Add(@{
                                channel = 'Team cha'; user = [string]$user.userPrincipalName; role = 'member'
                                status = 'Added'; detail = 'Đã thêm vào Team cha với quyền Member sau khi xác nhận.'
                                trace = $membershipTrace.ToArray()
                            })
                            if ($channelIds.Count -gt 0) {
                                Start-Sleep -Seconds 2
                                Add-MembershipTrace -Trace $membershipTrace -Command 'Start-Sleep -Seconds 2' -Status 'success' -Detail 'Chờ đồng bộ thành viên Team cha trước khi thêm vào private channel.'
                            }
                        }
                        catch {
                            $teamAddErrors[$userId] = Get-GraphErrorText -ErrorRecord $_
                        }
                    }
                }

                $results = [System.Collections.Generic.List[object]]::new()
                foreach ($channelId in $channelIds) {
                    $channel = $channelsById[$channelId]
                    $channelMembersUri = "https://graph.microsoft.com/v1.0/teams/$teamId/channels/$(Get-GraphPathValue $channelId)/members"
                    $channelMemberIds = @{}
                    foreach ($member in Get-GraphPages -Uri $channelMembersUri -Trace $membershipTrace) {
                        if ($member.userId) { $channelMemberIds[$member.userId] = $true }
                    }

                    $channelAssignments = @($assignments | Where-Object { [string]$_.channelId -eq [string]$channelId })
                    foreach ($assignment in $channelAssignments) {
                        $userId = [string]$assignment.userId
                        $user = $users | Where-Object { [string]$_.id -eq $userId } | Select-Object -First 1
                        $upn = [string]$user.userPrincipalName
                        $channelRole = [string]$assignment.role
                        if ($teamAddErrors.ContainsKey($userId)) {
                            Add-MembershipTrace -Trace $membershipTrace -Status 'error' -Detail 'Không thêm vào kênh vì bước thêm vào Team cha thất bại.'
                            $results.Add(@{ channel = $channel.displayName; user = $upn; status = 'TeamAddError'; detail = $teamAddErrors[$userId] })
                            continue
                        }
                        if ([string]::IsNullOrWhiteSpace($userId) -or -not $teamMemberIds.ContainsKey($userId)) {
                            Add-MembershipTrace -Trace $membershipTrace -Status 'error' -Detail 'Không thêm vào kênh vì người dùng chưa thuộc Team cha.'
                            $results.Add(@{ channel = $channel.displayName; user = $upn; status = 'NotInTeam'; detail = 'Add the person to the parent team first.' })
                            continue
                        }
                        if ($channelMemberIds.ContainsKey($userId)) {
                            Add-MembershipTrace -Trace $membershipTrace -Status 'info' -Detail 'Người dùng đã thuộc kênh; không gửi lệnh thêm hoặc đổi quyền kênh.'
                            $results.Add(@{ channel = $channel.displayName; user = $upn; status = 'AlreadyMember'; detail = 'Already in this channel.' })
                            continue
                        }

                        $result = @{ channel = $channel.displayName; user = $upn; status = ''; detail = '' }
                        try {
                            $channelRoles = [string[]]@()
                            if ($channelRole -eq 'owner') { $channelRoles = [string[]]@('owner') }
                            $memberBody = @{
                                '@odata.type' = '#microsoft.graph.aadUserConversationMember'
                                roles = $channelRoles
                                'user@odata.bind' = "https://graph.microsoft.com/v1.0/users('$userId')"
                            }
                            $memberUri = "https://graph.microsoft.com/v1.0/teams/$teamId/channels/$(Get-GraphPathValue $channelId)/members"
                            Invoke-MembershipGraphRequest -Method POST -Uri $memberUri -Body $memberBody -Trace $membershipTrace | Out-Null
                            $channelMemberIds[$userId] = $true
                            $result.status = 'Added'
                            $result.detail = if ($channelRole -eq 'owner') { 'Added as channel owner.' } else { 'Added as channel member.' }
                        }
                        catch {
                            $result.status = 'Error'
                            $result.detail = Get-GraphErrorText -ErrorRecord $_
                        }
                        $results.Add($result)
                    }
                }

                Send-JsonResponse -Context $context -Value @{ flow = 'privateChannels'; results = $results.ToArray(); trace = $membershipTrace.ToArray(); events = $membershipEvents.ToArray() }
                continue
            }

            Send-JsonResponse -Context $context -StatusCode 404 -Value @{ error = 'Unknown API route.' }
        }
        catch {
            if (-not $context.Response.OutputStream.CanWrite) { continue }
            try {
                $errorResponse = @{ error = Get-GraphErrorText -ErrorRecord $_ }
                if ($path -eq '/api/members' -and $null -ne $membershipTrace) {
                    $errorResponse.trace = $membershipTrace.ToArray()
                    $errorResponse.events = $membershipEvents.ToArray()
                }
                Send-JsonResponse -Context $context -StatusCode 500 -Value $errorResponse
            }
            catch {
                try { $context.Response.Close() } catch {}
            }
        }
    }
}
finally {
    if ($listener.IsListening) { $listener.Stop() }
    $listener.Close()
}
