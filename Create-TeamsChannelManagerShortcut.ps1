[CmdletBinding()]
param([string]$ShortcutPath = '')

$ErrorActionPreference = 'Stop'
$launcher = Join-Path $PSScriptRoot 'Open-PrivateChannelMembersUI.cmd'
$icon = Join-Path $PSScriptRoot 'toolms-shortcut.ico'
foreach ($file in @($launcher, $icon)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required file not found: $file" }
}
if ([string]::IsNullOrWhiteSpace($ShortcutPath)) {
    $ShortcutPath = Join-Path $PSScriptRoot 'Teams Channel Manager.lnk'
}
if (-not [IO.Path]::IsPathRooted($ShortcutPath)) { $ShortcutPath = Join-Path (Get-Location).Path $ShortcutPath }
$ShortcutPath = [IO.Path]::GetFullPath($ShortcutPath)
if ([IO.Path]::GetExtension($ShortcutPath) -ine '.lnk') { throw 'ShortcutPath must end in .lnk.' }
if (Test-Path -LiteralPath $ShortcutPath) { throw "Shortcut already exists; choose another name or change its icon in Properties: $ShortcutPath" }
if (-not (Test-Path -LiteralPath (Split-Path -Parent $ShortcutPath) -PathType Container)) { throw 'The shortcut destination folder does not exist.' }

$shell = New-Object -ComObject WScript.Shell
$shortcut = $null
try {
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $launcher
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.IconLocation = "$icon,0"
    $shortcut.Description = 'Open Teams Channel Manager'
    $shortcut.WindowStyle = 1
    $shortcut.Save()
    Write-Output "Created shortcut: $ShortcutPath"
}
finally {
    if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
}
