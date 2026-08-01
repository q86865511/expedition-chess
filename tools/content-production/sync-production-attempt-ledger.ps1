param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$GeneratedImagesRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repoPath = [System.IO.Path]::GetFullPath($Repo)
$ledgerPath = Join-Path $repoPath 'assets\production\production-asset-attempts.json'
$attemptRoot = Join-Path $repoPath 'assets\production\attempts'
$existing = Get-Content -Raw -Encoding UTF8 -LiteralPath $ledgerPath | ConvertFrom-Json
$existingById = @{}
foreach ($entry in $existing.attempts) { $existingById[$entry.attempt_id] = $entry }

$briefByUnit = @{}
$briefFiles = @(
    (Join-Path $repoPath '.pipeline\content-production\briefs\player-batch-001.json'),
    (Join-Path $repoPath '.pipeline\content-production\briefs\remaining-units.json')
)
foreach ($briefFile in $briefFiles) {
    $document = Get-Content -Raw -Encoding UTF8 -LiteralPath $briefFile | ConvertFrom-Json
    foreach ($unit in $document.units) { $briefByUnit[$unit.unit_id] = $unit.brief }
}

$gateRows = @'
slice_monster_00|attempt-001|644|
slice_monster_01|attempt-001|770|
slice_monster_02|attempt-001|828|
slice_monster_03|attempt-001|275|
slice_monster_04|attempt-001|991|
slice_monster_05|attempt-001|20|move3
slice_monster_05|attempt-002|1692|
slice_monster_06|attempt-001|4017|
slice_monster_07|attempt-001|403|
slice_monster_08|attempt-001|1347|
slice_monster_09|attempt-001|1017|
slice_monster_10|attempt-001|0|hit1
slice_monster_10|attempt-002|0|move3,attack4,hit1,death4
slice_monster_10|attempt-003|1088|
slice_monster_11|attempt-001|1489|
slice_player_00|attempt-001|104|cast2,cast3,cast4,hit1
slice_player_00|attempt-002|1885|
slice_player_01|attempt-001|648|
slice_player_02|attempt-001|1196|
slice_player_03|attempt-001|33|attack2
slice_player_03|attempt-002|589|
slice_player_04|attempt-001|351|
slice_player_05|attempt-001|722|
slice_player_06|attempt-001|694|
slice_player_07|attempt-001|0|move1,move2,attack1,attack2
slice_player_07|attempt-002|657|
slice_player_08|attempt-001|939|
slice_player_09|attempt-001|333|
slice_player_10|attempt-001|0|death2,death3,death4
slice_player_10|attempt-002|0|move3
slice_player_10|attempt-003|120|
slice_player_11|attempt-001|36|hit1
slice_player_11|attempt-002|787|
slice_player_12|attempt-001|11|attack4,death2,death3
slice_player_12|attempt-002|469|
slice_player_13|attempt-001|111|attack4
slice_player_13|attempt-002|338|
slice_player_14|attempt-001|1192|
slice_player_15|attempt-001|1322|
slice_player_16|attempt-001|976|
slice_player_17|attempt-001|793|
slice_player_18|attempt-001|2625|
slice_player_19|attempt-001|0|attack1
slice_player_19|attempt-002|869|
slice_player_20|attempt-001|191|
slice_player_21|attempt-001|1708|
slice_player_22|attempt-001|457|
slice_player_23|attempt-001|254|
slice_player_24|attempt-001|1070|
slice_player_25|attempt-001|79|attack4
slice_player_25|attempt-002|319|
slice_player_26|attempt-001|0|attack1,cast3,cast4,hit1
slice_player_26|attempt-002|602|
slice_player_27|attempt-001|120|
slice_player_28|attempt-001|817|
slice_player_29|attempt-001|181|
slice_player_30|attempt-001|446|
slice_player_31|attempt-001|1901|
'@
$gateByAttempt = @{}
foreach ($line in ($gateRows -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line.Split('|')
    $gateByAttempt[($parts[0] + '/' + $parts[1])] = [pscustomobject]@{
        minimum = [int]$parts[2]
        failures = if ($parts.Length -ge 4 -and $parts[3]) { @($parts[3].Split(',')) } else { @() }
    }
}

$outputByHash = @{}
Get-ChildItem -LiteralPath $GeneratedImagesRoot -Filter 'exec-*.png' | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $outputByHash[$hash] = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
}

$all = New-Object System.Collections.Generic.List[object]
$unitDirectories = Get-ChildItem -LiteralPath $attemptRoot -Directory | Sort-Object Name
foreach ($unitDirectory in $unitDirectories) {
    $attemptDirectories = Get-ChildItem -LiteralPath $unitDirectory.FullName -Directory -Filter 'attempt-*' | Sort-Object Name
    $latestAttempt = $attemptDirectories[-1].Name
    foreach ($attemptDirectory in $attemptDirectories) {
        $attemptNumber = [int]($attemptDirectory.Name -replace '^attempt-', '')
        $attemptId = '{0}-attempt-{1:D3}' -f $unitDirectory.Name, $attemptNumber
        if ($existingById.ContainsKey($attemptId)) {
            $all.Add($existingById[$attemptId])
            continue
        }
        $unitId = 'unit.' + $unitDirectory.Name
        $rawPath = Join-Path $attemptDirectory.FullName 'raw.png'
        $rawHash = (Get-FileHash -LiteralPath $rawPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $image = [System.Drawing.Image]::FromFile($rawPath)
        try { $width = $image.Width; $height = $image.Height }
        finally { $image.Dispose() }
        $gate = $gateByAttempt[$unitDirectory.Name + '/' + $attemptDirectory.Name]
        if ($null -eq $gate) { throw "Missing gate result for $attemptId" }
        $isLatest = $attemptDirectory.Name -eq $latestAttempt
        $status = if ($isLatest) { 'generated' } else { 'rejected' }
        $review = if ($isLatest) {
            [ordered]@{ reviewer = $null; decision = 'pending'; reviewed_at = $null; review_record_sha256 = $null; reason = $null }
        } else {
            [ordered]@{ reviewer = 'codex:mechanical-gate'; decision = 'rejected'; reviewed_at = '2026-08-01T16:30:00+08:00'; review_record_sha256 = $null; reason = 'Missing required direction/action subject; rejected before human originality review.' }
        }
        $brief = [string]$briefByUnit[$unitId]
        $prompt = "Independent built-in ImageGen attempt for $unitId. Original-only brief: $brief Exact 5x5 sheet; 20 ordered action cells; each cell four complete N/E/S/W subjects; row 5 portrait/material/glyph/turnaround/palette; flat #ff00ff; no copied identity."
        $relativeRaw = $rawPath.Substring($repoPath.Length + 1).Replace('\', '/')
        $all.Add([ordered]@{
            attempt_id = $attemptId
            unit_id = $unitId
            status = $status
            generation = [ordered]@{
                mode = 'built-in-imagegen'
                independent_call = $true
                prompt = $prompt
                prompt_capture = 'normalized-from-tool-invocation-template'
                imagegen_output_id = [string]$outputByHash[$rawHash]
                call_id = $null
                call_id_exposure = 'not exposed by built-in ImageGen'
                model_native_seed = 'not_exposed_by_builtin_image_gen'
            }
            raw_source = [ordered]@{ path = $relativeRaw; sha256 = $rawHash; width = $width; height = $height }
            mechanical_gate = [ordered]@{
                status = if ($gate.failures.Count -eq 0) { 'passed' } else { 'failed' }
                min_direction_quadrant_pixels = $gate.minimum
                failures = @($gate.failures)
            }
            review = $review
        })
    }
}

$attemptArray = @($all | ForEach-Object { $_ })
$document = [ordered]@{
    schema_version = 1
    slice = 'content-production'
    updated_at = '2026-08-01T16:30:00+08:00'
    processing_contract = [ordered]@{
        raw_background = '#ff00ff'
        normalized_source_size = @(1280, 1280)
        grid = @(5, 5)
        action_cells = 20
        directions_per_action_cell = 4
        direction_order = @('north', 'east', 'south', 'west')
        model_native_seed_exposure = 'not_exposed_by_builtin_image_gen'
    }
    attempts = $attemptArray
}
$json = $document | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($ledgerPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
Write-Output "Synchronized $($all.Count) production asset attempts."
