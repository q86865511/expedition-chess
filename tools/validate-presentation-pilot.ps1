[CmdletBinding()]
param(
    [string]$PilotRoot = 'assets\pilot',
    [string]$OutputPath = '.pipeline\visual\pui-t13-asset-validation.json'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pilotPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $PilotRoot))
$inventoryPath = Join-Path $pilotPath 'inventory.json'
$issues = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]
$deliveryPaths = New-Object System.Collections.Generic.HashSet[string](
    [StringComparer]::OrdinalIgnoreCase
)
$allExpectedPngPaths = New-Object System.Collections.Generic.HashSet[string](
    [StringComparer]::OrdinalIgnoreCase
)

function Add-Issue {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $issues.Add([ordered]@{
        code = $Code
        path = $Path.Replace('\', '/')
        detail = $Detail
    })
}

function Add-Warning {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $warnings.Add([ordered]@{
        code = $Code
        path = $Path.Replace('\', '/')
        detail = $Detail
    })
}

function Resolve-ResourcePath {
    param([Parameter(Mandatory = $true)][string]$ResourcePath)

    if (-not $ResourcePath.StartsWith('res://', [StringComparison]::Ordinal)) {
        throw "Pilot inventory path is not res:// scoped: $ResourcePath"
    }
    return [IO.Path]::GetFullPath(
        (Join-Path $repoRoot $ResourcePath.Substring(6).Replace('/', '\'))
    )
}

function Get-RepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    return $AbsolutePath.Substring($repoRoot.Length + 1).Replace('\', '/')
}

function Register-Png {
    param(
        [Parameter(Mandatory = $true)][string]$ResourcePath,
        [bool]$Delivery = $true
    )

    $absolutePath = Resolve-ResourcePath -ResourcePath $ResourcePath
    [void]$allExpectedPngPaths.Add($absolutePath)
    if ($Delivery) {
        [void]$deliveryPaths.Add($absolutePath)
    }
    return $absolutePath
}

function Test-Png {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$ExpectedWidth = 0,
        [int]$ExpectedHeight = 0,
        [bool]$RequireTransparentCorners = $false
    )

    $relative = Get-RepoRelativePath -AbsolutePath $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Issue -Code 'PUI_PILOT_ASSET_MISSING' -Path $relative -Detail 'PNG is missing.'
        return
    }
    $bitmap = $null
    try {
        $bitmap = New-Object Drawing.Bitmap($Path)
        if (
            ($ExpectedWidth -gt 0 -and $bitmap.Width -ne $ExpectedWidth) -or
            ($ExpectedHeight -gt 0 -and $bitmap.Height -ne $ExpectedHeight)
        ) {
            Add-Issue `
                -Code 'PUI_PILOT_DIMENSION_INVALID' `
                -Path $relative `
                -Detail (
                    "Expected ${ExpectedWidth}x${ExpectedHeight}, got " +
                    "$($bitmap.Width)x$($bitmap.Height)."
                )
        }
        if (-not $RequireTransparentCorners) {
            return
        }
        $corners = @(
            $bitmap.GetPixel(0, 0),
            $bitmap.GetPixel($bitmap.Width - 1, 0),
            $bitmap.GetPixel(0, $bitmap.Height - 1),
            $bitmap.GetPixel($bitmap.Width - 1, $bitmap.Height - 1)
        )
        if (@($corners | Where-Object { $_.A -ne 0 }).Count -gt 0) {
            Add-Issue `
                -Code 'PUI_PILOT_ALPHA_BOUNDARY_INVALID' `
                -Path $relative `
                -Detail 'All four canvas corners must be fully transparent.'
        }
        $opaqueCount = 0
        for ($y = 0; $y -lt $bitmap.Height; $y++) {
            for ($x = 0; $x -lt $bitmap.Width; $x++) {
                if ($bitmap.GetPixel($x, $y).A -gt 16) {
                    $opaqueCount++
                }
            }
        }
        if ($opaqueCount -eq 0 -or $opaqueCount -eq ($bitmap.Width * $bitmap.Height)) {
            Add-Issue `
                -Code 'PUI_PILOT_ALPHA_COVERAGE_INVALID' `
                -Path $relative `
                -Detail 'Canvas must contain both visible subject pixels and transparent padding.'
        }
    }
    catch {
        Add-Issue `
            -Code 'PUI_PILOT_PNG_INVALID' `
            -Path $relative `
            -Detail $_.Exception.Message
    }
    finally {
        if ($null -ne $bitmap) {
            $bitmap.Dispose()
        }
    }
}

if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
    Add-Issue `
        -Code 'PUI_PILOT_INVENTORY_MISSING' `
        -Path (Get-RepoRelativePath -AbsolutePath $inventoryPath) `
        -Detail 'inventory.json is required.'
    $inventory = $null
}
else {
    try {
        $inventory = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        Add-Issue `
            -Code 'PUI_PILOT_INVENTORY_INVALID' `
            -Path (Get-RepoRelativePath -AbsolutePath $inventoryPath) `
            -Detail $_.Exception.Message
        $inventory = $null
    }
}

if ($null -ne $inventory) {
    if (
        [int]$inventory.schema_version -ne 1 -or
        [string]$inventory.slice -cne 'presentation-ui' -or
        [string]$inventory.task -cne 'T13'
    ) {
        Add-Issue `
            -Code 'PUI_PILOT_INVENTORY_INVALID' `
            -Path 'assets/pilot/inventory.json' `
            -Detail 'Schema, slice, or task identity is invalid.'
    }
    $approvalStatus = [string]$inventory.status
    $isUserApproved = [bool]$inventory.user_approved
    $approvalStateValid = (
        ($approvalStatus -ceq 'candidate_pending_user_approval' -and -not $isUserApproved) -or
        ($approvalStatus -ceq 'user_approved' -and $isUserApproved)
    )
    if (-not $approvalStateValid) {
        Add-Issue `
            -Code 'PUI_PILOT_APPROVAL_STATE_INVALID' `
            -Path 'assets/pilot/inventory.json' `
            -Detail 'Status and user_approved must form a valid pending or approved pair.'
    }
    if ([string]$inventory.generation_seed -ceq 'not_exposed_by_builtin_image_gen') {
        Add-Warning `
            -Code 'PUI_PILOT_SEED_NOT_EXPOSED' `
            -Path 'assets/pilot/provenance.md' `
            -Detail 'Built-in image_gen does not expose a model-native seed; SHA-256 identifies outputs.'
    }

    $characters = @($inventory.characters)
    if ($characters.Count -ne 5) {
        Add-Issue `
            -Code 'PUI_PILOT_CHARACTER_COUNT_INVALID' `
            -Path 'assets/pilot/inventory.json' `
            -Detail "Expected five pilot characters, got $($characters.Count)."
    }
    $playerCosts = @(
        $characters |
            Where-Object { [string]$_.kind -ceq 'player' } |
            ForEach-Object { [int]$_.cost } |
            Sort-Object
    )
    if (($playerCosts -join ',') -cne '1,3,5') {
        Add-Issue `
            -Code 'PUI_PILOT_PLAYER_COSTS_INVALID' `
            -Path 'assets/pilot/inventory.json' `
            -Detail "Expected player costs 1,3,5; got $($playerCosts -join ',')."
    }
    if (@($characters | Where-Object { [string]$_.kind -ceq 'monster' }).Count -ne 1) {
        Add-Issue `
            -Code 'PUI_PILOT_MONSTER_COUNT_INVALID' `
            -Path 'assets/pilot/inventory.json' `
            -Detail 'Expected exactly one monster.'
    }
    if (@($characters | Where-Object { [string]$_.kind -ceq 'boss' }).Count -ne 1) {
        Add-Issue `
            -Code 'PUI_PILOT_BOSS_COUNT_INVALID' `
            -Path 'assets/pilot/inventory.json' `
            -Detail 'Expected exactly one boss.'
    }
    foreach ($character in $characters) {
        $directions = @($character.board)
        if ($directions.Count -ne 4) {
            Add-Issue `
                -Code 'PUI_PILOT_DIRECTION_COUNT_INVALID' `
                -Path 'assets/pilot/inventory.json' `
                -Detail "$($character.id) requires four board directions."
        }
        foreach ($resourcePath in $directions) {
            $path = Register-Png -ResourcePath ([string]$resourcePath)
            Test-Png `
                -Path $path `
                -ExpectedWidth 64 `
                -ExpectedHeight 64 `
                -RequireTransparentCorners $true
        }
        $portraitPathValue = Register-Png -ResourcePath ([string]$character.portrait)
        Test-Png `
            -Path $portraitPathValue `
            -ExpectedWidth 256 `
            -ExpectedHeight 256 `
            -RequireTransparentCorners $true
    }

    $characterSheet = Register-Png -ResourcePath ([string]$inventory.character_sheet)
    Test-Png -Path $characterSheet -RequireTransparentCorners $true

    $campPath = Register-Png -ResourcePath ([string]$inventory.environment.path)
    Test-Png -Path $campPath
    $coreUiPath = Register-Png -ResourcePath ([string]$inventory.core_ui.path)
    Test-Png -Path $coreUiPath

    $responsiveDimensions = [ordered]@{
        '16x9-720p-ui100.png' = @(1280, 720)
        '16x9-1080p-ui125.png' = @(1920, 1080)
        '16x9-1440p-ui150.png' = @(2560, 1440)
        '4x3-1024x768-ui100.png' = @(1024, 768)
        '16x10-1920x1200-ui125.png' = @(1920, 1200)
    }
    foreach ($resourcePath in @($inventory.responsive_screenshots)) {
        $path = Register-Png -ResourcePath ([string]$resourcePath)
        $name = [IO.Path]::GetFileName($path)
        if (-not $responsiveDimensions.Contains($name)) {
            Add-Issue `
                -Code 'PUI_PILOT_SCREENSHOT_UNEXPECTED' `
                -Path (Get-RepoRelativePath -AbsolutePath $path) `
                -Detail 'Responsive screenshot name is not in the fixed matrix.'
            continue
        }
        $dimensions = $responsiveDimensions[$name]
        Test-Png `
            -Path $path `
            -ExpectedWidth $dimensions[0] `
            -ExpectedHeight $dimensions[1]
    }
    if (@($inventory.responsive_screenshots).Count -ne 5) {
        Add-Issue `
            -Code 'PUI_PILOT_SCREENSHOT_MATRIX_INCOMPLETE' `
            -Path 'assets/pilot/inventory.json' `
            -Detail 'Responsive matrix requires five screenshots.'
    }

    $requiredModes = @('default', 'protanopia', 'deuteranopia', 'tritanopia')
    foreach ($mode in $requiredModes) {
        $property = $inventory.color_vision_screenshots.PSObject.Properties[$mode]
        if ($null -eq $property) {
            Add-Issue `
                -Code 'PUI_PILOT_COLOR_MODE_MISSING' `
                -Path 'assets/pilot/inventory.json' `
                -Detail "Missing color mode: $mode."
            continue
        }
        $path = Register-Png -ResourcePath ([string]$property.Value)
        Test-Png -Path $path -ExpectedWidth 1280 -ExpectedHeight 720
    }

    foreach ($resourcePath in @($inventory.selected_sources)) {
        $path = Register-Png -ResourcePath ([string]$resourcePath) -Delivery $false
        Test-Png -Path $path
    }
    $actualSourcePngs = @(
        Get-ChildItem -LiteralPath (Join-Path $pilotPath 'source') -File -Filter *.png |
            ForEach-Object { $_.FullName }
    )
    foreach ($path in $actualSourcePngs) {
        if (-not $allExpectedPngPaths.Contains($path)) {
            Add-Issue `
                -Code 'PUI_PILOT_UNUSED_SOURCE' `
                -Path (Get-RepoRelativePath -AbsolutePath $path) `
                -Detail 'Discarded or unselected large source must not remain in the project.'
        }
    }

    $palettePath = Resolve-ResourcePath -ResourcePath ([string]$inventory.palette)
    if (-not (Test-Path -LiteralPath $palettePath -PathType Leaf)) {
        Add-Issue `
            -Code 'PUI_PILOT_PALETTE_MISSING' `
            -Path (Get-RepoRelativePath -AbsolutePath $palettePath) `
            -Detail 'Palette file is missing.'
    }
    else {
        try {
            $palette = Get-Content -LiteralPath $palettePath -Raw -Encoding UTF8 |
                ConvertFrom-Json
            if (@($palette.tokens.PSObject.Properties).Count -lt 8) {
                Add-Issue `
                    -Code 'PUI_PILOT_PALETTE_INVALID' `
                    -Path (Get-RepoRelativePath -AbsolutePath $palettePath) `
                    -Detail 'Palette requires at least eight named tokens.'
            }
        }
        catch {
            Add-Issue `
                -Code 'PUI_PILOT_PALETTE_INVALID' `
                -Path (Get-RepoRelativePath -AbsolutePath $palettePath) `
                -Detail $_.Exception.Message
        }
    }

    $provenancePath = Resolve-ResourcePath -ResourcePath ([string]$inventory.provenance)
    if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) {
        Add-Issue `
            -Code 'PUI_PILOT_PROVENANCE_MISSING' `
            -Path (Get-RepoRelativePath -AbsolutePath $provenancePath) `
            -Detail 'Provenance file is missing.'
    }
    else {
        $provenance = Get-Content -LiteralPath $provenancePath -Raw -Encoding UTF8
        foreach ($token in @(
            'built-in `image_gen`',
            'not exposed by the built-in tool',
            'call_pxuhVAmJNhtRY37cmNbqgNdI',
            'call_woJkh5Lv5QTiw63HrJl8HM8w',
            'call_NgWDANU9suQwTy9fMTv9p334',
            'remove_chroma_key.py',
            'render-presentation-pilot.ps1'
        )) {
            if (-not $provenance.Contains($token)) {
                Add-Issue `
                    -Code 'PUI_PILOT_PROVENANCE_INCOMPLETE' `
                    -Path (Get-RepoRelativePath -AbsolutePath $provenancePath) `
                    -Detail "Missing provenance token: $token"
            }
        }
    }

    $processingPath = Resolve-ResourcePath -ResourcePath ([string]$inventory.processing_script)
    if (-not (Test-Path -LiteralPath $processingPath -PathType Leaf)) {
        Add-Issue `
            -Code 'PUI_PILOT_PROCESSING_SCRIPT_MISSING' `
            -Path (Get-RepoRelativePath -AbsolutePath $processingPath) `
            -Detail 'Deterministic processing script is missing.'
    }
}

if (Test-Path -LiteralPath $pilotPath -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $pilotPath -Recurse -File -Filter *.png) {
        if (-not $allExpectedPngPaths.Contains($file.FullName)) {
            Add-Issue `
                -Code 'PUI_PILOT_UNINVENTORIED_ASSET' `
                -Path (Get-RepoRelativePath -AbsolutePath $file.FullName) `
                -Detail 'Every pilot PNG must be selected or identified as a selected source.'
        }
    }
}

$hashOwners = @{}
$assetHashes = New-Object System.Collections.Generic.List[object]
foreach ($path in @($deliveryPaths) | Sort-Object) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        continue
    }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $relative = Get-RepoRelativePath -AbsolutePath $path
    $assetHashes.Add([ordered]@{ path = $relative; sha256 = $hash })
    if ($hashOwners.ContainsKey($hash)) {
        Add-Issue `
            -Code 'PUI_PILOT_DUPLICATE_ASSET' `
            -Path $relative `
            -Detail "Duplicates $($hashOwners[$hash])."
    }
    else {
        $hashOwners[$hash] = $relative
    }
}

$payload = [ordered]@{
    schema_version = 1
    scope = 'presentation-ui-t13-pilot'
    passed = ($issues.Count -eq 0)
    user_approval_required = $true
    user_approved = ($null -ne $inventory -and [bool]$inventory.user_approved)
    issue_count = $issues.Count
    warning_count = $warnings.Count
    issues = $issues.ToArray()
    warnings = $warnings.ToArray()
    asset_hashes = $assetHashes.ToArray()
}

$resolvedOutput = [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
$outputParent = Split-Path -Parent $resolvedOutput
New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
[IO.File]::WriteAllText(
    $resolvedOutput,
    ($payload | ConvertTo-Json -Depth 12),
    (New-Object Text.UTF8Encoding($false))
)
$roundTrip = Get-Content -LiteralPath $resolvedOutput -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ([bool]$roundTrip.passed -ne [bool]$payload.passed) {
    throw 'Pilot validation artifact read-back failed.'
}

if ($payload.passed) {
    if ($payload.user_approved) {
        Write-Host 'Presentation pilot asset validation passed; user approval is recorded.'
    }
    else {
        Write-Host 'Presentation pilot asset validation passed; user approval remains required.'
    }
    exit 0
}
Write-Host "Presentation pilot asset validation failed with $($issues.Count) issue(s)."
exit 2
