param(
    [ValidateSet('Import', 'Gut', 'AllTests', 'Evidence', 'Run')]
    [string]$Mode = 'Run',
    [string]$GodotPath = '',
    [ValidateSet(100, 125, 150)]
    [int]$UiScale = 100,
    [ValidateSet('zh_TW', 'en')]
    [string]$Locale = 'zh_TW',
    [ValidateSet('1280x720', '1920x1080')]
    [string]$WindowSize = '1280x720',
    [string]$TestPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$profileRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'artifacts\ui-art-refresh\phase-b1\profile')
)
$allowedRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'artifacts\ui-art-refresh\phase-b1')
)
if (-not $profileRoot.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Isolated profile escaped the allowed root: $profileRoot"
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $candidate = Get-ChildItem -Path 'E:\OneDrive' -Filter 'Godot_v4.7-stable_win64.exe' -Recurse -File |
        Select-Object -First 1
    if ($null -eq $candidate) {
        throw 'Godot 4.7 executable was not found.'
    }
    $GodotPath = $candidate.FullName
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
    'AllTests' {
        & (Join-Path $repoRoot 'tools\run-tests.ps1') -Suite All
        exit $LASTEXITCODE
    }
    'Gut' {
        & (Join-Path $repoRoot 'tools\run-tests.ps1') -Suite Gut -TestPath $TestPath -GodotPath $GodotPath -TimeoutSeconds 300
        exit $LASTEXITCODE
    }
    'Evidence' {
        & $GodotPath --path $repoRoot --script 'res://tests/runners/presentation_phase_b1_evidence_runner.gd' -- '--output-dir=res://specs/ui-art-refresh/evidence/phase-b1'
        exit $LASTEXITCODE
    }
    'Run' {
        & $GodotPath --path $repoRoot --resolution $WindowSize
        exit $LASTEXITCODE
    }
}
