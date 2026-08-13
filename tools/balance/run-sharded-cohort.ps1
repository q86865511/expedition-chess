[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [ValidateRange(1, 10000)]
    [int]$SeedCount = 1000,
    [ValidateRange(1, 16)]
    [int]$ShardCount = 8,
    [ValidateSet('Screening', 'Final')]
    [string]$GateMode = 'Screening',
    [ValidateRange(600, 604800)]
    [int]$TimeoutSeconds = 43200
)

$ErrorActionPreference = 'Stop'
# Per-act elimination gate (DC-REQ-008) is shared with the golden test so the
# aggregate cannot drift from domain/balance/balance_bot_report.gd.
. (Join-Path $PSScriptRoot 'act-elimination-gate.ps1')
# Section 6.3b convergence signals (win-rate band, win HP spread) are shared with
# the same golden as domain/balance/balance_bot_report.gd. WARN only: they are
# published as report fields and never appended to $gateReasons.
. (Join-Path $PSScriptRoot 'convergence-warnings.ps1')
if ($ShardCount -gt $SeedCount) { throw 'ShardCount cannot exceed SeedCount.' }
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$artifactRoot = Join-Path $repoRoot 'artifacts\test'
$godot = (Resolve-Path -LiteralPath $GodotPath).Path
$lock = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'toolchain.lock.json') | ConvertFrom-Json
$actualHash = (Get-FileHash -LiteralPath $godot -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -cne [string]$lock.godot.sha256) {
    throw 'Godot executable does not match toolchain.lock.json.'
}

function Get-GitSourcePaths {
    $gitCommand = Get-Command git -ErrorAction Stop
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $gitCommand.Source
    $escapedRoot = $repoRoot.Replace('"', '\"')
    $startInfo.Arguments = "-C `"$escapedRoot`" ls-files -z --cached --others --exclude-standard"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Unable to start git while building source freeze.' }
    $buffer = New-Object IO.MemoryStream
    try {
        $process.StandardOutput.BaseStream.CopyTo($buffer)
        $standardError = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "git ls-files failed while building source freeze: $standardError"
        }
        $decoded = [Text.Encoding]::UTF8.GetString($buffer.ToArray())
        return @($decoded.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))
    }
    finally {
        $buffer.Dispose()
        $process.Dispose()
    }
}

function Get-SourceFreeze {
    $relativePaths = @(Get-GitSourcePaths | Where-Object {
        $_ -and -not $_.StartsWith('artifacts/') -and -not $_.StartsWith('.pipeline/')
    } | Sort-Object -CaseSensitive)
    $entries = New-Object System.Collections.Generic.List[object]
    $fragments = New-Object Text.StringBuilder
    foreach ($relativePath in $relativePaths) {
        $absolutePath = Join-Path $repoRoot $relativePath
        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            throw "Source freeze path missing: $relativePath"
        }
        $sha = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $normalized = $relativePath.Replace('\', '/')
        $entries.Add([ordered]@{ path = $normalized; sha256 = $sha })
        [void]$fragments.Append($normalized)
        [void]$fragments.Append([char]0)
        [void]$fragments.Append($sha)
        [void]$fragments.Append([char]0)
    }
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = (($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($fragments.ToString())) |
            ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally { $hasher.Dispose() }
    $head = (git -C $repoRoot rev-parse HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'git rev-parse failed while building source freeze.' }
    return [pscustomobject]@{
        digest = $digest
        git_head = $head
        file_count = $entries.Count
        files = $entries.ToArray()
    }
}

function Write-Utf8Json {
    param([Parameter(Mandatory = $true)]$Value, [Parameter(Mandatory = $true)][string]$Path)
    $json = $Value | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-EconomyPayloadDigest {
    param([Parameter(Mandatory = $true)][string[]]$Parts)
    $stream = New-Object IO.MemoryStream
    try {
        foreach ($part in $Parts) {
            $bytes = [Text.Encoding]::UTF8.GetBytes($part)
            $prefix = [byte[]]@(
                (($bytes.Length -shr 24) -band 255),
                (($bytes.Length -shr 16) -band 255),
                (($bytes.Length -shr 8) -band 255),
                ($bytes.Length -band 255)
            )
            $stream.Write($prefix, 0, $prefix.Length)
            $stream.Write($bytes, 0, $bytes.Length)
        }
        $hasher = [Security.Cryptography.SHA256]::Create()
        try {
            return (($hasher.ComputeHash($stream.ToArray()) |
                ForEach-Object { $_.ToString('x2') }) -join '')
        }
        finally { $hasher.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-RateBps {
    param([long]$Numerator, [long]$Denominator)
    if ($Denominator -le 0) { return 0 }
    return [int][math]::Floor(($Numerator * 10000.0) / $Denominator)
}

function Add-GateReason {
    param([string]$Reason)
    if (-not $gateReasons.Contains($Reason)) { $gateReasons.Add($Reason) }
}

$preflightArtifact = Join-Path $artifactRoot 'balance-candidate-preflight.json'
$preflightLog = Join-Path $artifactRoot 'balance-candidate-preflight.godot.log'
if (Test-Path -LiteralPath $preflightArtifact) { Remove-Item -LiteralPath $preflightArtifact -Force }
if (Test-Path -LiteralPath $preflightLog) { Remove-Item -LiteralPath $preflightLog -Force }
$preflightArguments = @(
    '--headless', '--path', $repoRoot, '--log-file', $preflightLog,
    '--script', 'res://tests/runners/balance_playtest_runner.gd', '--',
    '--seed-count', '1', '--archive-only',
    '--artifact-path', 'res://artifacts/test/balance-candidate-preflight.json'
)
$preflight = Start-Process -FilePath $godot -ArgumentList $preflightArguments -PassThru -WindowStyle Hidden
if (-not $preflight.WaitForExit(300000)) {
    & taskkill.exe /PID $preflight.Id /T /F | Out-Null
    throw 'Balance candidate archive preflight timed out.'
}
if ($preflight.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $preflightArtifact -PathType Leaf)) {
    throw "Balance candidate archive preflight failed with exit code $($preflight.ExitCode)."
}

$startedAt = [DateTime]::UtcNow
$freezeBefore = Get-SourceFreeze
$modeName = $GateMode.ToLowerInvariant()
$freezeName = "balance-$modeName-source-freeze.json"
$freezePath = Join-Path $artifactRoot $freezeName
Write-Utf8Json ([ordered]@{
    artifact_schema_version = 1
    runner = 'balance-source-freeze'
    source_freeze_digest = $freezeBefore.digest
    git_head = $freezeBefore.git_head
    file_count = $freezeBefore.file_count
    files = $freezeBefore.files
}) $freezePath

$processes = New-Object System.Collections.Generic.List[object]
for ($shardIndex = 0; $shardIndex -lt $ShardCount; $shardIndex++) {
    $localSeedCount = [int][math]::Floor(($SeedCount - 1 - $shardIndex) / $ShardCount) + 1
    $artifactName = 'balance-{0}-shard-{1:D2}.json' -f $modeName, $shardIndex
    $artifactPath = Join-Path $artifactRoot $artifactName
    $logPath = Join-Path $artifactRoot ('balance-{0}-shard-{1:D2}.godot.log' -f $modeName, $shardIndex)
    if (Test-Path -LiteralPath $artifactPath) { Remove-Item -LiteralPath $artifactPath -Force }
    if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
    $arguments = @(
        '--headless', '--path', $repoRoot, '--log-file', $logPath,
        '--script', 'res://tests/runners/balance_playtest_runner.gd', '--',
        '--seed-start', [string]$shardIndex,
        '--seed-count', [string]$localSeedCount,
        '--seed-stride', [string]$ShardCount,
        '--artifact-path', "res://artifacts/test/$artifactName",
        '--shard'
    )
    $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -WindowStyle Hidden
    $processes.Add([pscustomobject]@{
        Index = $shardIndex
        SeedStart = $shardIndex
        SeedStride = $ShardCount
        SeedCount = $localSeedCount
        Process = $process
        Artifact = $artifactPath
        Log = $logPath
    })
}

foreach ($entry in $processes) {
    if (-not $entry.Process.WaitForExit($TimeoutSeconds * 1000)) {
        & taskkill.exe /PID $entry.Process.Id /T /F | Out-Null
        throw "Balance $modeName shard $($entry.Index) timed out."
    }
    if ($entry.Process.ExitCode -ne 0) {
        throw "Balance $modeName shard $($entry.Index) failed with exit code $($entry.Process.ExitCode)."
    }
    if (-not (Test-Path -LiteralPath $entry.Artifact -PathType Leaf)) {
        throw "Balance $modeName shard $($entry.Index) did not publish an artifact."
    }
}

$freezeAfter = Get-SourceFreeze
if ($freezeAfter.digest -cne $freezeBefore.digest) {
    throw "Source changed during balance $modeName; all shard evidence is rejected."
}

$reports = New-Object System.Collections.Generic.List[object]
$shardMapping = New-Object System.Collections.Generic.List[object]
$caseProofs = New-Object System.Collections.Generic.List[object]
$sampledCases = New-Object System.Collections.Generic.List[object]
$driftCaseIds = New-Object System.Collections.Generic.List[string]
$primaryElapsedTotal = 0L
$primaryCaseCount = 0
$replayElapsedTotal = 0L
$replayCaseCount = 0
foreach ($entry in $processes) {
    $report = Get-Content -Raw -Encoding UTF8 -LiteralPath $entry.Artifact | ConvertFrom-Json
    $expectedLocalCases = $entry.SeedCount * 3
    if ([int]$report.strategy_seed_case_count -ne $expectedLocalCases -or
        @($report.case_proofs).Count -ne $expectedLocalCases) {
        throw "Balance $modeName shard $($entry.Index) case proof count mismatch."
    }
    if (@($report.failed_seeds).Count -gt 0) {
        throw "Balance $modeName shard $($entry.Index) contains operational failures."
    }
    $report | Add-Member -NotePropertyName source_freeze_digest -NotePropertyValue $freezeBefore.digest -Force
    $report | Add-Member -NotePropertyName shard -NotePropertyValue ([ordered]@{
        shard_index = $entry.Index
        shard_count = $ShardCount
        seed_rule = "seed_index % $ShardCount == $($entry.Index)"
        seed_start = $entry.SeedStart
        seed_stride = $entry.SeedStride
        seed_count = $entry.SeedCount
    }) -Force
    Write-Utf8Json $report $entry.Artifact
    $reports.Add($report)
    foreach ($proof in @($report.case_proofs)) { $caseProofs.Add($proof) }
    foreach ($sample in @($report.replay_validation.sampled_cases)) { $sampledCases.Add($sample) }
    foreach ($drift in @($report.replay_validation.drift_case_ids)) { $driftCaseIds.Add([string]$drift) }
    $primaryElapsedTotal += [long]$report.execution_metrics.primary_elapsed_ms_total
    $primaryCaseCount += [int]$report.execution_metrics.primary_case_count
    $replayElapsedTotal += [long]$report.execution_metrics.replay_elapsed_ms_total
    $replayCaseCount += [int]$report.execution_metrics.replay_sample_count
    $shardMapping.Add([ordered]@{
        shard_index = $entry.Index
        seed_rule = "seed_index % $ShardCount == $($entry.Index)"
        seed_start = $entry.SeedStart
        seed_stride = $entry.SeedStride
        seed_count = $entry.SeedCount
        artifact = [IO.Path]::GetFileName($entry.Artifact)
        log = [IO.Path]::GetFileName($entry.Log)
        primary_case_count = [int]$report.execution_metrics.primary_case_count
        primary_mean_elapsed_ms = [double]$report.execution_metrics.primary_mean_elapsed_ms
        replay_sample_count = [int]$report.execution_metrics.replay_sample_count
        replay_mean_elapsed_ms = [double]$report.execution_metrics.replay_mean_elapsed_ms
    })
}

foreach ($field in @('candidate_id', 'content_version', 'manifest_digest', 'tune_digest')) {
    if (@($reports | ForEach-Object { [string]$_.$field } | Select-Object -Unique).Count -ne 1) {
        throw "Balance $modeName shard candidate mismatch: $field"
    }
}

$expectedCaseCount = $SeedCount * 3
$gateReasons = New-Object System.Collections.Generic.List[string]
if ($caseProofs.Count -ne $expectedCaseCount -or $primaryCaseCount -ne $expectedCaseCount) {
    Add-GateReason 'BALANCE_COHORT_CASE_COUNT_MISMATCH'
}

$strategyRows = [ordered]@{}
foreach ($strategyId in @('tempo', 'economy', 'synergy')) {
    $strategyRows[$strategyId] = [ordered]@{
        strategy_id = $strategyId
        cases = 0
        terminal = 0
        wins = 0
        act1_reached = 0
        act2_reached = 0
        act3_reached = 0
        buy_unit_count = 0
        buy_xp_count = 0
        reroll_count = 0
        sell_unit_count = 0
        boss_retry_count = 0
    }
}
$buildRows = @{}
$contentCounts = @{}
$routeCounts = @{}
$failedSeeds = New-Object System.Collections.Generic.List[object]
$uniqueGold = New-Object System.Collections.Generic.HashSet[int]
$endingGoldTotal = 0L
$endingHpTotal = 0L
$battleWins = 0L
$battleLosses = 0L
$fallbackBuildCount = 0
$selectedIdCount = 0L
$opaqueSelectedIdCount = 0L
foreach ($proof in $caseProofs) {
    $strategyId = [string]$proof.strategy_id
    if (-not $strategyRows.Contains($strategyId)) {
        Add-GateReason 'BALANCE_STRATEGY_INVALID'
        continue
    }
    $row = $strategyRows[$strategyId]
    $row.cases += 1
    if ([bool]$proof.terminal) { $row.terminal += 1 }
    if ([bool]$proof.won) { $row.wins += 1 }
    $actReached = [int]$proof.act_reached
    if ($actReached -ge 1) { $row.act1_reached += 1 }
    if ($actReached -ge 2) { $row.act2_reached += 1 }
    if ($actReached -ge 3) { $row.act3_reached += 1 }
    $row.buy_unit_count += [int]$proof.buy_unit_count
    $row.buy_xp_count += [int]$proof.buy_xp_count
    $row.reroll_count += [int]$proof.reroll_count
    $row.sell_unit_count += [int]$proof.sell_unit_count
    $row.boss_retry_count += [int]$proof.boss_retry_count
    $buildId = [string]$proof.build_id
    if (-not $buildRows.ContainsKey($buildId)) {
        $buildRows[$buildId] = [ordered]@{ build_id = $buildId; selected = 0; wins = 0 }
    }
    $buildRows[$buildId].selected += 1
    if ([bool]$proof.won) { $buildRows[$buildId].wins += 1 }
    if ($buildId -in @('build.unresolved', 'build.empty', 'build.none') -or $buildId.StartsWith('build.unit.')) {
        $fallbackBuildCount += 1
    }
    foreach ($selectedId in @($proof.selected_ids)) {
        $key = [string]$selectedId
        $contentCounts[$key] = [int]$contentCounts[$key] + 1
        $selectedIdCount += 1
        if ($key.StartsWith('reservation_owner_') -or $key.StartsWith('offer_') -or
            $key.StartsWith('choice_') -or $key.StartsWith('reward.kind.')) {
            $opaqueSelectedIdCount += 1
        }
    }
    foreach ($routeId in @($proof.route_ids)) {
        $key = [string]$routeId
        $routeCounts[$key] = [int]$routeCounts[$key] + 1
    }
    $endingGold = [int]$proof.ending_gold
    $endingHp = [int]$proof.ending_hp
    [void]$uniqueGold.Add($endingGold)
    $endingGoldTotal += $endingGold
    $endingHpTotal += $endingHp
    $battleWins += [int]$proof.battle_wins
    $battleLosses += [int]$proof.battle_losses
    $codes = @($proof.failure_codes)
    if ($codes.Count -gt 0) {
        $failedSeeds.Add([ordered]@{
            strategy_id = $strategyId
            seed_index = [int]$proof.seed_index
            failure_codes = @($codes | ForEach-Object { [string]$_ })
            replay_digest = [string]$proof.replay_digest
        })
    }
    if (-not [bool]$proof.terminal -or [string]$proof.final_phase -cne 'RESULTS') {
        Add-GateReason 'BALANCE_TERMINAL_PROOF_INVALID'
    }
    if (@($proof.route_ids).Count -ne [int]$proof.completed_node_count) {
        Add-GateReason 'BALANCE_ROUTE_PROOF_MISMATCH'
    }
    if ([int]$proof.settlement_receipt_count -ne
        ([int]$proof.battle_wins + [int]$proof.battle_losses)) {
        Add-GateReason 'BALANCE_SETTLEMENT_RECEIPT_MISMATCH'
    }
    if (@($proof.settlement_receipt_digests | Select-Object -Unique).Count -ne
        @($proof.settlement_receipt_digests).Count) {
        Add-GateReason 'BALANCE_SETTLEMENT_RECEIPT_DUPLICATE'
    }
    if (@($proof.reward_receipt_digests | Select-Object -Unique).Count -ne
        @($proof.reward_receipt_digests).Count) {
        Add-GateReason 'BALANCE_DUPLICATE_REWARD'
    }
    if ($endingGold -lt 0 -or $endingHp -lt 0) { Add-GateReason 'BALANCE_NEGATIVE_RESOURCE' }
}

$seedGroups = @($caseProofs | Group-Object { [int]$_.seed_index })
if ($seedGroups.Count -ne $SeedCount) { Add-GateReason 'BALANCE_COHORT_SEED_COUNT_MISMATCH' }
foreach ($group in $seedGroups) {
    $strategies = @($group.Group | ForEach-Object { [string]$_.strategy_id } | Sort-Object -Unique)
    $runIds = @($group.Group | ForEach-Object { [string]$_.run_id } | Sort-Object -Unique)
    $worlds = @($group.Group | ForEach-Object { [string]$_.world_digest } | Sort-Object -Unique)
    if ($group.Count -ne 3 -or ($strategies -join ',') -cne 'economy,synergy,tempo' -or
        $runIds.Count -ne 1 -or $worlds.Count -ne 1) {
        Add-GateReason 'BALANCE_COHORT_WORLD_MISMATCH'
        break
    }
}

foreach ($strategyId in @('tempo', 'economy', 'synergy')) {
    $row = $strategyRows[$strategyId]
    if ($row.terminal -lt 500) { Add-GateReason "BALANCE_$($strategyId.ToUpperInvariant())_TERMINAL_SAMPLE_LOW" }
    if ($row.wins -lt 50) { Add-GateReason "BALANCE_$($strategyId.ToUpperInvariant())_WIN_SAMPLE_LOW" }
}
if ($failedSeeds.Count -gt 0) { Add-GateReason 'BALANCE_FAILED_SEEDS_PRESENT' }
if ($driftCaseIds.Count -gt 0) { Add-GateReason 'BALANCE_REPLAY_DRIFT' }

$expectedSampleIds = New-Object System.Collections.Generic.List[string]
for ($seedIndex = 0; $seedIndex -lt $SeedCount; $seedIndex += 20) {
    foreach ($strategyId in @('tempo', 'economy', 'synergy')) {
        $expectedSampleIds.Add("$strategyId`:$seedIndex")
    }
}
$actualSampleIds = @($sampledCases | ForEach-Object {
    '{0}:{1}' -f [string]$_.strategy_id, [int]$_.seed_index
} | Sort-Object)
$expectedSorted = @($expectedSampleIds | Sort-Object)
if (($actualSampleIds -join '|') -cne ($expectedSorted -join '|') -or
    $replayCaseCount -ne $expectedSorted.Count) {
    Add-GateReason 'BALANCE_REPLAY_SAMPLE_SET_MISMATCH'
}

$buildOutput = New-Object System.Collections.Generic.List[object]
$selectionRates = New-Object System.Collections.Generic.List[int]
$winRates = New-Object System.Collections.Generic.List[int]
foreach ($buildId in @($buildRows.Keys | Sort-Object)) {
    $build = $buildRows[$buildId]
    $selectionRate = Get-RateBps $build.selected $expectedCaseCount
    $winRate = Get-RateBps $build.wins $build.selected
    if ($buildId -cne 'build.none') {
        $selectionRates.Add($selectionRate)
        $winRates.Add($winRate)
    }
    $buildOutput.Add([ordered]@{
        build_id = $buildId
        selected = $build.selected
        wins = $build.wins
        selection_rate_bps = $selectionRate
        win_rate_bps = $winRate
    })
}
$orderedSelection = @($selectionRates | Sort-Object -Descending)
if ($orderedSelection.Count -ge 2 -and $orderedSelection[0] - $orderedSelection[1] -ge 2000) {
    Add-GateReason 'BALANCE_BUILD_SELECTION_DOMINANCE'
}
$orderedWins = @($winRates | Sort-Object -Descending)
if ($orderedWins.Count -ge 2 -and $orderedWins[0] - $orderedWins[1] -ge 2000) {
    Add-GateReason 'BALANCE_BUILD_WIN_RATE_DOMINANCE'
}
$allPerfect = $true
foreach ($strategyId in @('tempo', 'economy', 'synergy')) {
    $row = $strategyRows[$strategyId]
    if ($row.cases -eq 0 -or $row.wins -ne $row.cases) { $allPerfect = $false }
}
if ($allPerfect) { Add-GateReason 'BALANCE_ALL_STRATEGIES_PERFECT_WIN_RATE' }
if ($fallbackBuildCount -eq $expectedCaseCount) { Add-GateReason 'BALANCE_BUILD_ID_ALL_FALLBACK' }
if ($uniqueGold.Count -eq 1) { Add-GateReason 'BALANCE_ENDING_GOLD_CONSTANT' }
$actCurve = Get-BalanceActCurve -CaseProofs $caseProofs.ToArray() -SeedCount $SeedCount
foreach ($reason in @(Get-BalanceActEliminationGateReasons -ActCurve $actCurve)) {
    Add-GateReason $reason
}
# Deliberately not fed into Add-GateReason: section 6.3b's win-rate band and win-HP
# spread are convergence signals for the TUNE iteration loop, not pass/fail gates.
$convergence = Get-BalanceConvergenceReport -CaseProofs $caseProofs.ToArray()

$strategyRank = @{ tempo = 0; economy = 1; synergy = 2 }
$canonicalCases = @($caseProofs | Sort-Object `
    @{ Expression = { $strategyRank[[string]$_.strategy_id] } },
    @{ Expression = { [int]$_.seed_index } })
$replayParts = New-Object System.Collections.Generic.List[string]
$replayParts.Add('BALANCE-BOT-REPORT-V1')
foreach ($proof in $canonicalCases) {
    $replayParts.Add(('{0}:{1}:{2}' -f
        [string]$proof.strategy_id, [int]$proof.seed_index, [string]$proof.replay_digest))
}
$canonicalReplayDigest = Get-EconomyPayloadDigest $replayParts.ToArray()
$orderedProofs = @($caseProofs | Sort-Object `
    @{ Expression = { [int]$_.seed_index } },
    @{ Expression = { $strategyRank[[string]$_.strategy_id] } })
$uniqueGoldValues = @($uniqueGold | Sort-Object)
$finishedAt = [DateTime]::UtcNow
$payload = [ordered]@{
    artifact_schema_version = 1
    runner = 'balance-playtest-sharded'
    gate_mode = $modeName
    candidate_id = [string]$reports[0].candidate_id
    content_version = [string]$reports[0].content_version
    manifest_digest = [string]$reports[0].manifest_digest
    tune_digest = [string]$reports[0].tune_digest
    source_freeze_digest = $freezeBefore.digest
    source_freeze_artifact = $freezeName
    git_head = $freezeBefore.git_head
    cohort_seed_count = $SeedCount
    strategy_seed_case_count = $caseProofs.Count
    strategies = @($strategyRows.Values)
    builds = $buildOutput.ToArray()
    content_selection_counts = $contentCounts
    stable_id_observability = [ordered]@{
        selected_id_count = $selectedIdCount
        opaque_selected_id_count = $opaqueSelectedIdCount
    }
    node_route_counts = $routeCounts
    resource_curve = [ordered]@{
        mean_terminal_gold = if ($caseProofs.Count -gt 0) { [double]$endingGoldTotal / $caseProofs.Count } else { 0.0 }
        mean_terminal_hp = if ($caseProofs.Count -gt 0) { [double]$endingHpTotal / $caseProofs.Count } else { 0.0 }
    }
    battle_outcomes = [ordered]@{ wins = $battleWins; losses = $battleLosses }
    act_curve = $actCurve
    convergence = $convergence
    case_proofs = $orderedProofs
    failed_seeds = $failedSeeds.ToArray()
    regression_proof = [ordered]@{
        all_strategies_perfect_win_rate = $allPerfect
        fallback_build_count = $fallbackBuildCount
        unique_ending_gold = $uniqueGoldValues
    }
    canonical_replay_digest = $canonicalReplayDigest
    replay_validation = [ordered]@{
        mode = 'deterministic_sample'
        sample_rate_bps = 500
        selection_rule = 'seed_index % 20 == 0'
        sampled_case_count = $actualSampleIds.Count
        sampled_cases = @($sampledCases | Sort-Object `
            @{ Expression = { [int]$_.seed_index } },
            @{ Expression = { $strategyRank[[string]$_.strategy_id] } })
        drift_case_ids = @($driftCaseIds | Sort-Object)
    }
    execution_metrics = [ordered]@{
        shard_count = $ShardCount
        primary_case_count = $primaryCaseCount
        primary_elapsed_ms_total = $primaryElapsedTotal
        primary_mean_elapsed_ms = if ($primaryCaseCount -gt 0) { [double]$primaryElapsedTotal / $primaryCaseCount } else { 0.0 }
        replay_sample_count = $replayCaseCount
        replay_elapsed_ms_total = $replayElapsedTotal
        replay_mean_elapsed_ms = if ($replayCaseCount -gt 0) { [double]$replayElapsedTotal / $replayCaseCount } else { 0.0 }
        effective_mean_elapsed_ms = if ($primaryCaseCount -gt 0) { [double]($primaryElapsedTotal + $replayElapsedTotal) / $primaryCaseCount } else { 0.0 }
        wall_elapsed_seconds = ($finishedAt - $startedAt).TotalSeconds
    }
    shard_mapping = $shardMapping.ToArray()
    gate = if ($gateReasons.Count -eq 0) { 'PASS' } else { 'FAIL' }
    gate_reasons = $gateReasons.ToArray()
    ac_032 = 'PENDING_EXTERNAL'
    started_at_utc = $startedAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
    finished_at_utc = $finishedAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

$targetName = if ($GateMode -eq 'Final') { 'balance-playtest.json' } else { 'balance-playtest-screening.json' }
$target = Join-Path $artifactRoot $targetName
$temporary = $target + '.tmp'
Write-Utf8Json $payload $temporary
$readBack = Get-Content -Raw -Encoding UTF8 -LiteralPath $temporary | ConvertFrom-Json
if ([int]$readBack.strategy_seed_case_count -ne $expectedCaseCount -or
    [string]$readBack.source_freeze_digest -cne $freezeBefore.digest -or
    [string]$readBack.ac_032 -cne 'PENDING_EXTERNAL') {
    throw "Merged balance $modeName artifact read-back failed."
}
Move-Item -LiteralPath $temporary -Destination $target -Force
Write-Output $target
if ([string]$payload.gate -ne 'PASS') { exit 2 }
