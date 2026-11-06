param(
    [string]$SourceIcon = "Resources\AppIcon-256.png"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$source = (Resolve-Path (Join-Path $root $SourceIcon)).Path
Add-Type -AssemblyName System.Drawing

function New-Art([int]$width, [int]$height, [string]$path, [int]$iconSize, [int]$iconX, [int]$iconY, [bool]$withText) {
    $bmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect,
        [System.Drawing.Color]::FromArgb(255, 252, 245, 232),
        [System.Drawing.Color]::FromArgb(255, 240, 215, 181), 90)
    $g.FillRectangle($brush, $rect)
    $brush.Dispose()

    $web = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(95, 255, 250, 240), 1.0)
    $cx = $width - 10
    $cy = -10
    foreach ($r in @(24, 42, 60, 78)) {
        $g.DrawArc($web, $cx - $r, $cy - $r, $r * 2, $r * 2, 90, 90)
    }
    for ($i = 0; $i -lt 6; $i++) {
        $a = [Math]::PI * $i / 10.0
        $g.DrawLine($web, $cx, $cy, $cx - [Math]::Cos($a) * 90, $cy + [Math]::Sin($a) * 90)
    }
    $web.Dispose()

    $icon = [System.Drawing.Image]::FromFile($source)
    $g.DrawImage($icon, $iconX, $iconY, $iconSize, $iconSize)
    $icon.Dispose()

    if ($withText) {
        $dark = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 55, 45, 36))
        $soft = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 115, 91, 66))
        $title = New-Object System.Drawing.Font("Segoe UI Semibold", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
        $sub = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
        $g.DrawString("Spider Buddy", $title, $dark, 12, ($height - 104))
        $g.DrawString("for Windows", $sub, $soft, 13, ($height - 82))
        $g.DrawString("a small companion", $sub, $soft, 13, ($height - 46))
        $title.Dispose(); $sub.Dispose(); $dark.Dispose(); $soft.Dispose()
    }

    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $bmp.Dispose()
    Write-Host "Wrote $path"
}

New-Art 164 314 (Join-Path $root "packaging\installer-art.bmp") 128 18 38 $true
New-Art 55 58 (Join-Path $root "packaging\installer-small.bmp") 44 5 4 $false
