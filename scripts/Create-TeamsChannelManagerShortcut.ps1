[CmdletBinding()]
param(
    [string]$ShortcutPath = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$installRoot = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $installRoot 'app/Start-PrivateChannelMembersUI.ps1'
$powerShell = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path -LiteralPath $powerShell)) { $powerShell = Join-Path $PSHOME 'pwsh.exe' }
$icon = Join-Path $installRoot 'app/web/toolms-shortcut.ico'
foreach ($file in @($launcher, $icon)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required file not found: $file" }
}
if ([string]::IsNullOrWhiteSpace($ShortcutPath)) {
    $desktopDirectory = [Environment]::GetFolderPath('DesktopDirectory')
    if ([string]::IsNullOrWhiteSpace($desktopDirectory) -or -not (Test-Path -LiteralPath $desktopDirectory -PathType Container)) { throw 'Windows Desktop folder is unavailable. Specify -ShortcutPath to choose another location.' }
    $ShortcutPath = Join-Path $desktopDirectory 'Teams Channel Manager.lnk'
}
if (-not [IO.Path]::IsPathRooted($ShortcutPath)) { $ShortcutPath = Join-Path (Get-Location).Path $ShortcutPath }
$ShortcutPath = [IO.Path]::GetFullPath($ShortcutPath)
if ([IO.Path]::GetExtension($ShortcutPath) -ine '.lnk') { throw 'ShortcutPath must end in .lnk.' }
if ((Test-Path -LiteralPath $ShortcutPath) -and -not $Force) { throw "Shortcut already exists; use -Force to repair it or choose another name: $ShortcutPath" }
if (-not (Test-Path -LiteralPath (Split-Path -Parent $ShortcutPath) -PathType Container)) { throw 'The shortcut destination folder does not exist.' }

$shell = New-Object -ComObject WScript.Shell
$shortcut = $null
try {
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $powerShell
    $shortcut.Arguments = '-NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -File "' + $launcher + '"'
    $shortcut.WorkingDirectory = $installRoot
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
