[CmdletBinding()]
param(
    [string]$PilotRoot = 'assets\pilot'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pilotPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $PilotRoot))
$characterSheetPath = Join-Path $pilotPath 'character-pilot.png'
$coreUiPath = Join-Path $pilotPath 'core-ui.png'
$screenshotPath = Join-Path $pilotPath 'screenshots'
$boardPath = Join-Path $pilotPath 'board'
$portraitPath = Join-Path $pilotPath 'portraits'

foreach ($path in @($screenshotPath, $boardPath, $portraitPath)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

function New-FitImage {
    param(
        [Parameter(Mandatory = $true)][Drawing.Image]$Source,
        [Parameter(Mandatory = $true)][Drawing.Rectangle]$SourceRectangle,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height,
        [Parameter(Mandatory = $true)][Drawing.Color]$Background
    )

    $destination = New-Object Drawing.Bitmap(
        $Width,
        $Height,
        [Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = [Drawing.Graphics]::FromImage($destination)
    try {
        $graphics.Clear($Background)
        $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighSpeed
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::None

        $scale = [Math]::Min(
            [double]$Width / [double]$SourceRectangle.Width,
            [double]$Height / [double]$SourceRectangle.Height
        )
        $scaledWidth = [Math]::Max(
            1,
            [int][Math]::Floor($SourceRectangle.Width * $scale)
        )
        $scaledHeight = [Math]::Max(
            1,
            [int][Math]::Floor($SourceRectangle.Height * $scale)
        )
        $left = [int][Math]::Floor(($Width - $scaledWidth) / 2)
        $top = [int][Math]::Floor(($Height - $scaledHeight) / 2)
        $destinationRectangle = New-Object Drawing.Rectangle(
            $left,
            $top,
            $scaledWidth,
            $scaledHeight
        )
        $graphics.DrawImage(
            $Source,
            $destinationRectangle,
            $SourceRectangle,
            [Drawing.GraphicsUnit]::Pixel
        )
    }
    finally {
        $graphics.Dispose()
    }
    return $destination
}

function Get-AlphaBounds {
    param(
        [Parameter(Mandatory = $true)][Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory = $true)][Drawing.Rectangle]$Cell
    )

    $left = $Cell.Right
    $top = $Cell.Bottom
    $right = $Cell.Left - 1
    $bottom = $Cell.Top - 1
    for ($y = $Cell.Top; $y -lt $Cell.Bottom; $y++) {
        for ($x = $Cell.Left; $x -lt $Cell.Right; $x++) {
            if ($Bitmap.GetPixel($x, $y).A -le 16) {
                continue
            }
            if ($x -lt $left) { $left = $x }
            if ($x -gt $right) { $right = $x }
            if ($y -lt $top) { $top = $y }
            if ($y -gt $bottom) { $bottom = $y }
        }
    }
    if ($right -lt $left -or $bottom -lt $top) {
        throw "No opaque pixels in sheet cell $Cell."
    }
    return New-Object Drawing.Rectangle(
        $left,
        $top,
        ($right - $left + 1),
        ($bottom - $top + 1)
    )
}

function Save-Png {
    param(
        [Parameter(Mandatory = $true)][Drawing.Image]$Image,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $Image.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
}

$characterSheet = New-Object Drawing.Bitmap($characterSheetPath)
try {
    if ($characterSheet.Width -lt 1000 -or $characterSheet.Height -lt 800) {
        throw "Character sheet is unexpectedly small: $($characterSheet.Width)x$($characterSheet.Height)."
    }
    $characterIds = @(
        'player-cost-1-scout',
        'player-cost-3-warden',
        'player-cost-5-sovereign',
        'monster-forest-horror',
        'boss-void-regent'
    )
    $directions = @('front', 'back', 'right', 'left')
    for ($row = 0; $row -lt $characterIds.Count; $row++) {
        $cellTop = [int][Math]::Floor(
            [double]($row * $characterSheet.Height) / $characterIds.Count
        )
        $cellBottom = [int][Math]::Floor(
            [double](($row + 1) * $characterSheet.Height) / $characterIds.Count
        )
        for ($column = 0; $column -lt $directions.Count; $column++) {
            $cellLeft = [int][Math]::Floor(
                [double]($column * $characterSheet.Width) / 5
            )
            $cellRight = [int][Math]::Floor(
                [double](($column + 1) * $characterSheet.Width) / 5
            )
            $cell = New-Object Drawing.Rectangle(
                $cellLeft,
                $cellTop,
                ($cellRight - $cellLeft),
                ($cellBottom - $cellTop)
            )
            $bounds = Get-AlphaBounds -Bitmap $characterSheet -Cell $cell
            $sprite = New-FitImage `
                -Source $characterSheet `
                -SourceRectangle $bounds `
                -Width 64 `
                -Height 64 `
                -Background ([Drawing.Color]::Transparent)
            try {
                Save-Png `
                    -Image $sprite `
                    -Path (Join-Path $boardPath (
                        "$($characterIds[$row])\$($directions[$column]).png"
                    ))
            }
            finally {
                $sprite.Dispose()
            }
        }

        $portraitLeft = [int][Math]::Floor(
            [double](4 * $characterSheet.Width) / 5
        )
        $portraitCell = New-Object Drawing.Rectangle(
            $portraitLeft,
            $cellTop,
            ($characterSheet.Width - $portraitLeft),
            ($cellBottom - $cellTop)
        )
        $portraitBounds = Get-AlphaBounds -Bitmap $characterSheet -Cell $portraitCell
        $portrait = New-FitImage `
            -Source $characterSheet `
            -SourceRectangle $portraitBounds `
            -Width 256 `
            -Height 256 `
            -Background ([Drawing.Color]::Transparent)
        try {
            Save-Png `
                -Image $portrait `
                -Path (Join-Path $portraitPath "$($characterIds[$row]).png")
        }
        finally {
            $portrait.Dispose()
        }
    }
}
finally {
    $characterSheet.Dispose()
}

$darkNavy = [Drawing.Color]::FromArgb(255, 8, 15, 25)
$transparent = [Drawing.Color]::Transparent
$responsiveVariants = @(
    @{ name = '16x9-720p-ui100.png'; width = 1280; height = 720 },
    @{ name = '16x9-1080p-ui125.png'; width = 1920; height = 1080 },
    @{ name = '16x9-1440p-ui150.png'; width = 2560; height = 1440 },
    @{ name = '4x3-1024x768-ui100.png'; width = 1024; height = 768 },
    @{ name = '16x10-1920x1200-ui125.png'; width = 1920; height = 1200 }
)
$coreUi = New-Object Drawing.Bitmap($coreUiPath)
try {
    $sourceRectangle = New-Object Drawing.Rectangle(
        0,
        0,
        $coreUi.Width,
        $coreUi.Height
    )
    foreach ($variant in $responsiveVariants) {
        $rendered = New-FitImage `
            -Source $coreUi `
            -SourceRectangle $sourceRectangle `
            -Width $variant.width `
            -Height $variant.height `
            -Background $darkNavy
        try {
            Save-Png `
                -Image $rendered `
                -Path (Join-Path $screenshotPath $variant.name)
        }
        finally {
            $rendered.Dispose()
        }
    }
}
finally {
    $coreUi.Dispose()
}

$colorSources = @{
    'protanopia' = (Join-Path $pilotPath 'source\core-ui-protanopia.png')
    'deuteranopia' = (Join-Path $pilotPath 'source\core-ui-deuteranopia.png')
    'tritanopia' = (Join-Path $pilotPath 'source\core-ui-tritanopia.png')
}
foreach ($mode in $colorSources.Keys) {
    $source = New-Object Drawing.Bitmap($colorSources[$mode])
    try {
        $sourceRectangle = New-Object Drawing.Rectangle(
            0,
            0,
            $source.Width,
            $source.Height
        )
        $rendered = New-FitImage `
            -Source $source `
            -SourceRectangle $sourceRectangle `
            -Width 1280 `
            -Height 720 `
            -Background $darkNavy
        try {
            Save-Png `
                -Image $rendered `
                -Path (Join-Path $screenshotPath "color-$mode-720p.png")
        }
        finally {
            $rendered.Dispose()
        }
    }
    finally {
        $source.Dispose()
    }
}

Write-Host 'Presentation pilot derivatives rendered.'
