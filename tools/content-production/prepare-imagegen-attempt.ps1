param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$Unit,
    [Parameter(Mandatory = $true)][string]$Attempt
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-NearestBitmap {
    param(
        [System.Drawing.Image]$Source,
        [System.Drawing.Rectangle]$SourceRect,
        [int]$Width,
        [int]$Height,
        [bool]$TransparentChroma = $false
    )
    $bitmap = New-Object System.Drawing.Bitmap $Width, $Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $graphics.DrawImage($Source, [System.Drawing.Rectangle]::new(0, 0, $Width, $Height), $SourceRect, [System.Drawing.GraphicsUnit]::Pixel)
    }
    finally {
        $graphics.Dispose()
    }
    if ($TransparentChroma) {
        # Remove only magenta-like pixels connected to an image edge. This clears
        # antialiased/chroma-compressed spill without erasing enclosed purple gear.
        $visited = New-Object bool[] ($bitmap.Width * $bitmap.Height)
        $queue = [System.Collections.Generic.Queue[int]]::new()
        $edgeIndexes = [System.Collections.Generic.List[int]]::new()
        for ($x = 0; $x -lt $bitmap.Width; $x++) {
            $edgeIndexes.Add($x)
            $edgeIndexes.Add((($bitmap.Height - 1) * $bitmap.Width) + $x)
        }
        for ($y = 1; $y -lt ($bitmap.Height - 1); $y++) {
            $edgeIndexes.Add($y * $bitmap.Width)
            $edgeIndexes.Add(($y * $bitmap.Width) + $bitmap.Width - 1)
        }
        foreach ($edgeIndex in $edgeIndexes) {
            if ($visited[$edgeIndex]) { continue }
            $visited[$edgeIndex] = $true
            $edgeX = $edgeIndex % $bitmap.Width
            $edgeY = [int][Math]::Floor($edgeIndex / [double]$bitmap.Width)
            $pixel = $bitmap.GetPixel($edgeX, $edgeY)
            if ($pixel.R -ge 120 -and $pixel.B -ge 120 -and $pixel.G -le 150 -and ([Math]::Min($pixel.R, $pixel.B) - $pixel.G) -ge 45) {
                $queue.Enqueue($edgeIndex)
            }
        }
        $offsets = @(@(-1, 0), @(1, 0), @(0, -1), @(0, 1))
        while ($queue.Count -gt 0) {
            $index = $queue.Dequeue()
            $x = $index % $bitmap.Width
            $y = [int][Math]::Floor($index / [double]$bitmap.Width)
            $bitmap.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
            foreach ($offset in $offsets) {
                $nextX = $x + $offset[0]
                $nextY = $y + $offset[1]
                if ($nextX -lt 0 -or $nextX -ge $bitmap.Width -or $nextY -lt 0 -or $nextY -ge $bitmap.Height) { continue }
                $nextIndex = ($nextY * $bitmap.Width) + $nextX
                if ($visited[$nextIndex]) { continue }
                $visited[$nextIndex] = $true
                $nextPixel = $bitmap.GetPixel($nextX, $nextY)
                if ($nextPixel.R -ge 120 -and $nextPixel.B -ge 120 -and $nextPixel.G -le 150 -and ([Math]::Min($nextPixel.R, $nextPixel.B) - $nextPixel.G) -ge 45) {
                    $queue.Enqueue($nextIndex)
                }
            }
        }
    }
    return $bitmap
}

$attemptDir = Join-Path $Repo ("assets\production\attempts\{0}\{1}" -f $Unit, $Attempt)
$rawPath = Join-Path $attemptDir 'raw.png'
if (-not (Test-Path -LiteralPath $rawPath)) {
    throw "Missing raw candidate: $rawPath"
}

$source = [System.Drawing.Image]::FromFile($rawPath)
try {
    $fullRect = [System.Drawing.Rectangle]::new(0, 0, $source.Width, $source.Height)
    $normalized = New-NearestBitmap -Source $source -SourceRect $fullRect -Width 1280 -Height 1280
    try { $normalized.Save((Join-Path $attemptDir 'source-sheet-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $normalized.Dispose() }

    $cellWidth = [int][Math]::Round($source.Width / 5.0)
    $cellHeight = [int][Math]::Round($source.Height / 5.0)
    $margin = 5

    $portraitRect = [System.Drawing.Rectangle]::new($margin, (4 * $cellHeight) + $margin, $cellWidth - (2 * $margin), $cellHeight - (2 * $margin))
    $portrait = New-NearestBitmap -Source $source -SourceRect $portraitRect -Width 256 -Height 256 -TransparentChroma $true
    try { $portrait.Save((Join-Path $attemptDir 'portrait-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $portrait.Dispose() }

    $board = New-NearestBitmap -Source $source -SourceRect $portraitRect -Width 128 -Height 128 -TransparentChroma $true
    try { $board.Save((Join-Path $attemptDir 'board-icon-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $board.Dispose() }

    $idleRect = [System.Drawing.Rectangle]::new($margin, $margin, $cellWidth - (2 * $margin), $cellHeight - (2 * $margin))
    $directionStrip = New-Object System.Drawing.Bitmap 512, 128, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stripGraphics = [System.Drawing.Graphics]::FromImage($directionStrip)
    try {
        $stripGraphics.Clear([System.Drawing.Color]::Transparent)
        $stripGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $halfWidth = [int]($idleRect.Width / 2)
        $halfHeight = [int]($idleRect.Height / 2)
        $quadrants = @(
            [System.Drawing.Rectangle]::new($idleRect.X, $idleRect.Y, $halfWidth, $halfHeight),
            [System.Drawing.Rectangle]::new($idleRect.X + $halfWidth, $idleRect.Y, $idleRect.Width - $halfWidth, $halfHeight),
            [System.Drawing.Rectangle]::new($idleRect.X + $halfWidth, $idleRect.Y + $halfHeight, $idleRect.Width - $halfWidth, $idleRect.Height - $halfHeight),
            [System.Drawing.Rectangle]::new($idleRect.X, $idleRect.Y + $halfHeight, $halfWidth, $idleRect.Height - $halfHeight)
        )
        for ($index = 0; $index -lt 4; $index++) {
            $tile = New-NearestBitmap -Source $source -SourceRect $quadrants[$index] -Width 128 -Height 128 -TransparentChroma $true
            try { $stripGraphics.DrawImageUnscaled($tile, 128 * $index, 0) }
            finally { $tile.Dispose() }
        }
    }
    finally {
        $stripGraphics.Dispose()
    }
    try { $directionStrip.Save((Join-Path $attemptDir 'direction-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $directionStrip.Dispose() }
}
finally {
    $source.Dispose()
}

Write-Output "Prepared review previews for $Unit/$Attempt"
