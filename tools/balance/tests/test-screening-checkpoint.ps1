[CmdletBinding()]
param()

# 分片 screening 的逐案 checkpoint（暫停／續跑／重開機後續跑）golden。
#
# (a) 相等性：同一批 case，一次跑完 vs 跑一半被強殺後續跑，最終合併統計必須逐欄位
#     相同（只有時間類欄位與 resume_count 允許不同——本測試同時斷言那些欄位確實
#     不同，否則「排除清單」會變成空話）。合併走的是正式的
#     tools\balance\run-sharded-cohort.ps1 -MergeOnly，不是測試自己抄一份聚合。
# (b) 具名拒絕：meta 與現況不符（source tree 被改、candidate 換掉、cohort 形狀不同）
#     時，續跑必須回具名拒絕碼，不得默默接著跑。
# (c) 暫停：分片尾記錄是 paused 時，合併端不得把它當完成。
# (d) 強殺造成的半行 JSONL 只允許「最後一行」被丟棄並就地截斷；中間壞行是真損毀。
#
# 用法: powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/balance/tests/test-screening-checkpoint.ps1
# 退出碼: 0 = 全部斷言通過, 1 = 有斷言失敗（紅）。

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\screening-checkpoint.ps1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    Write-Output "FAIL missing module: $modulePath"
    exit 1
}
. $modulePath

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$cohortScript = Join-Path $repoRoot 'tools\balance\run-sharded-cohort.ps1'
$failures = New-Object System.Collections.Generic.List[string]
$checked = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$What)
    $script:checked += 1
    if ([string]$Expected -cne [string]$Actual) {
        $script:failures.Add("$What`n  expected: $Expected`n  actual  : $Actual")
    }
}

function Assert-True {
    param([bool]$Condition, [string]$What)
    $script:checked += 1
    if (-not $Condition) { $script:failures.Add($What) }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$ExpectedCode, [string]$What)
    $script:checked += 1
    try {
        & $Action | Out-Null
        $script:failures.Add("$What`n  expected throw containing: $ExpectedCode`n  actual  : no throw")
    }
    catch {
        if ([string]$_.Exception.Message -notlike "*$ExpectedCode*") {
            $script:failures.Add("$What`n  expected throw containing: $ExpectedCode`n  actual  : $($_.Exception.Message)")
        }
    }
}

# ---------------------------------------------------------------- 合成 cohort --
# 8 seeds x 3 策略 x 2 分片；欄位形狀與 balance report 的 case_proofs[] 相同
# （合併端只吃這些欄位）。同一個 (strategy, seed) 永遠產生同一筆內容，續跑之後
# 重跑的 case 必須與一次跑完的那筆逐欄位相同——決定性由 seed 派生，與行程無關。
$strategyIds = @('tempo', 'economy', 'synergy')
function New-GoldenCaseRecord {
    param(
        [Parameter(Mandatory = $true)][string]$StrategyId,
        [Parameter(Mandatory = $true)][int]$SeedIndex,
        [Parameter(Mandatory = $true)][int]$ShardCount,
        [int]$ElapsedOffset = 0
    )
    $rank = [array]::IndexOf($strategyIds, $StrategyId)
    $won = (($SeedIndex + $rank) % 3) -ne 0
    $actReached = if ($won) { 3 } else { 1 + (($SeedIndex + $rank) % 2) }
    $battleWins = 4 + $rank + ($SeedIndex % 3)
    $battleLosses = if ($won) { 0 } else { 1 }
    $nodeCount = 3 + ($SeedIndex % 2)
    $routeIds = @(0..($nodeCount - 1) | ForEach-Object { "node.act1.$_" })
    $settlement = @(0..($battleWins + $battleLosses - 1) | ForEach-Object {
        "settlement_$StrategyId`_$SeedIndex`_$_"
    })
    $snapshots = New-Object System.Collections.Generic.List[object]
    for ($act = 1; $act -le $actReached; $act++) {
        $eliminated = (-not $won) -and ($act -eq $actReached)
        $snapshots.Add([ordered]@{
            act_index = $act
            gold = 10 + $SeedIndex + $act
            expedition_hp = 20 - $act
            roster_unit_count = 2
            board_unit_count = 2
            stable_unit_ids = @('unit.alpha', 'unit.beta')
            battle_wins = $act
            battle_losses = if ($eliminated) { 1 } else { 0 }
            elimination_node_id = if ($eliminated) { "node.act$act.boss" } else { '' }
        })
    }
    $case = [ordered]@{
        strategy_id = $StrategyId
        seed_index = $SeedIndex
        run_id = "run_$SeedIndex"
        world_digest = ('{0:x2}' -f ($SeedIndex % 256)) * 32
        terminal = $true
        won = $won
        act_reached = $actReached
        build_id = "build.trait.$StrategyId"
        selected_ids = @("unit.alpha", "offer_$SeedIndex")
        route_ids = $routeIds
        ending_gold = 3 + (($SeedIndex * 7 + $rank) % 11)
        ending_hp = 5 + (($SeedIndex + $rank) % 7)
        battle_wins = $battleWins
        battle_losses = $battleLosses
        buy_unit_count = 2 + $rank
        buy_xp_count = 1
        reroll_count = $SeedIndex % 2
        sell_unit_count = 0
        boss_retry_count = 0
        completed_node_count = $nodeCount
        reload_count = 0
        null_offer_rule_count = 0
        act_snapshots = $snapshots.ToArray()
        final_phase = 'RESULTS'
        settlement_receipt_count = $settlement.Count
        settlement_receipt_digests = $settlement
        reward_receipt_count = 1
        reward_receipt_digests = @("reward_$StrategyId`_$SeedIndex")
        failure_codes = @()
        replay_digest = "replay_$StrategyId`_$SeedIndex"
    }
    $replaySampled = ($SeedIndex % 20) -eq 0
    $record = [ordered]@{
        schema_version = 1
        shard_index = $SeedIndex % $ShardCount
        strategy_id = $StrategyId
        seed_index = $SeedIndex
        primary_elapsed_ms = 1000 + $SeedIndex * 10 + $rank + $ElapsedOffset
        replay_sampled = $replaySampled
        replay_elapsed_ms = if ($replaySampled) { 900 + $rank + $ElapsedOffset } else { 0 }
        replay_matched = $replaySampled
        case = $case
    }
    return ($record | ConvertTo-Json -Depth 20 -Compress)
}

# runner 的 case 順序：策略外圈、seed 內圈（同一片內）。
function Get-GoldenShardCaseKeys {
    param([int]$SeedCount, [int]$ShardCount, [int]$ShardIndex)
    $keys = New-Object System.Collections.Generic.List[object]
    foreach ($strategyId in $strategyIds) {
        for ($seedIndex = $ShardIndex; $seedIndex -lt $SeedCount; $seedIndex += $ShardCount) {
            $keys.Add([pscustomobject]@{ StrategyId = $strategyId; SeedIndex = $seedIndex })
        }
    }
    return $keys.ToArray()
}

function New-GoldenCheckpointRoot {
    param([string]$Name)
    $root = Join-Path ([IO.Path]::GetTempPath()) ("balance-screening-golden-$PID-$Name")
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    New-Item -ItemType Directory -Path (Get-ScreeningCheckpointRoot $root) -Force | Out-Null
    return $root
}

function Write-GoldenMeta {
    param([string]$ArtifactRoot, [string]$FreezeDigest, [int]$SeedCount, [int]$ShardCount)
    Write-ScreeningJsonFile ([ordered]@{
        artifact_schema_version = 1
        runner = 'balance-screening-checkpoint-meta'
        gate_mode = 'Screening'
        candidate_id = 'candidate_golden'
        content_version = '0.0.1-golden'
        manifest_digest = 'a' * 64
        tune_digest = 'b' * 64
        source_freeze_digest = $FreezeDigest
        source_freeze_artifact = 'balance-screening-source-freeze.json'
        git_head = '0' * 40
        seed_count = $SeedCount
        shard_count = $ShardCount
        resume_count = 0
        started_at_utc = '2026-01-01T00:00:00Z'
    }) (Get-ScreeningMetaPath $ArtifactRoot)
}

function Write-GoldenShardStatus {
    param([string]$ArtifactRoot, [int]$ShardIndex, [string]$Status, [int]$Completed, [int]$Skipped)
    Write-ScreeningJsonFile ([ordered]@{
        schema_version = 1
        status = $Status
        shard_index = $ShardIndex
        completed_cases = $Completed
        skipped_cases = $Skipped
        candidate_id = 'candidate_golden'
        content_version = '0.0.1-golden'
        manifest_digest = 'a' * 64
        tune_digest = 'b' * 64
    }) (Get-ScreeningShardPath -ArtifactRoot $ArtifactRoot -ShardIndex $ShardIndex -Kind status)
}

function Add-GoldenCase {
    param([string]$Path, [string]$Line)
    $existing = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding($false)))
    }
    else { '' }
    [IO.File]::WriteAllText($Path, $existing + $Line + "`n", (New-Object Text.UTF8Encoding($false)))
}

# 合併產物的正規化：把巢狀結構壓成逐行 "路徑=值"，陣列索引正規化成 []，
# 讓比對能指出「第一個不同的欄位路徑」而不是丟一坨 JSON。
$script:ExcludedPaths = @(
    'started_at_utc', 'finished_at_utc',
    'execution_metrics.primary_elapsed_ms_total', 'execution_metrics.primary_mean_elapsed_ms',
    'execution_metrics.replay_elapsed_ms_total', 'execution_metrics.replay_mean_elapsed_ms',
    'execution_metrics.effective_mean_elapsed_ms', 'execution_metrics.wall_elapsed_seconds',
    'execution_metrics.resume_count',
    'shard_mapping[].primary_mean_elapsed_ms', 'shard_mapping[].replay_mean_elapsed_ms'
)

function ConvertTo-FieldLines {
    param($Node, [string]$Path, [System.Collections.Generic.List[string]]$Lines, [switch]$OnlyExcluded)
    $isExcluded = $script:ExcludedPaths -contains $Path
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Node.PSObject.Properties) {
            $childPath = if ([string]::IsNullOrEmpty($Path)) { $property.Name } else { "$Path.$($property.Name)" }
            ConvertTo-FieldLines -Node $property.Value -Path $childPath -Lines $Lines -OnlyExcluded:$OnlyExcluded
        }
        return
    }
    if ($Node -is [object[]]) {
        $index = 0
        foreach ($item in $Node) {
            ConvertTo-FieldLines -Node $item -Path "$Path[]" -Lines $Lines -OnlyExcluded:$OnlyExcluded
            $index += 1
        }
        if ($Node.Count -eq 0 -and -not $OnlyExcluded) { $Lines.Add("$Path[]=<empty>") }
        return
    }
    if ($OnlyExcluded) {
        if ($isExcluded) { $Lines.Add("$Path=$Node") }
        return
    }
    if (-not $isExcluded) { $Lines.Add("$Path=$Node") }
}

function Get-FieldLines {
    param([string]$Path, [switch]$OnlyExcluded)
    $payload = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
    $lines = New-Object System.Collections.Generic.List[string]
    ConvertTo-FieldLines -Node $payload -Path '' -Lines $lines -OnlyExcluded:$OnlyExcluded
    return $lines
}

# ------------------------------------------------------------- 單元層 golden --
Assert-Equal 'tempo:0' (Get-ScreeningCaseKey -StrategyId 'tempo' -SeedIndex 0) 'case key 格式必須與 GDScript 端相同'
Assert-Equal 4 (Get-ScreeningShardSeedCount -SeedCount 8 -ShardCount 2 -ShardIndex 0) '分片 0 的 seed 數'
Assert-Equal 4 (Get-ScreeningShardSeedCount -SeedCount 8 -ShardCount 2 -ShardIndex 1) '分片 1 的 seed 數'
Assert-Equal 12 (Get-ScreeningShardCaseCount -SeedCount 8 -ShardCount 2 -ShardIndex 1) '分片 case 數＝seed 數 x 3 策略'
Assert-Equal 62 (Get-ScreeningShardSeedCount -SeedCount 1000 -ShardCount 16 -ShardIndex 15) '1000/16 的尾片 seed 數'
$shardSeedTotal = 0
foreach ($shardIndex in 0..15) {
    $shardSeedTotal += Get-ScreeningShardSeedCount -SeedCount 1000 -ShardCount 16 -ShardIndex $shardIndex
}
Assert-Equal 1000 $shardSeedTotal '16 片的 seed 數加總必須等於 cohort seed 數（切割不重不漏）'

$meta = [pscustomobject]@{
    source_freeze_digest = 'digest-a'; candidate_id = 'candidate-a'; tune_digest = 'tune-a'
    seed_count = 8; shard_count = 2; gate_mode = 'Screening'
}
Assert-Equal '' (Test-ScreeningResumeCompatibility -Meta $meta -SourceFreezeDigest 'digest-a' `
    -CandidateId 'candidate-a' -TuneDigest 'tune-a' -SeedCount 8 -ShardCount 2 -GateMode 'Screening') `
    '一致時必須允許續跑'
Assert-Equal 'BALANCE_RESUME_META_MISSING' (Test-ScreeningResumeCompatibility -Meta $null -SourceFreezeDigest 'digest-a' `
    -CandidateId 'candidate-a' -TuneDigest 'tune-a' -SeedCount 8 -ShardCount 2 -GateMode 'Screening') `
    '沒有 meta 就不是續跑'
Assert-Equal 'BALANCE_RESUME_SOURCE_DRIFT' (Test-ScreeningResumeCompatibility -Meta $meta -SourceFreezeDigest 'digest-b' `
    -CandidateId 'candidate-a' -TuneDigest 'tune-a' -SeedCount 8 -ShardCount 2 -GateMode 'Screening') `
    'source tree 被改過必須具名拒絕'
Assert-Equal 'BALANCE_RESUME_CANDIDATE_MISMATCH' (Test-ScreeningResumeCompatibility -Meta $meta -SourceFreezeDigest 'digest-a' `
    -CandidateId 'candidate-b' -TuneDigest 'tune-a' -SeedCount 8 -ShardCount 2 -GateMode 'Screening') `
    'candidate 換掉必須具名拒絕'
Assert-Equal 'BALANCE_RESUME_CANDIDATE_MISMATCH' (Test-ScreeningResumeCompatibility -Meta $meta -SourceFreezeDigest 'digest-a' `
    -CandidateId 'candidate-a' -TuneDigest 'tune-b' -SeedCount 8 -ShardCount 2 -GateMode 'Screening') `
    'tune digest 換掉必須具名拒絕'
Assert-Equal 'BALANCE_RESUME_PARAM_MISMATCH' (Test-ScreeningResumeCompatibility -Meta $meta -SourceFreezeDigest 'digest-a' `
    -CandidateId 'candidate-a' -TuneDigest 'tune-a' -SeedCount 16 -ShardCount 2 -GateMode 'Screening') `
    'cohort 形狀不同必須具名拒絕'

# 強殺造成的半行：只有最後一行可以被丟棄並就地截斷。
$repairRoot = New-GoldenCheckpointRoot 'repair'
$repairPath = Get-ScreeningShardPath -ArtifactRoot $repairRoot -ShardIndex 0 -Kind checkpoint
Add-GoldenCase -Path $repairPath -Line (New-GoldenCaseRecord -StrategyId 'tempo' -SeedIndex 0 -ShardCount 2)
Add-GoldenCase -Path $repairPath -Line (New-GoldenCaseRecord -StrategyId 'tempo' -SeedIndex 2 -ShardCount 2)
[IO.File]::AppendAllText($repairPath, '{"schema_version":1,"shard_index":0,"strat', (New-Object Text.UTF8Encoding($false)))
$repaired = Read-ScreeningCheckpointShard -Path $repairPath -RepairTrailingLine
Assert-Equal 2 (@($repaired.records).Count) '半行必須被丟棄，其餘 case 全部保留'
Assert-True ([bool]$repaired.repaired_trailing_line) '截斷事件必須被回報'
Assert-Equal 2 (@(Read-ScreeningCheckpointShard -Path $repairPath).records.Count) '截斷後的檔案必須是乾淨的 JSONL'
Assert-Equal '' ([string](Get-Content -Raw -Encoding UTF8 -LiteralPath $repairPath | Select-String -Pattern '"strat$' -Quiet)) '半行不得留在檔案裡'

$corruptRoot = New-GoldenCheckpointRoot 'corrupt'
$corruptPath = Get-ScreeningShardPath -ArtifactRoot $corruptRoot -ShardIndex 0 -Kind checkpoint
Add-GoldenCase -Path $corruptPath -Line '{"broken":'
Add-GoldenCase -Path $corruptPath -Line (New-GoldenCaseRecord -StrategyId 'tempo' -SeedIndex 0 -ShardCount 2)
Assert-Throws { Read-ScreeningCheckpointShard -Path $corruptPath -RepairTrailingLine } 'BALANCE_CHECKPOINT_CORRUPT' `
    '中間壞行是真損毀，不得靜默丟棄'

$mismatchRoot = New-GoldenCheckpointRoot 'mismatch'
Add-GoldenCase -Path (Get-ScreeningShardPath -ArtifactRoot $mismatchRoot -ShardIndex 0 -Kind checkpoint) `
    -Line (New-GoldenCaseRecord -StrategyId 'tempo' -SeedIndex 1 -ShardCount 2)
Assert-Throws { Read-ScreeningShardCases -ArtifactRoot $mismatchRoot -ShardIndex 0 -ShardCount 2 } `
    'BALANCE_CHECKPOINT_SHARD_MISMATCH' '分片檔裡出現別片的 seed 必須擋下'

$duplicateRoot = New-GoldenCheckpointRoot 'duplicate'
$duplicatePath = Get-ScreeningShardPath -ArtifactRoot $duplicateRoot -ShardIndex 0 -Kind checkpoint
Add-GoldenCase -Path $duplicatePath -Line (New-GoldenCaseRecord -StrategyId 'tempo' -SeedIndex 0 -ShardCount 2)
Add-GoldenCase -Path $duplicatePath -Line (New-GoldenCaseRecord -StrategyId 'tempo' -SeedIndex 0 -ShardCount 2)
Assert-Throws { Read-ScreeningShardCases -ArtifactRoot $duplicateRoot -ShardIndex 0 -ShardCount 2 } `
    'BALANCE_CHECKPOINT_DUPLICATE_CASE' '同一個 case 出現兩次必須擋下'

# 跳過清單：從已完成的記錄產生，內容與排序必須決定性。
$skipKeys = @(Get-ScreeningSkipKeys -Records (Read-ScreeningCheckpointShard -Path $repairPath).records)
Assert-Equal 'tempo:0,tempo:2' ($skipKeys -join ',') '跳過清單＝已完成的 case，排序決定性'

# ------------------------------------------------- 接線斷言（防雙實作漂移）--
$aggregateText = Get-Content -Raw -Encoding UTF8 -LiteralPath $cohortScript
foreach ($token in @(
    'screening-checkpoint.ps1', 'Test-ScreeningResumeCompatibility', 'Read-ScreeningShardCases',
    'Write-ScreeningSkipList', '--checkpoint-path', '--skip-list-path', '--pause-flag-path'
)) {
    Assert-True ($aggregateText -match [regex]::Escape($token)) "run-sharded-cohort.ps1 必須接線 '$token'"
}
$ctlPath = Join-Path $repoRoot 'tools\balance\screening-ctl.ps1'
Assert-True (Test-Path -LiteralPath $ctlPath -PathType Leaf) 'screening-ctl.ps1 必須存在'
$ctlText = Get-Content -Raw -Encoding UTF8 -LiteralPath $ctlPath
foreach ($token in @("'start', 'pause', 'resume', 'status'", '-Resume')) {
    Assert-True ($ctlText -match [regex]::Escape($token)) "screening-ctl.ps1 必須提供 '$token'"
}

# --------------------------------------------- 相等性 golden（跑正式合併路徑）--
$seedCount = 8
$shardCount = 2
$freeze = Get-ScreeningSourceFreeze -RepoRoot $repoRoot
$straightRoot = New-GoldenCheckpointRoot 'straight'
$resumeRoot = New-GoldenCheckpointRoot 'resume'
Write-GoldenMeta -ArtifactRoot $straightRoot -FreezeDigest $freeze.digest -SeedCount $seedCount -ShardCount $shardCount
Write-GoldenMeta -ArtifactRoot $resumeRoot -FreezeDigest $freeze.digest -SeedCount $seedCount -ShardCount $shardCount

# 一次跑完。
foreach ($shardIndex in 0..($shardCount - 1)) {
    $path = Get-ScreeningShardPath -ArtifactRoot $straightRoot -ShardIndex $shardIndex -Kind checkpoint
    foreach ($case in Get-GoldenShardCaseKeys -SeedCount $seedCount -ShardCount $shardCount -ShardIndex $shardIndex) {
        Add-GoldenCase -Path $path -Line (New-GoldenCaseRecord -StrategyId $case.StrategyId -SeedIndex $case.SeedIndex -ShardCount $shardCount)
    }
    Write-GoldenShardStatus -ArtifactRoot $straightRoot -ShardIndex $shardIndex -Status 'completed' `
        -Completed (Get-ScreeningShardCaseCount -SeedCount $seedCount -ShardCount $shardCount -ShardIndex $shardIndex) -Skipped 0
}

# 跑一半被強殺：分片 0 落帳 5 筆＋半行，分片 1 落帳 3 筆，兩片都沒有尾記錄。
$killedCounts = @(5, 3)
foreach ($shardIndex in 0..($shardCount - 1)) {
    $path = Get-ScreeningShardPath -ArtifactRoot $resumeRoot -ShardIndex $shardIndex -Kind checkpoint
    $cases = Get-GoldenShardCaseKeys -SeedCount $seedCount -ShardCount $shardCount -ShardIndex $shardIndex
    foreach ($case in $cases[0..($killedCounts[$shardIndex] - 1)]) {
        Add-GoldenCase -Path $path -Line (New-GoldenCaseRecord -StrategyId $case.StrategyId -SeedIndex $case.SeedIndex -ShardCount $shardCount)
    }
}
[IO.File]::AppendAllText(
    (Get-ScreeningShardPath -ArtifactRoot $resumeRoot -ShardIndex 0 -Kind checkpoint),
    '{"schema_version":1,"shard_index":0,"strategy_id":"eco',
    (New-Object Text.UTF8Encoding($false))
)
$pauseFlagPath = Get-ScreeningPauseFlagPath $resumeRoot
[IO.File]::WriteAllText($pauseFlagPath, "paused`n", (New-Object Text.UTF8Encoding($false)))

# 續跑：讀 checkpoint（修好半行）→ 產跳過清單 → 只重跑沒跑過的 case。
# 重跑的 case 拿到不同的 elapsed（真實情況也是如此），統計欄位必須完全不受影響。
Assert-True (Test-Path -LiteralPath $pauseFlagPath) '續跑前旗標存在'
Remove-Item -LiteralPath $pauseFlagPath -Force
foreach ($shardIndex in 0..($shardCount - 1)) {
    $path = Get-ScreeningShardPath -ArtifactRoot $resumeRoot -ShardIndex $shardIndex -Kind checkpoint
    $shardCheckpoint = Read-ScreeningShardCases -ArtifactRoot $resumeRoot -ShardIndex $shardIndex `
        -ShardCount $shardCount -RepairTrailingLine
    $skipList = @(Get-ScreeningSkipKeys -Records $shardCheckpoint.records)
    Write-ScreeningSkipList -Path (Get-ScreeningShardPath -ArtifactRoot $resumeRoot -ShardIndex $shardIndex -Kind skip) -Keys $skipList
    Assert-Equal $killedCounts[$shardIndex] $skipList.Count "分片 $shardIndex 的跳過清單＝強殺前已落帳的 case"
    $rerun = 0
    foreach ($case in Get-GoldenShardCaseKeys -SeedCount $seedCount -ShardCount $shardCount -ShardIndex $shardIndex) {
        if ($skipList -contains (Get-ScreeningCaseKey -StrategyId $case.StrategyId -SeedIndex $case.SeedIndex)) { continue }
        Add-GoldenCase -Path $path -Line (New-GoldenCaseRecord -StrategyId $case.StrategyId -SeedIndex $case.SeedIndex `
            -ShardCount $shardCount -ElapsedOffset 7000)
        $rerun += 1
    }
    Write-GoldenShardStatus -ArtifactRoot $resumeRoot -ShardIndex $shardIndex -Status 'completed' `
        -Completed $rerun -Skipped $skipList.Count
}
$resumeMeta = Read-ScreeningJsonFile (Get-ScreeningMetaPath $resumeRoot)
$resumeMeta | Add-Member -NotePropertyName resume_count -NotePropertyValue 1 -Force
Write-ScreeningJsonFile $resumeMeta (Get-ScreeningMetaPath $resumeRoot)

function Invoke-GoldenMerge {
    param([string]$ArtifactRoot)
    # 合併端被拒絕時會寫 stderr；PS 5.1 在 $ErrorActionPreference='Stop' 下會把原生
    # 指令的 stderr 當終止錯誤，故這段暫時放行，改以退出碼與輸出內容判讀。
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cohortScript -MergeOnly -ArtifactRoot $ArtifactRoot 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String) }
}

$straightMerge = Invoke-GoldenMerge -ArtifactRoot $straightRoot
$resumeMerge = Invoke-GoldenMerge -ArtifactRoot $resumeRoot
# 8 seeds 遠低於樣本下限，gate 必然 FAIL（exit 2）；本 golden 驗的是「兩邊一致」，
# 不是 PASS。3 = 例外／throw，代表合併路徑本身壞了。
foreach ($merge in @(@{ n = 'straight'; m = $straightMerge }, @{ n = 'resume'; m = $resumeMerge })) {
    Assert-True ($merge.m.ExitCode -eq 2) ("$($merge.n) merge 必須寫出 artifact 並以 gate FAIL(2) 結束，實際 $($merge.m.ExitCode)：`n$($merge.m.Output)")
}
$straightArtifact = Join-Path $straightRoot 'balance-playtest-screening.json'
$resumeArtifact = Join-Path $resumeRoot 'balance-playtest-screening.json'
Assert-True (Test-Path -LiteralPath $straightArtifact -PathType Leaf) '一次跑完必須產出合併 artifact'
Assert-True (Test-Path -LiteralPath $resumeArtifact -PathType Leaf) '續跑必須產出合併 artifact'

if ((Test-Path -LiteralPath $straightArtifact) -and (Test-Path -LiteralPath $resumeArtifact)) {
    $straightLines = Get-FieldLines -Path $straightArtifact
    $resumeLines = Get-FieldLines -Path $resumeArtifact
    Assert-Equal $straightLines.Count $resumeLines.Count '兩邊的欄位數必須相同'
    $mismatched = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt [Math]::Min($straightLines.Count, $resumeLines.Count); $index++) {
        if ($straightLines[$index] -cne $resumeLines[$index]) {
            $mismatched.Add("    [$index] straight=$($straightLines[$index]) resume=$($resumeLines[$index])")
        }
    }
    $checked += 1
    if ($mismatched.Count -gt 0) {
        $failures.Add("續跑後的合併統計必須與一次跑完逐欄位相同，實際有 $($mismatched.Count) 欄不同：`n" +
            (($mismatched | Select-Object -First 10) -join "`n"))
    }
    Assert-True ($straightLines.Count -gt 200) "比對必須涵蓋整份報告（實際 $($straightLines.Count) 欄）"
    # 排除清單不得是空話：時間類欄位在兩邊必須真的不同。
    $straightTime = @(Get-FieldLines -Path $straightArtifact -OnlyExcluded)
    $resumeTime = @(Get-FieldLines -Path $resumeArtifact -OnlyExcluded)
    $differing = 0
    for ($index = 0; $index -lt [Math]::Min($straightTime.Count, $resumeTime.Count); $index++) {
        if ($straightTime[$index] -cne $resumeTime[$index]) { $differing += 1 }
    }
    Assert-True ($differing -ge 5) "被排除的時間類欄位必須確實不同（實際只有 $differing 欄不同），否則相等性斷言是假的"
    $straightPayload = Get-Content -Raw -Encoding UTF8 -LiteralPath $straightArtifact | ConvertFrom-Json
    $resumePayload = Get-Content -Raw -Encoding UTF8 -LiteralPath $resumeArtifact | ConvertFrom-Json
    Assert-Equal 24 ([int]$straightPayload.strategy_seed_case_count) '一次跑完的 case 數'
    Assert-Equal 24 ([int]$resumePayload.strategy_seed_case_count) '續跑後的 case 數（不得少算或重複）'
    Assert-Equal 0 ([int]$straightPayload.execution_metrics.resume_count) '一次跑完 resume_count=0'
    Assert-Equal 1 ([int]$resumePayload.execution_metrics.resume_count) '續跑後 resume_count=1'
    Write-Output ("CHECK merged fields compared: {0} (time-only fields differing: {1})" -f $straightLines.Count, $differing)
    Write-Output ("CHECK canonical_replay_digest straight={0} resume={1}" -f
        [string]$straightPayload.canonical_replay_digest, [string]$resumePayload.canonical_replay_digest)
}

# ---------------------------------------------------- 暫停的分片不得被誤判完成 --
$pausedRoot = New-GoldenCheckpointRoot 'paused'
Write-GoldenMeta -ArtifactRoot $pausedRoot -FreezeDigest $freeze.digest -SeedCount $seedCount -ShardCount $shardCount
foreach ($shardIndex in 0..($shardCount - 1)) {
    $path = Get-ScreeningShardPath -ArtifactRoot $pausedRoot -ShardIndex $shardIndex -Kind checkpoint
    $cases = Get-GoldenShardCaseKeys -SeedCount $seedCount -ShardCount $shardCount -ShardIndex $shardIndex
    foreach ($case in $cases[0..4]) {
        Add-GoldenCase -Path $path -Line (New-GoldenCaseRecord -StrategyId $case.StrategyId -SeedIndex $case.SeedIndex -ShardCount $shardCount)
    }
    Write-GoldenShardStatus -ArtifactRoot $pausedRoot -ShardIndex $shardIndex -Status 'paused' -Completed 5 -Skipped 0
}
$pausedMerge = Invoke-GoldenMerge -ArtifactRoot $pausedRoot
Assert-Equal 4 $pausedMerge.ExitCode '暫停的 cohort 必須以 4 收場，而不是合併出一份殘缺報告'
Assert-True ($pausedMerge.Output -match 'BALANCE_SCREENING_PAUSED') '暫停必須明示回報'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $pausedRoot 'balance-playtest-screening.json'))) `
    '暫停狀態下不得寫出合併 artifact'
$pausedStatus = Get-ScreeningCheckpointStatus -ArtifactRoot $pausedRoot
Assert-Equal 10 $pausedStatus.completed_cases 'status 必須回報實際完成的 case 數'
Assert-Equal 24 $pausedStatus.expected_cases 'status 必須回報預期的 case 數'
Assert-Equal 'paused' ([string]$pausedStatus.shards[0].status) 'status 必須把暫停的分片標成 paused'

# ---------------------------------------------------------- source drift 拒絕 --
$driftRoot = New-GoldenCheckpointRoot 'drift'
Write-GoldenMeta -ArtifactRoot $driftRoot -FreezeDigest ('f' * 64) -SeedCount $seedCount -ShardCount $shardCount
foreach ($shardIndex in 0..($shardCount - 1)) {
    $path = Get-ScreeningShardPath -ArtifactRoot $driftRoot -ShardIndex $shardIndex -Kind checkpoint
    foreach ($case in Get-GoldenShardCaseKeys -SeedCount $seedCount -ShardCount $shardCount -ShardIndex $shardIndex) {
        Add-GoldenCase -Path $path -Line (New-GoldenCaseRecord -StrategyId $case.StrategyId -SeedIndex $case.SeedIndex -ShardCount $shardCount)
    }
    Write-GoldenShardStatus -ArtifactRoot $driftRoot -ShardIndex $shardIndex -Status 'completed' -Completed 12 -Skipped 0
}
$driftMerge = Invoke-GoldenMerge -ArtifactRoot $driftRoot
Assert-True ($driftMerge.Output -match 'BALANCE_RESUME_SOURCE_DRIFT') `
    "source tree 與 meta 不符時，合併必須具名拒絕，實際輸出：`n$($driftMerge.Output)"
Assert-True (-not (Test-Path -LiteralPath (Join-Path $driftRoot 'balance-playtest-screening.json'))) `
    '被拒絕的證據不得產出合併 artifact'

foreach ($name in @('repair', 'corrupt', 'mismatch', 'duplicate', 'straight', 'resume', 'paused', 'drift')) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("balance-screening-golden-$PID-$name")
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Output "FAIL $failure" }
    Write-Output "RESULT FAIL ($($failures.Count) assertion failures of $checked)"
    exit 1
}
Write-Output "RESULT PASS ($checked assertions: checkpoint IO, resume rejection, pause, merge equality)"
exit 0
