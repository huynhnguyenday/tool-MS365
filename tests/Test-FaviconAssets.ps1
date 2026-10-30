[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $root 'Build-Favicon.ps1')

# A 2x2 block containing three white pixels must integrate to 75% white.
# Nearest-neighbor sampling would return either solid black or solid white.
$diagonal = New-Object byte[] 64
for ($y = 0; $y -lt 4; $y++) {
    for ($x = 0; $x -lt 4; $x++) {
        $i = ($y * 4 + $x) * 4
        $diagonal[$i + 3] = 255
        if ($x -ge $y) { $diagonal[$i] = 255; $diagonal[$i + 1] = 255; $diagonal[$i + 2] = 255 }
    }
}
$scaled = [TeamsChannelManager.FaviconRasterizer]::Resize($diagonal, 4, 4, 0, 0, 4, 2)
if ([Math]::Abs([int]$scaled[0] - 191) -gt 1 -or $scaled[4] -ne 255 -or $scaled[8] -ne 0) { throw 'Diagonal coverage is not antialiased correctly.' }

# Transparent black beside opaque white must not create a dark fringe.
$transparent = New-Object byte[] 64
for ($i = 0; $i -lt 32; $i++) { $transparent[$i] = 255 }
$scaled = [TeamsChannelManager.FaviconRasterizer]::Resize($transparent, 4, 4, 0, 0, 4, 1)
if ($scaled[0] -ne 255 -or $scaled[1] -ne 255 -or $scaled[2] -ne 255 -or $scaled[3] -ne 128) { throw 'Alpha processing creates a dark halo.' }

function Read-Frame([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try { return ([Windows.Media.Imaging.BitmapDecoder]::Create($stream, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)).Frames[0] }
    finally { $stream.Dispose() }
}
foreach ($size in @(16, 32)) {
    $frame = Read-Frame (Join-Path $root "favicon-$size.png")
    if ($frame.PixelWidth -ne $size -or $frame.PixelHeight -ne $size) { throw 'Wrong PNG dimensions.' }
    $converted = [Windows.Media.Imaging.FormatConvertedBitmap]::new($frame, [Windows.Media.PixelFormats]::Bgra32, $null, 0)
    $pixels = New-Object byte[] ($size * $size * 4)
    $converted.CopyPixels($pixels, $size * 4, 0)
    $edgePixels = 0
    for ($i = 0; $i -lt $pixels.Length; $i += 4) {
        if ($pixels[$i] -gt 30 -and $pixels[$i] -lt 220 -and $pixels[$i + 3] -gt 190) { $edgePixels++ }
    }
    if ($edgePixels -lt $size) { throw "${size}px favicon has too few filtered edge pixels; check for nearest-neighbor regression." }
    Write-Output "PASS ${size}px favicon: $edgePixels filtered edge pixels."
}
$stream = [IO.File]::OpenRead((Join-Path $root 'favicon.ico'))
try {
    $ico = [Windows.Media.Imaging.IconBitmapDecoder]::new($stream, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    if ((@($ico.Frames | ForEach-Object PixelWidth) -join ',') -ne '16,32,48') { throw 'Wrong ICO frame sizes.' }
}
finally { $stream.Dispose() }
Write-Output 'PASS analytical antialiasing, alpha-edge handling, actual PNG edge quality and ICO frame sizes.'
