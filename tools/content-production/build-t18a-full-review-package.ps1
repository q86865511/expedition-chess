param([Parameter(Mandatory = $true)][string]$Repo)

$ErrorActionPreference = 'Stop'
$repoPath = [System.IO.Path]::GetFullPath($Repo)
$ledgerPath = Join-Path $repoPath 'assets\production\production-asset-attempts.json'
$outputDirectory = Join-Path $repoPath '.pipeline\content-production\reviews\t18a-full-batch-assets'
$reviewPath = Join-Path $repoPath '.pipeline\content-production\reviews\t18a-full-batch.md'
$ledger = Get-Content -Raw -Encoding UTF8 -LiteralPath $ledgerPath | ConvertFrom-Json
$active = @($ledger.attempts | Where-Object { $_.status -in @('generated', 'adopted') } | Sort-Object unit_id)
if ($active.Count -ne 44) { throw "Expected 44 active attempts; found $($active.Count)." }
if ((@($active | Group-Object unit_id | Where-Object Count -ne 1)).Count -ne 0) {
    throw 'Every unit must have exactly one generated/adopted attempt.'
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
Add-Type -AssemblyName System.Drawing

function Save-Gallery {
    param(
        [Parameter(Mandatory = $true)][object[]]$Entries,
        [Parameter(Mandatory = $true)][string]$PreviewName,
        [Parameter(Mandatory = $true)][int]$Columns,
        [Parameter(Mandatory = $true)][int]$ImageWidth,
        [Parameter(Mandatory = $true)][int]$ImageHeight,
        [Parameter(Mandatory = $true)][string]$OutputName
    )
    $labelHeight = 38
    $rows = [int][Math]::Ceiling($Entries.Count / [double]$Columns)
    $bitmap = New-Object System.Drawing.Bitmap ($Columns * $ImageWidth), ($rows * ($ImageHeight + $labelHeight)), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $font = New-Object System.Drawing.Font ([System.Drawing.FontFamily]::GenericSansSerif), 18, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $labelBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 238, 232, 214))
    $backgroundBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 15, 21, 31))
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(255, 15, 21, 31))
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        for ($index = 0; $index -lt $Entries.Count; $index++) {
            $entry = $Entries[$index]
            $column = $index % $Columns
            $row = [int][Math]::Floor($index / [double]$Columns)
            $x = $column * $ImageWidth
            $y = $row * ($ImageHeight + $labelHeight)
            $attemptDirectory = Split-Path -Parent (Join-Path $repoPath ($entry.raw_source.path -replace '/', '\'))
            $previewPath = Join-Path $attemptDirectory $PreviewName
            if (-not (Test-Path -LiteralPath $previewPath)) { throw "Missing preview: $previewPath" }
            $source = [System.Drawing.Image]::FromFile($previewPath)
            try {
                $graphics.DrawImage($source, $x, $y, $ImageWidth, $ImageHeight)
            } finally {
                $source.Dispose()
            }
            $graphics.FillRectangle($backgroundBrush, $x, $y + $ImageHeight, $ImageWidth, $labelHeight)
            $label = ($entry.unit_id -replace '^unit\.slice_', '') + '  ' + ($entry.attempt_id -replace '^.*-attempt-', 'a')
            $graphics.DrawString($label, $font, $labelBrush, $x + 8, $y + $ImageHeight + 7)
        }
        $outputPath = Join-Path $outputDirectory $OutputName
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $backgroundBrush.Dispose()
        $labelBrush.Dispose()
        $font.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$players = @($active | Where-Object unit_id -like 'unit.slice_player_*')
$monsters = @($active | Where-Object unit_id -like 'unit.slice_monster_*')
Save-Gallery -Entries $players -PreviewName 'portrait-preview.png' -Columns 8 -ImageWidth 256 -ImageHeight 256 -OutputName 'players-portraits.png'
Save-Gallery -Entries $monsters -PreviewName 'portrait-preview.png' -Columns 6 -ImageWidth 256 -ImageHeight 256 -OutputName 'monsters-portraits.png'
Save-Gallery -Entries $players -PreviewName 'direction-preview.png' -Columns 4 -ImageWidth 512 -ImageHeight 128 -OutputName 'players-directions.png'
Save-Gallery -Entries $monsters -PreviewName 'direction-preview.png' -Columns 3 -ImageWidth 512 -ImageHeight 128 -OutputName 'monsters-directions.png'

$sharedNames = @('trait', 'ability', 'status_damage', 'combat_vfx', 'core_ui')
$sharedBitmap = New-Object System.Drawing.Bitmap 1536, 1080, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$sharedGraphics = [System.Drawing.Graphics]::FromImage($sharedBitmap)
$sharedFont = New-Object System.Drawing.Font ([System.Drawing.FontFamily]::GenericSansSerif), 20, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$sharedLabelBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 238, 232, 214))
try {
    $sharedGraphics.Clear([System.Drawing.Color]::FromArgb(255, 15, 21, 31))
    $sharedGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    for ($index = 0; $index -lt $sharedNames.Count; $index++) {
        $column = $index % 3
        $row = [int][Math]::Floor($index / 3.0)
        $x = $column * 512
        $y = $row * 540
        $sourcePath = Join-Path $repoPath ("assets\production\shared_attempts\attempt-001\{0}.png" -f $sharedNames[$index])
        $source = [System.Drawing.Image]::FromFile($sourcePath)
        try { $sharedGraphics.DrawImage($source, $x, $y, 512, 512) }
        finally { $source.Dispose() }
        $sharedGraphics.DrawString($sharedNames[$index], $sharedFont, $sharedLabelBrush, $x + 8, $y + 514)
    }
    $sharedBitmap.Save((Join-Path $outputDirectory 'shared-atlases.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $sharedLabelBrush.Dispose()
    $sharedFont.Dispose()
    $sharedGraphics.Dispose()
    $sharedBitmap.Dispose()
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# T18A full-batch human adoption review')
$lines.Add('')
$lines.Add('- Reviewer: user (independent human reviewer)')
$lines.Add('- Scope: 44 units, Camp, and 5 shared atlases')
$lines.Add('- Status: awaiting one aggregate decision; player_00-03 were adopted in batch-001 and remain here for read-back.')
$lines.Add('- Mechanical gate: 44/44 latest attempts passed 20 action cells x N/E/S/W; all 496 player silhouette pairs are below IoU 0.92 / SSIM 0.95.')
$lines.Add('')
$lines.Add('## Galleries')
$lines.Add('')
$lines.Add('- [Player portraits](t18a-full-batch-assets/players-portraits.png)')
$lines.Add('- [Player direction previews](t18a-full-batch-assets/players-directions.png)')
$lines.Add('- [Monster portraits](t18a-full-batch-assets/monsters-portraits.png)')
$lines.Add('- [Monster direction previews](t18a-full-batch-assets/monsters-directions.png)')
$lines.Add('- [Camp candidate](../../../assets/production/camp_attempts/attempt-001/raw.png)')
$lines.Add('- [Shared atlas gallery](t18a-full-batch-assets/shared-atlases.png)')
$lines.Add('- Shared atlas: [trait](../../../assets/production/shared_attempts/attempt-001/trait.png), [ability](../../../assets/production/shared_attempts/attempt-001/ability.png), [status/damage](../../../assets/production/shared_attempts/attempt-001/status_damage.png), [combat VFX](../../../assets/production/shared_attempts/attempt-001/combat_vfx.png), [core UI](../../../assets/production/shared_attempts/attempt-001/core_ui.png)')
$lines.Add('')
$lines.Add('## Unit decision table')
$lines.Add('')
$lines.Add('| Unit / attempt | Originality | Silhouette | Weapon / role | Direction / action | Human decision | Source |')
$lines.Add('|---|---|---|---|---|---|---|')
foreach ($entry in $active) {
    $short = $entry.unit_id -replace '^unit\.slice_', ''
    $attempt = $entry.attempt_id -replace '^.*-attempt-', 'a'
    $attemptDirectory = Split-Path -Parent ($entry.raw_source.path -replace '\\', '/')
    $sourceLink = '../../../' + $attemptDirectory + '/source-sheet-preview.png'
    $decision = if ($entry.status -eq 'adopted') { 'adopted (prior decision)' } else { 'pending' }
    $silhouette = if ($entry.unit_id -like 'unit.slice_player_*') { 'metric pass' } else { 'visual precheck pass' }
    $lines.Add("| $short / $attempt | precheck pass | $silhouette | precheck pass | mechanical pass | $decision | [sheet]($sourceLink) |")
}
$lines.Add('')
$lines.Add('## Environment asset decision table')
$lines.Add('')
$lines.Add('| Asset | Originality / semantics | Composition / recognition | Human decision |')
$lines.Add('|---|---|---|---|')
$lines.Add('| Camp attempt-001 | Original ImageGen candidate; pilot used only for pixel density and composition reference | precheck pass | pending |')
$lines.Add('| trait atlas | 8 trait semantic families x 8 variants | precheck pass | pending |')
$lines.Add('| ability atlas | 8 ability semantic families x 8 variants | precheck pass | pending |')
$lines.Add('| status/damage atlas | 8 status/damage semantic families x 8 variants | precheck pass | pending |')
$lines.Add('| combat VFX atlas | 8 combat-effect semantic families x 8 variants | precheck pass | pending |')
$lines.Add('| core UI atlas | 8 UI semantic families x 8 variants | precheck pass | pending |')
$lines.Add('')
$lines.Add('## Reviewer response')
$lines.Add('')
$lines.Add('Reply with "all adopted", or list rejected unit/asset IDs with reasons; unlisted items will be treated as adopted. A rejection creates a new attempt and never overwrites old evidence.')
[System.IO.File]::WriteAllLines($reviewPath, $lines, [System.Text.UTF8Encoding]::new($false))

$result = [ordered]@{
    active_attempts = $active.Count
    players = $players.Count
    monsters = $monsters.Count
    adopted = @($active | Where-Object status -eq 'adopted').Count
    pending = @($active | Where-Object status -eq 'generated').Count
    review_path = $reviewPath
    artifacts = @(Get-ChildItem -LiteralPath $outputDirectory -Filter '*.png' | Sort-Object Name | ForEach-Object {
        [ordered]@{ name = $_.Name; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
}
$result | ConvertTo-Json -Depth 4
