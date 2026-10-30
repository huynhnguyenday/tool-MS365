[CmdletBinding()]
param([string]$SourcePath = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourcePath)) { $SourcePath = Join-Path $PSScriptRoot 'favicon-source.png' }
Add-Type -AssemblyName PresentationCore
if (-not ('TeamsChannelManager.FaviconRasterizer' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
namespace TeamsChannelManager {
    public static class FaviconRasterizer {
        public static int[] Bounds(byte[] pixels, int width, int height) {
            int left = width, top = height, right = -1, bottom = -1;
            for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) {
                if (pixels[(y * width + x) * 4 + 3] < 200) continue;
                left = Math.Min(left, x); top = Math.Min(top, y);
                right = Math.Max(right, x); bottom = Math.Max(bottom, y);
            }
            if (right < left) throw new ArgumentException("Source image has no opaque content.");
            return new int[] { left, top, right, bottom };
        }
        // Integrate every source pixel covered by each destination pixel.
        // Accumulate premultiplied colors to avoid halos at transparent edges.
        public static byte[] Resize(byte[] pixels, int width, int height,
                                    int left, int top, int side, int size) {
            byte[] output = new byte[size * size * 4];
            for (int y = 0; y < size; y++) for (int x = 0; x < size; x++) {
                double x0 = left + x * (double)side / size;
                double x1 = left + (x + 1) * (double)side / size;
                double y0 = top + y * (double)side / size;
                double y1 = top + (y + 1) * (double)side / size;
                double alpha = 0, blue = 0, green = 0, red = 0;
                for (int sy = (int)Math.Floor(y0); sy < Math.Ceiling(y1) && sy < height; sy++) {
                    for (int sx = (int)Math.Floor(x0); sx < Math.Ceiling(x1) && sx < width; sx++) {
                        if (sx < 0 || sy < 0) continue;
                        double weight = (Math.Min(x1, sx + 1) - Math.Max(x0, sx)) *
                                        (Math.Min(y1, sy + 1) - Math.Max(y0, sy));
                        int index = (sy * width + sx) * 4;
                        double weightedAlpha = pixels[index + 3] * weight;
                        alpha += weightedAlpha;
                        blue += pixels[index] * weightedAlpha;
                        green += pixels[index + 1] * weightedAlpha;
                        red += pixels[index + 2] * weightedAlpha;
                    }
                }
                int destination = (y * size + x) * 4;
                if (alpha > 0) {
                    output[destination] = (byte)Math.Round(blue / alpha);
                    output[destination + 1] = (byte)Math.Round(green / alpha);
                    output[destination + 2] = (byte)Math.Round(red / alpha);
                }
                output[destination + 3] = (byte)Math.Round(alpha / ((x1 - x0) * (y1 - y0)));
            }
            return output;
        }
    }
}
'@
}

$stream = [IO.File]::OpenRead((Resolve-Path -LiteralPath $SourcePath).Path)
try {
    $decoder = [Windows.Media.Imaging.BitmapDecoder]::Create($stream, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $source = [Windows.Media.Imaging.FormatConvertedBitmap]::new($decoder.Frames[0], [Windows.Media.PixelFormats]::Bgra32, $null, 0)
}
finally { $stream.Dispose() }
$width = $source.PixelWidth; $height = $source.PixelHeight
$pixels = New-Object byte[] ($width * $height * 4)
$source.CopyPixels($pixels, $width * 4, 0)
$bounds = [TeamsChannelManager.FaviconRasterizer]::Bounds($pixels, $width, $height)
$side = [Math]::Min([Math]::Min($width, $height), [Math]::Max($bounds[2] - $bounds[0] + 1, $bounds[3] - $bounds[1] + 1) + 4)
$left = [Math]::Max(0, [Math]::Min($width - $side, [int][Math]::Floor(($bounds[0] + $bounds[2] + 1 - $side) / 2)))
$top = [Math]::Max(0, [Math]::Min($height - $side, [int][Math]::Floor(($bounds[1] + $bounds[3] + 1 - $side) / 2)))
$frames = @()
foreach ($size in @(16, 32, 48)) {
    $resized = [TeamsChannelManager.FaviconRasterizer]::Resize($pixels, $width, $height, $left, $top, $side, $size)
    $bitmap = [Windows.Media.Imaging.BitmapSource]::Create($size, $size, 96, 96, [Windows.Media.PixelFormats]::Bgra32, $null, $resized, $size * 4)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $buffer = [IO.MemoryStream]::new()
    try {
        $encoder.Save($buffer)
        $bytes = $buffer.ToArray()
        $frames += @{ Size = $size; Bytes = $bytes }
        if ($size -in @(16, 32)) { [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot "favicon-$size.png"), $bytes) }
    }
    finally { $buffer.Dispose() }
}
$writer = [IO.BinaryWriter]::new([IO.File]::Create((Join-Path $PSScriptRoot 'favicon.ico')))
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
    $offset = 6 + 16 * $frames.Count
    foreach ($frame in $frames) {
        $writer.Write([byte]$frame.Size); $writer.Write([byte]$frame.Size)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$frame.Bytes.Length); $writer.Write([uint32]$offset)
        $offset += $frame.Bytes.Length
    }
    foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
}
finally { $writer.Dispose() }
Write-Output 'Built favicon PNG 16/32 and ICO 16/32/48 with alpha-aware area resampling.'
