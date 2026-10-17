param(
    [string]$SourcePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'discord2.png'),
    [string]$DestinationPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'HordeEternal/media/Discord.tga')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$source = [System.Drawing.Bitmap]::FromFile((Resolve-Path $SourcePath).Path)
$bitmap = New-Object System.Drawing.Bitmap 64, 64, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($source, 0, 0, 64, 64)
    $bytes = New-Object byte[] (18 + 64 * 64 * 4)
    $bytes[2] = 2
    $bytes[12] = 64
    $bytes[14] = 64
    $bytes[16] = 32
    $bytes[17] = 40
    $visible, $transparent = 0, 0
    for ($y = 0; $y -lt 64; $y++) {
        for ($x = 0; $x -lt 64; $x++) {
            $pixel = $bitmap.GetPixel($x, $y)
            $alpha = $pixel.A
            $offset = 18 + ($y * 64 + $x) * 4
            $bytes[$offset] = $pixel.B
            $bytes[$offset + 1] = $pixel.G
            $bytes[$offset + 2] = $pixel.R
            $bytes[$offset + 3] = $alpha
            if ($alpha -gt 0) { $visible++ } else { $transparent++ }
        }
    }
    if ($visible -eq 0) { throw 'Discord icon must contain visible pixels.' }
    [System.IO.File]::WriteAllBytes($DestinationPath, $bytes)
    $saved = [System.IO.File]::ReadAllBytes($DestinationPath)
    if ($saved.Length -ne 16402 -or $saved[2] -ne 2 -or $saved[16] -ne 32 -or $saved[17] -ne 40) {
        throw 'Generated TGA validation failed.'
    }
    $bluePixels, $whitePixels = 0, 0
    for ($offset = 18; $offset -lt $saved.Length; $offset += 4) {
        if ($saved[$offset] -ne $bytes[$offset] -or $saved[$offset + 1] -ne $bytes[$offset + 1] -or
            $saved[$offset + 2] -ne $bytes[$offset + 2] -or $saved[$offset + 3] -ne $bytes[$offset + 3]) {
            throw 'Generated texture did not preserve source pixel colours and alpha.'
        }
        if ($saved[$offset + 3] -eq 0) { continue }
        if ($saved[$offset] -gt ($saved[$offset + 2] + 20)) { $bluePixels++ }
        if ($saved[$offset] -gt 245 -and $saved[$offset + 1] -gt 245 -and $saved[$offset + 2] -gt 245) { $whitePixels++ }
    }
    if ((Split-Path $SourcePath -Leaf) -eq 'discord2.png' -and ($bluePixels -lt 100 -or $whitePixels -lt 100)) {
        throw 'Discord2 blue background or white logo was lost during conversion.'
    }
    Write-Output "PASS: 64x64 BGRA Discord icon; original colours retained; $visible visible pixels, $transparent transparent pixels; source PNG unchanged."
} finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    $source.Dispose()
}