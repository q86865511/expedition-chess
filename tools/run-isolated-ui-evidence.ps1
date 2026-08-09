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
    (Join-Path $repoRoot 'artifacts\ui-art-refresh\phase-b1r2\profile')
)
$allowedRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'artifacts\ui-art-refresh\phase-b1r2')
)
$evidenceRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'specs\ui-art-refresh\evidence\phase-b1r2')
)
$realAppDataRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $env:APPDATA 'Godot\app_userdata')
)

function Get-AppDataSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $directories = @()
    $files = @()
    if (Test-Path -LiteralPath $Root -PathType Container) {
        $directories = @(
            Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force |
                Sort-Object FullName |
                ForEach-Object {
                    [ordered]@{
                        path = $_.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
                        creation_time_utc = $_.CreationTimeUtc.ToString('o')
                        last_write_time_utc = $_.LastWriteTimeUtc.ToString('o')
                    }
                }
        )
        $files = @(
            Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
                Sort-Object FullName |
                ForEach-Object {
                    [ordered]@{
                        path = $_.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
                        length = $_.Length
                        creation_time_utc = $_.CreationTimeUtc.ToString('o')
                        last_write_time_utc = $_.LastWriteTimeUtc.ToString('o')
                        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    }
                }
        )
    }
    $inventoryJson = ConvertTo-Json -Compress -Depth 8 -InputObject ([ordered]@{
        directories = $directories
        files = $files
    })
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $inventoryHash = [System.BitConverter]::ToString(
            $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($inventoryJson))
        ).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
    $gameDirectoryName = -join [char[]](0x9060, 0x5f81, 0x68cb)
    $backupDirectoryName = $gameDirectoryName + '.bak'
    $totalBytes = 0L
    foreach ($fileEntry in $files) {
        $totalBytes += [long]$fileEntry['length']
    }
    return [ordered]@{
        schema_version = 2
        captured_at_utc = [DateTime]::UtcNow.ToString('o')
        root = '%APPDATA%/Godot/app_userdata'
        directory_count = $directories.Count
        file_count = $files.Count
        total_bytes = $totalBytes
        inventory_sha256 = $inventoryHash
        expected_paths = [ordered]@{
            game_directory = Test-Path -LiteralPath (Join-Path $Root $gameDirectoryName)
            nested_backup_directory = Test-Path -LiteralPath (Join-Path (Join-Path $Root $gameDirectoryName) $backupDirectoryName)
            nested_backup_settings = Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $Root $gameDirectoryName) $backupDirectoryName) 'settings-v1.json')
        }
        directories = $directories
        files = $files
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $json = ($Value | ConvertTo-Json -Depth 8).Replace("`r`n", "`n") + "`n"
    [System.IO.File]::WriteAllText(
        $Path,
        $json,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Invoke-GodotProcess {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$Visible
    )
    $startParameters = @{
        FilePath = $GodotPath
        ArgumentList = $Arguments
        Wait = $true
        PassThru = $true
    }
    if (-not $Visible) {
        $startParameters.WindowStyle = 'Hidden'
    }
    $process = Start-Process @startParameters
    return $process.ExitCode
}

New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
$beforePath = Join-Path $evidenceRoot 'real-appdata-before.json'
# B1R2 P8: capture the before-snapshot at invocation time. Reusing a
# committed baseline from disk falsely fails after any legitimate play
# session touches the real profile. (ASCII-only comment: this file has
# no BOM and PS 5.1 decodes non-BOM files as ANSI.)
$before = Get-AppDataSnapshot -Root $realAppDataRoot
Write-JsonFile -Path $beforePath -Value $before
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

$runExitCode = 0
switch ($Mode) {
    'Import' {
        $runExitCode = Invoke-GodotProcess -Arguments @('--headless', '--path', $repoRoot, '--editor', '--quit')
    }
    'Localization' {
        $runExitCode = Invoke-GodotProcess -Arguments @('--headless', '--path', $repoRoot, '--script', 'res://tools/content-production/export-localization-catalog.gd')
    }
    'AllTests' {
        & (Join-Path $repoRoot 'tools\run-tests.ps1') -Suite All -GodotPath $GodotPath
        $runExitCode = $LASTEXITCODE
    }
    'Gut' {
        & (Join-Path $repoRoot 'tools\run-tests.ps1') -Suite Gut -TestPath $TestPath -GodotPath $GodotPath -TimeoutSeconds 300
        $runExitCode = $LASTEXITCODE
    }
    'Evidence' {
        $runExitCode = Invoke-GodotProcess -Arguments @('--path', $repoRoot, '--script', 'res://tests/runners/presentation_phase_b1_evidence_runner.gd', '--', '--output-dir=res://specs/ui-art-refresh/evidence/phase-b1r2')
    }
    'Activation' {
        $expected = $ExpectedDiagnostic.ToLowerInvariant()
        $runExitCode = Invoke-GodotProcess -Arguments @('--path', $repoRoot, '--script', 'res://tests/runners/presentation_phase_b1r_activation_runner.gd', '--', '--output-dir=res://specs/ui-art-refresh/evidence/phase-b1r2', "--expected-diagnostic=$expected")
    }
    'Run' {
        $runExitCode = Invoke-GodotProcess -Arguments @('--path', $repoRoot, '--resolution', $WindowSize) -Visible
    }
}

$after = Get-AppDataSnapshot -Root $realAppDataRoot
$afterPath = Join-Path $evidenceRoot 'real-appdata-after.json'
Write-JsonFile -Path $afterPath -Value $after
$unchanged = [string]$before.inventory_sha256 -eq [string]$after.inventory_sha256
Write-JsonFile -Path (Join-Path $evidenceRoot 'real-appdata-integrity.json') -Value ([ordered]@{
    ok = $unchanged
    compared_scope = '%APPDATA%/Godot/app_userdata/**'
    includes_nested_backup = $true
    before_inventory_sha256 = [string]$before.inventory_sha256
    after_inventory_sha256 = [string]$after.inventory_sha256
    before_file_count = [int]$before.file_count
    after_file_count = [int]$after.file_count
    before_directory_count = [int]$before.directory_count
    after_directory_count = [int]$after.directory_count
})
if (-not $unchanged) {
    throw 'Real APPDATA changed during an isolated Godot launch; see phase-b1r2 snapshots.'
}
exit $runExitCode
