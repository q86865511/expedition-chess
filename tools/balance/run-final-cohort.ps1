[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [ValidateRange(10000, 10000)]
    [int]$SeedCount = 10000,
    [ValidateRange(600, 7200)]
    [int]$TimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$artifactRoot = Join-Path $repoRoot 'artifacts\test'
$godot = (Resolve-Path -LiteralPath $GodotPath).Path
$lock = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'toolchain.lock.json') | ConvertFrom-Json
$actualHash = (Get-FileHash -LiteralPath $godot -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -cne [string]$lock.godot.sha256) {
    throw 'Godot executable does not match toolchain.lock.json.'
}

$shards = @(
    [pscustomobject]@{ Index = 0; Start = 0; Count = 3334 },
    [pscustomobject]@{ Index = 1; Start = 3334; Count = 3333 },
    [pscustomobject]@{ Index = 2; Start = 6667; Count = 3333 }
)
$processes = New-Object System.Collections.Generic.List[object]
foreach ($shard in $shards) {
    $artifactName = "balance-playtest-shard-$($shard.Index).json"
    $artifactPath = Join-Path $artifactRoot $artifactName
    $logPath = Join-Path $artifactRoot "balance-playtest-shard-$($shard.Index).godot.log"
    if (Test-Path -LiteralPath $artifactPath) { Remove-Item -LiteralPath $artifactPath -Force }
    $arguments = @(
        '--headless', '--path', $repoRoot, '--log-file', $logPath,
        '--script', 'res://tests/runners/balance_playtest_runner.gd', '--',
        '--seed-start', [string]$shard.Start,
        '--seed-count', [string]$shard.Count,
        '--artifact-path', "res://artifacts/test/$artifactName",
        '--shard'
    )
    $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -WindowStyle Hidden
    $processes.Add([pscustomobject]@{ Shard = $shard; Process = $process; Artifact = $artifactPath; Log = $logPath })
}

foreach ($entry in $processes) {
    if (-not $entry.Process.WaitForExit($TimeoutSeconds * 1000)) {
        & taskkill.exe /PID $entry.Process.Id /T /F | Out-Null
        throw "Balance shard $($entry.Shard.Index) timed out."
    }
    if ($entry.Process.ExitCode -ne 0) {
        throw "Balance shard $($entry.Shard.Index) failed with exit code $($entry.Process.ExitCode)."
    }
    if (-not (Test-Path -LiteralPath $entry.Artifact -PathType Leaf)) {
        throw "Balance shard $($entry.Shard.Index) did not publish an artifact."
    }
}

$reports = @($processes | ForEach-Object {
    Get-Content -Raw -Encoding UTF8 -LiteralPath $_.Artifact | ConvertFrom-Json
})
$candidateFields = @('candidate_id', 'content_version', 'manifest_digest', 'tune_digest')
foreach ($field in $candidateFields) {
    if (@($reports | ForEach-Object { [string]$_.$field } | Select-Object -Unique).Count -ne 1) {
        throw "Balance shard candidate mismatch: $field"
    }
}

$strategyRows = @{}
$buildRows = @{}
$contentCounts = @{}
$routeCounts = @{}
$failedSeeds = New-Object System.Collections.Generic.List[object]
$battleWins = 0
$battleLosses = 0
$goldWeighted = 0.0
$hpWeighted = 0.0
$caseCount = 0
$gateReasons = New-Object System.Collections.Generic.List[string]
foreach ($report in $reports) {
    if ([string]$report.gate -ne 'PASS') { $gateReasons.Add('BALANCE_SHARD_GATE_FAILED') }
    $caseCount += [int]$report.strategy_seed_case_count
    foreach ($row in @($report.strategies)) {
        $id = [string]$row.strategy_id
        if (-not $strategyRows.ContainsKey($id)) {
            $strategyRows[$id] = [ordered]@{ strategy_id = $id; cases = 0; terminal = 0; wins = 0; act1_reached = 0; act2_reached = 0; act3_reached = 0 }
        }
        foreach ($field in @('cases','terminal','wins','act1_reached','act2_reached','act3_reached')) {
            $strategyRows[$id][$field] += [int]$row.$field
        }
    }
    foreach ($row in @($report.builds)) {
        $id = [string]$row.build_id
        if (-not $buildRows.ContainsKey($id)) { $buildRows[$id] = [ordered]@{ build_id = $id; selected = 0; wins = 0 } }
        $buildRows[$id].selected += [int]$row.selected
        $buildRows[$id].wins += [int]$row.wins
    }
    foreach ($property in $report.content_selection_counts.PSObject.Properties) {
        $contentCounts[$property.Name] = [int]($contentCounts[$property.Name] + [int]$property.Value)
    }
    foreach ($property in $report.node_route_counts.PSObject.Properties) {
        $routeCounts[$property.Name] = [int]($routeCounts[$property.Name] + [int]$property.Value)
    }
    foreach ($failed in @($report.failed_seeds)) { $failedSeeds.Add($failed) }
    $battleWins += [int]$report.battle_outcomes.wins
    $battleLosses += [int]$report.battle_outcomes.losses
    $shardCases = [int]$report.strategy_seed_case_count
    $goldWeighted += [double]$report.resource_curve.mean_terminal_gold * $shardCases
    $hpWeighted += [double]$report.resource_curve.mean_terminal_hp * $shardCases
}

if ($caseCount -ne 30000) { $gateReasons.Add('BALANCE_FINAL_CASE_COUNT_MISMATCH') }
foreach ($id in @('tempo','economy','synergy')) {
    if (-not $strategyRows.ContainsKey($id) -or $strategyRows[$id].terminal -lt 500) { $gateReasons.Add("BALANCE_$($id.ToUpperInvariant())_TERMINAL_SAMPLE_LOW") }
    if (-not $strategyRows.ContainsKey($id) -or $strategyRows[$id].wins -lt 50) { $gateReasons.Add("BALANCE_$($id.ToUpperInvariant())_WIN_SAMPLE_LOW") }
}
if ($failedSeeds.Count -gt 0) { $gateReasons.Add('BALANCE_FAILED_SEEDS_PRESENT') }

$buildOutput = New-Object System.Collections.Generic.List[object]
$selectionRates = New-Object System.Collections.Generic.List[int]
$winRates = New-Object System.Collections.Generic.List[int]
foreach ($id in @($buildRows.Keys | Sort-Object)) {
    $row = $buildRows[$id]
    $selectionRate = if ($caseCount -gt 0) { [math]::Floor($row.selected * 10000 / $caseCount) } else { 0 }
    $winRate = if ($row.selected -gt 0) { [math]::Floor($row.wins * 10000 / $row.selected) } else { 0 }
    $selectionRates.Add([int]$selectionRate)
    $winRates.Add([int]$winRate)
    $buildOutput.Add([ordered]@{ build_id = $id; selected = $row.selected; wins = $row.wins; selection_rate_bps = $selectionRate; win_rate_bps = $winRate })
}
$orderedSelection = @($selectionRates | Sort-Object -Descending)
if ($orderedSelection.Count -ge 2 -and $orderedSelection[0] - $orderedSelection[1] -ge 2000) {
    $gateReasons.Add('BALANCE_BUILD_SELECTION_DOMINANCE')
}
$orderedWins = @($winRates | Sort-Object -Descending)
if ($orderedWins.Count -ge 2 -and $orderedWins[0] - $orderedWins[1] -ge 2000) {
    $gateReasons.Add('BALANCE_BUILD_WIN_RATE_DOMINANCE')
}

$sha = [Security.Cryptography.SHA256]::Create()
try {
    $replayText = 'BALANCE-BOT-REPORT-V1-SHARDED|' + ((@($reports.canonical_replay_digest) | Sort-Object) -join '|')
    $replayDigest = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($replayText)) | ForEach-Object { $_.ToString('x2') }) -join '')
}
finally { $sha.Dispose() }

$payload = [ordered]@{
    artifact_schema_version = 1
    runner = 'balance-playtest'
    candidate_id = [string]$reports[0].candidate_id
    content_version = [string]$reports[0].content_version
    manifest_digest = [string]$reports[0].manifest_digest
    tune_digest = [string]$reports[0].tune_digest
    cohort_seed_count = $SeedCount
    strategy_seed_case_count = $caseCount
    strategies = @($strategyRows.Keys | Sort-Object | ForEach-Object { $strategyRows[$_] })
    builds = $buildOutput.ToArray()
    content_selection_counts = $contentCounts
    node_route_counts = $routeCounts
    resource_curve = [ordered]@{
        mean_terminal_gold = if ($caseCount -gt 0) { $goldWeighted / $caseCount } else { 0 }
        mean_terminal_hp = if ($caseCount -gt 0) { $hpWeighted / $caseCount } else { 0 }
    }
    battle_outcomes = [ordered]@{ wins = $battleWins; losses = $battleLosses }
    failed_seeds = $failedSeeds.ToArray()
    canonical_replay_digest = $replayDigest
    gate = if ($gateReasons.Count -eq 0) { 'PASS' } else { 'FAIL' }
    gate_reasons = @($gateReasons | Select-Object -Unique)
    ac_032 = 'PENDING_EXTERNAL'
    started_at_utc = @($reports.started_at_utc | Sort-Object)[0]
    finished_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    execution = [ordered]@{ mode = 'three_parallel_seed_shards'; shard_count = 3; shared_seed_range = '0..9999' }
}
$target = Join-Path $artifactRoot 'balance-playtest.json'
$temporary = $target + '.tmp'
[IO.File]::WriteAllText($temporary, ($payload | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
$readBack = Get-Content -Raw -Encoding UTF8 -LiteralPath $temporary | ConvertFrom-Json
if ([int]$readBack.strategy_seed_case_count -ne 30000 -or [string]$readBack.ac_032 -ne 'PENDING_EXTERNAL') {
    throw 'Merged balance artifact read-back failed.'
}
Move-Item -LiteralPath $temporary -Destination $target -Force
if ([string]$payload.gate -ne 'PASS') { throw "Final balance gate failed: $($payload.gate_reasons -join ', ')" }
Write-Output $target
