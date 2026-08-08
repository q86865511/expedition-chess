param(
    [ValidateSet('Import', 'Localization', 'Gut', 'AllTests', 'Evidence', 'Activation', 'Run')]
    [string]$Mode = 'Run',
    [string]$GodotPath = '',
    [ValidateSet(100, 125, 150)]
    [int]$UiScale = 100,
    [ValidateSet('zh_TW', 'en')]
    [string]$Locale = 'zh_TW',
    [ValidateSet('1280x720', '1920x1080')]
    [string]$WindowSize = '1280x720',
    [string]$TestPath = '',
    [switch]$FreshProfile,
    [ValidateSet('Present', 'Absent')]
    [string]$ExpectedDiagnostic = 'Absent'
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$profileRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'artifacts\ui-art-refresh\phase-b1r\profile')
)
$allowedRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'artifacts\ui-art-refresh\phase-b1r')
)
if (-not $profileRoot.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Isolated profile escaped the allowed root: $profileRoot"
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = $env:GODOT_BIN
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    throw 'Set GODOT_BIN or pass -GodotPath before launching isolated UI verification.'
}
$GodotPath = [System.IO.Path]::GetFullPath($GodotPath)
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable was not found: $GodotPath"
}

if ($FreshProfile -and (Test-Path -LiteralPath $profileRoot)) {
    $resolvedProfile = [System.IO.Path]::GetFullPath(
        (Resolve-Path -LiteralPath $profileRoot).Path
    )
    if (-not $resolvedProfile.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear profile outside the allowed root: $resolvedProfile"
    }
    Remove-Item -LiteralPath $resolvedProfile -Recurse -Force
}

$appData = Join-Path $profileRoot 'AppData\Roaming'
$localAppData = Join-Path $profileRoot 'AppData\Local'
New-Item -ItemType Directory -Force -Path $appData, $localAppData | Out-Null
$env:APPDATA = $appData
$env:LOCALAPPDATA = $localAppData
$env:EXPEDITION_EVIDENCE_UI_SCALE = [string]$UiScale
$env:EXPEDITION_EVIDENCE_LOCALE = $Locale
$env:GODOT_BIN = $GodotPath

Write-Host "Isolated APPDATA: $appData"
Write-Host "Isolated LOCALAPPDATA: $localAppData"

switch ($Mode) {
    'Import' {
        & $GodotPath --headless --path $repoRoot --editor --quit
        exit $LASTEXITCODE
    }
    'Localization' {
        & $GodotPath --headless --path $repoRoot --script 'res://tools/content-production/export-localization-catalog.gd'
        exit $LASTEXITCODE
    }
    'AllTests' {
        & (Join-Path $repoRoot 'tools\run-tests.ps1') -Suite All
        exit $LASTEXITCODE
    }
    'Gut' {
        & (Join-Path $repoRoot 'tools\run-tests.ps1') -Suite Gut -TestPath $TestPath -GodotPath $GodotPath -TimeoutSeconds 300
        exit $LASTEXITCODE
    }
    'Evidence' {
        & $GodotPath --path $repoRoot --script 'res://tests/runners/presentation_phase_b1_evidence_runner.gd' -- '--output-dir=res://specs/ui-art-refresh/evidence/phase-b1r'
        exit $LASTEXITCODE
    }
    'Activation' {
        $expected = $ExpectedDiagnostic.ToLowerInvariant()
        & $GodotPath --path $repoRoot --script 'res://tests/runners/presentation_phase_b1r_activation_runner.gd' -- '--output-dir=res://specs/ui-art-refresh/evidence/phase-b1r' "--expected-diagnostic=$expected"
        exit $LASTEXITCODE
    }
    'Run' {
        & $GodotPath --path $repoRoot --resolution $WindowSize
        exit $LASTEXITCODE
    }
}
