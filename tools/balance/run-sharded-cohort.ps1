[CmdletBinding()]
param(
    # -MergeOnly 只重算合併，不起任何 Godot 行程，因此那條路徑不需要 GodotPath。
    [string]$GodotPath = '',
    [ValidateRange(1, 10000)]
    [int]$SeedCount = 1000,
    [ValidateRange(1, 16)]
    [int]$ShardCount = 8,
    [ValidateSet('Screening', 'Final')]
    [string]$GateMode = 'Screening',
    [ValidateRange(600, 604800)]
    [int]$TimeoutSeconds = 43200,
    # 續跑：從 <artifact-root>/screening-checkpoint/ 的逐案 checkpoint 接著跑。
    # 重開機後續跑＝同一條指令，不依賴任何駐留行程。
    [switch]$Resume,
    # 只做合併（checkpoint 已齊時重算 gate／統計，或給 golden 測試驅動合併路徑）。
    [switch]$MergeOnly,
    # 只允許搭配 -MergeOnly：把 checkpoint 與合併產物導向測試用目錄，
    # 避免 golden 覆寫正式的 artifacts/test 證據。
    [string]$ArtifactRoot = ''
)

$ErrorActionPreference = 'Stop'
# Per-act elimination gate (DC-REQ-008) is shared with the golden test so the
# aggregate cannot drift from domain/balance/balance_bot_report.gd.
. (Join-Path $PSScriptRoot 'act-elimination-gate.ps1')
# Section 6.3b convergence signals (win-rate band, win HP spread) are shared with
# the same golden as domain/balance/balance_bot_report.gd. WARN only: they are
# published as report fields and never appended to $gateReasons.
. (Join-Path $PSScriptRoot 'convergence-warnings.ps1')
# 逐案 checkpoint（暫停／續跑／重開機後續跑）的共用路徑與檔案語意。
. (Join-Path $PSScriptRoot 'screening-checkpoint.ps1')
if ($ShardCount -gt $SeedCount) { throw 'ShardCount cannot exceed SeedCount.' }
if ($Resume -and $MergeOnly) { throw 'Use either -Resume or -MergeOnly, not both.' }
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
    $artifactRoot = Join-Path $repoRoot 'artifacts\test'
}
else {
    if (-not $MergeOnly) {
        # 分片以 res://artifacts/test/... 寫檔，改根目錄只在不起分片時才成立。
        throw '-ArtifactRoot is only supported together with -MergeOnly.'
    }
    if (-not (Test-Path -LiteralPath $ArtifactRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $ArtifactRoot -Force | Out-Null
    }
    $artifactRoot = (Resolve-Path -LiteralPath $ArtifactRoot).Path
}
$godot = ''
if (-not $MergeOnly) {
    if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw 'GodotPath is required unless -MergeOnly is set.' }
    $godot = (Resolve-Path -LiteralPath $GodotPath).Path
    $lock = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'toolchain.lock.json') | ConvertFrom-Json
    $actualHash = (Get-FileHash -LiteralPath $godot -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -cne [string]$lock.godot.sha256) {
        throw 'Godot executable does not match toolchain.lock.json.'
    }
}

# Source freeze 的實作在 screening-checkpoint.ps1（續跑要用同一套算法比對，
# 測試也要能自行算出同一個 digest）；這裡只是綁上本輪 repo root 的薄包裝。
function Get-SourceFreeze {
    return (Get-ScreeningSourceFreeze -RepoRoot $repoRoot)
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

# 協調端因錯誤中止時（分片被殺、逾時、證據被拒）把狀態記成 failed，網頁與
# screening-ctl status 才不會一直顯示 running。exit 2（gate FAIL）與 exit 4（暫停）
# 不是終止錯誤，不會經過這裡。
trap {
    if (Test-Path -LiteralPath (Get-ScreeningMetaPath $artifactRoot) -PathType Leaf) {
        Write-ScreeningState -ArtifactRoot $artifactRoot -Status 'failed' -Detail ([string]$_.Exception.Message)
    }
    break
}

$modeName = $GateMode.ToLowerInvariant()
$checkpointRoot = Get-ScreeningCheckpointRoot $artifactRoot
$metaPath = Get-ScreeningMetaPath $artifactRoot
$pauseFlagPath = Get-ScreeningPauseFlagPath $artifactRoot
$freezeName = "balance-$modeName-source-freeze.json"
$freezePath = Join-Path $artifactRoot $freezeName

function Invoke-CandidatePreflight {
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
    return (Get-Content -Raw -Encoding UTF8 -LiteralPath $preflightArtifact | ConvertFrom-Json)
}

$meta = Read-ScreeningJsonFile $metaPath
if ($MergeOnly) {
    # 合併路徑不重跑 candidate preflight：身分以開跑時凍結的 meta 為準，
    # 並在下面用 source freeze 與各分片尾記錄交叉驗證。
    if ($null -eq $meta) { throw 'BALANCE_RESUME_META_MISSING: no checkpoint meta to merge.' }
    $SeedCount = [int]$meta.seed_count
    $ShardCount = [int]$meta.shard_count
    $GateMode = [string]$meta.gate_mode
    $modeName = $GateMode.ToLowerInvariant()
    $freezeBefore = Get-SourceFreeze
    if ([string]$meta.source_freeze_digest -cne $freezeBefore.digest) {
        throw "BALANCE_RESUME_SOURCE_DRIFT: source tree changed since the cohort started; checkpoint evidence is rejected."
    }
    $candidate = $meta
    $processes = New-Object System.Collections.Generic.List[object]
    for ($shardIndex = 0; $shardIndex -lt $ShardCount; $shardIndex++) {
        $processes.Add([pscustomobject]@{
            Index = $shardIndex
            SeedStart = $shardIndex
            SeedStride = $ShardCount
            SeedCount = (Get-ScreeningShardSeedCount -SeedCount $SeedCount -ShardCount $ShardCount -ShardIndex $shardIndex)
            Log = ('balance-{0}-shard-{1:D2}.godot.log' -f $modeName, $shardIndex)
        })
    }
}
else {
    $candidate = Invoke-CandidatePreflight
    $freezeBefore = Get-SourceFreeze
    if ($Resume) {
        if ($null -eq $meta) {
            throw "BALANCE_RESUME_META_MISSING: $metaPath is absent; start a fresh cohort instead."
        }
        $rejection = Test-ScreeningResumeCompatibility -Meta $meta `
            -SourceFreezeDigest $freezeBefore.digest `
            -CandidateId ([string]$candidate.candidate_id) `
            -TuneDigest ([string]$candidate.tune_digest) `
            -SeedCount $SeedCount -ShardCount $ShardCount -GateMode $GateMode
        if (-not [string]::IsNullOrEmpty($rejection)) {
            throw "${rejection}: resume refused; the checkpoint was produced by a different source tree, candidate, or cohort shape."
        }
        # 續跑先清掉暫停旗標，否則分片一開工就會立刻再暫停。
        if (Test-Path -LiteralPath $pauseFlagPath) { Remove-Item -LiteralPath $pauseFlagPath -Force }
        $meta | Add-Member -NotePropertyName resume_count -NotePropertyValue ([int]$meta.resume_count + 1) -Force
        Write-ScreeningJsonFile $meta $metaPath
    }
    else {
        if (Test-Path -LiteralPath $checkpointRoot) { Remove-Item -LiteralPath $checkpointRoot -Recurse -Force }
        New-Item -ItemType Directory -Path $checkpointRoot -Force | Out-Null
        Write-Utf8Json ([ordered]@{
            artifact_schema_version = 1
            runner = 'balance-source-freeze'
            source_freeze_digest = $freezeBefore.digest
            git_head = $freezeBefore.git_head
            file_count = $freezeBefore.file_count
            files = $freezeBefore.files
        }) $freezePath
        $meta = [ordered]@{
            artifact_schema_version = 1
            runner = 'balance-screening-checkpoint-meta'
            gate_mode = $GateMode
            candidate_id = [string]$candidate.candidate_id
            content_version = [string]$candidate.content_version
            manifest_digest = [string]$candidate.manifest_digest
            tune_digest = [string]$candidate.tune_digest
            source_freeze_digest = $freezeBefore.digest
            source_freeze_artifact = $freezeName
            git_head = $freezeBefore.git_head
            seed_count = $SeedCount
            shard_count = $ShardCount
            resume_count = 0
            started_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        Write-ScreeningJsonFile $meta $metaPath
        $meta = Read-ScreeningJsonFile $metaPath
    }
    $startDetail = if ($Resume) { 'resumed' } else { 'started' }
    Write-ScreeningState -ArtifactRoot $artifactRoot -Status 'running' `
        -Detail $startDetail -CoordinatorPid $PID

    $processes = New-Object System.Collections.Generic.List[object]
    for ($shardIndex = 0; $shardIndex -lt $ShardCount; $shardIndex++) {
        $localSeedCount = Get-ScreeningShardSeedCount -SeedCount $SeedCount -ShardCount $ShardCount -ShardIndex $shardIndex
        $expectedCases = Get-ScreeningShardCaseCount -SeedCount $SeedCount -ShardCount $ShardCount -ShardIndex $shardIndex
        $artifactName = 'balance-{0}-shard-{1:D2}.json' -f $modeName, $shardIndex
        $artifactPath = Join-Path $artifactRoot $artifactName
        $logName = 'balance-{0}-shard-{1:D2}.godot.log' -f $modeName, $shardIndex
        $logPath = Join-Path $artifactRoot $logName
        $checkpointName = 'shard-{0:D2}.jsonl' -f $shardIndex
        $skipName = 'shard-{0:D2}.skip' -f $shardIndex
        $skipPath = Get-ScreeningShardPath -ArtifactRoot $artifactRoot -ShardIndex $shardIndex -Kind skip
        $statusPath = Get-ScreeningShardPath -ArtifactRoot $artifactRoot -ShardIndex $shardIndex -Kind status
        $doneCases = 0
        if ($Resume) {
            # 已提交的 case 變成跳過清單；壞掉的尾行（強殺時可能只寫一半）就地截斷後重跑。
            $shardCheckpoint = Read-ScreeningShardCases -ArtifactRoot $artifactRoot `
                -ShardIndex $shardIndex -ShardCount $ShardCount -RepairTrailingLine
            $skipKeys = @(Get-ScreeningSkipKeys -Records $shardCheckpoint.records)
            $doneCases = $skipKeys.Count
            Write-ScreeningSkipList -Path $skipPath -Keys $skipKeys
        }
        else {
            if (Test-Path -LiteralPath $artifactPath) { Remove-Item -LiteralPath $artifactPath -Force }
            if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
        }
        if ($Resume -and $doneCases -ge $expectedCases -and $expectedCases -gt 0) {
            # 這一片在中斷前就跑完了：不必再起一次 Godot，尾記錄已在 checkpoint 裡。
            if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) {
                throw "Balance $modeName shard $shardIndex is complete but has no status record."
            }
            $processes.Add([pscustomobject]@{
                Index = $shardIndex
                SeedStart = $shardIndex
                SeedStride = $ShardCount
                SeedCount = $localSeedCount
                Process = $null
                Log = $logName
            })
            continue
        }
        if ($Resume -and (Test-Path -LiteralPath $logPath -PathType Leaf)) {
            # 續跑會重寫 log；保留上一段的原始輸出當診斷證據。
            $archivedLog = Join-Path $artifactRoot (
                'balance-{0}-shard-{1:D2}.resume{2}.godot.log' -f $modeName, $shardIndex, ([int]$meta.resume_count)
            )
            Move-Item -LiteralPath $logPath -Destination $archivedLog -Force
        }
        $arguments = @(
            '--headless', '--path', $repoRoot, '--log-file', $logPath,
            '--script', 'res://tests/runners/balance_playtest_runner.gd', '--',
            '--seed-start', [string]$shardIndex,
            '--seed-count', [string]$localSeedCount,
            '--seed-stride', [string]$ShardCount,
            '--shard-index', [string]$shardIndex,
            '--artifact-path', "res://artifacts/test/$artifactName",
            '--checkpoint-path', "res://artifacts/test/$script:ScreeningCheckpointDirName/$checkpointName",
            '--pause-flag-path', "res://artifacts/test/$script:ScreeningCheckpointDirName/pause.flag",
            '--shard'
        )
        if ($Resume) {
            $arguments += @('--skip-list-path', "res://artifacts/test/$script:ScreeningCheckpointDirName/$skipName")
        }
        $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -WindowStyle Hidden
        $processes.Add([pscustomobject]@{
            Index = $shardIndex
            SeedStart = $shardIndex
            SeedStride = $ShardCount
            SeedCount = $localSeedCount
            Process = $process
            Log = $logName
        })
    }

    foreach ($entry in $processes) {
        if ($null -eq $entry.Process) { continue }
        if (-not $entry.Process.WaitForExit($TimeoutSeconds * 1000)) {
            & taskkill.exe /PID $entry.Process.Id /T /F | Out-Null
            throw "Balance $modeName shard $($entry.Index) timed out."
        }
        if ($entry.Process.ExitCode -ne 0) {
            throw "Balance $modeName shard $($entry.Index) failed with exit code $($entry.Process.ExitCode)."
        }
    }

    $freezeAfter = Get-SourceFreeze
    if ($freezeAfter.digest -cne $freezeBefore.digest) {
        throw "Source changed during balance $modeName; all shard evidence is rejected."
    }
}

# 合併端一律以逐案 checkpoint（screening-checkpoint/shard-NN.jsonl）為權威輸入，
# 全量重算統計；分片自己寫的 balance-<mode>-shard-NN.json 只留作單片診斷產物，
# 不再參與合併（續跑時那份 JSON 只含本次行程跑的 case，本來就不完整）。
$shardMapping = New-Object System.Collections.Generic.List[object]
$caseProofs = New-Object System.Collections.Generic.List[object]
$sampledCases = New-Object System.Collections.Generic.List[object]
$driftCaseIds = New-Object System.Collections.Generic.List[string]
$pausedShards = New-Object System.Collections.Generic.List[int]
$primaryElapsedTotal = 0L
$primaryCaseCount = 0
$replayElapsedTotal = 0L
$replayCaseCount = 0
foreach ($entry in $processes) {
    $statusPath = Get-ScreeningShardPath -ArtifactRoot $artifactRoot -ShardIndex $entry.Index -Kind status
    $shardStatus = Read-ScreeningJsonFile $statusPath
    if ($null -eq $shardStatus) {
        throw "Balance $modeName shard $($entry.Index) did not publish a checkpoint status record."
    }
    # 暫停的分片不得被讀成完成：記下來，等所有分片盤點完再一次回報。
    $shardPaused = [string]$shardStatus.status -cne 'completed'
    if ($shardPaused) { $pausedShards.Add([int]$entry.Index) }
    foreach ($field in @('candidate_id', 'content_version', 'manifest_digest', 'tune_digest')) {
        if ([string]$shardStatus.$field -cne [string]$candidate.$field) {
            throw "Balance $modeName shard $($entry.Index) candidate mismatch: $field"
        }
    }
    $shardCheckpoint = Read-ScreeningShardCases -ArtifactRoot $artifactRoot `
        -ShardIndex $entry.Index -ShardCount $ShardCount
    $records = @($shardCheckpoint.records)
    $expectedLocalCases = $entry.SeedCount * 3
    if (-not $shardPaused -and $records.Count -ne $expectedLocalCases) {
        throw "Balance $modeName shard $($entry.Index) case proof count mismatch."
    }
    $shardPrimaryElapsed = 0L
    $shardReplayElapsed = 0L
    $shardReplayCount = 0
    foreach ($record in $records) {
        $proof = $record.case
        if (@($proof.failure_codes).Count -gt 0) {
            throw "Balance $modeName shard $($entry.Index) contains operational failures."
        }
        $caseProofs.Add($proof)
        $shardPrimaryElapsed += [long]$record.primary_elapsed_ms
        if ([bool]$record.replay_sampled) {
            $shardReplayCount += 1
            $shardReplayElapsed += [long]$record.replay_elapsed_ms
            $sampledCases.Add([pscustomobject]@{
                strategy_id = [string]$record.strategy_id
                seed_index = [int]$record.seed_index
            })
            if (-not [bool]$record.replay_matched) {
                $driftCaseIds.Add((Get-ScreeningCaseKey -StrategyId ([string]$record.strategy_id) -SeedIndex ([int]$record.seed_index)))
            }
        }
    }
    $primaryElapsedTotal += $shardPrimaryElapsed
    $primaryCaseCount += $records.Count
    $replayElapsedTotal += $shardReplayElapsed
    $replayCaseCount += $shardReplayCount
    $shardMapping.Add([ordered]@{
        shard_index = $entry.Index
        seed_rule = "seed_index % $ShardCount == $($entry.Index)"
        seed_start = $entry.SeedStart
        seed_stride = $entry.SeedStride
        seed_count = $entry.SeedCount
        artifact = ('{0}/shard-{1:D2}.jsonl' -f $script:ScreeningCheckpointDirName, $entry.Index)
        log = [IO.Path]::GetFileName($entry.Log)
        primary_case_count = $records.Count
        primary_mean_elapsed_ms = $(if ($records.Count -gt 0) { [double]$shardPrimaryElapsed / $records.Count } else { 0.0 })
        replay_sample_count = $shardReplayCount
        replay_mean_elapsed_ms = $(if ($shardReplayCount -gt 0) { [double]$shardReplayElapsed / $shardReplayCount } else { 0.0 })
    })
}

if ($pausedShards.Count -gt 0) {
    $pausedList = ($pausedShards | Sort-Object) -join ','
    Write-ScreeningState -ArtifactRoot $artifactRoot -Status 'paused' -Detail "shards $pausedList"
    Write-Output "BALANCE_SCREENING_PAUSED shards=$pausedList completed_cases=$($caseProofs.Count) expected_cases=$($SeedCount * 3)"
    Write-Output 'Resume with: tools\balance\screening-ctl.ps1 resume'
    exit 4
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
# Cohort 的起跑時間以 checkpoint meta 為準：續跑之後 wall time 仍然是「整輪」的
# 牆鐘時間（含暫停），而不是最後一段行程的時間。
$startedAt = ([DateTime]::Parse([string]$meta.started_at_utc)).ToUniversalTime()
$payload = [ordered]@{
    artifact_schema_version = 1
    runner = 'balance-playtest-sharded'
    gate_mode = $modeName
    candidate_id = [string]$candidate.candidate_id
    content_version = [string]$candidate.content_version
    manifest_digest = [string]$candidate.manifest_digest
    tune_digest = [string]$candidate.tune_digest
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
        # 這一輪被續跑過幾次（0＝一次跑完）。統計欄位不受續跑影響，只有時間類欄位會。
        resume_count = [int]$meta.resume_count
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
Write-ScreeningState -ArtifactRoot $artifactRoot -Status 'completed' -Detail ([string]$payload.gate)
Write-Output $target
if ([string]$payload.gate -ne 'PASS') { exit 2 }
