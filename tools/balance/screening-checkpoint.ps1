# 分片 screening 的逐案 checkpoint 共用模組。
#
# 由 tools/balance/run-sharded-cohort.ps1（跑批與合併）、tools/balance/screening-ctl.ps1
# （start/pause/resume/status）共同 dot-source；tools/balance/tests/test-screening-checkpoint.ps1
# 直接對本檔的函式做 golden。所有 checkpoint 檔都落在 <artifact-root>/screening-checkpoint/：
#
#   meta.json            開跑時的身分凍結（candidate / source freeze / seed 與 shard 切割）
#   state.json           本輪狀態（running / paused / completed / failed）——純觀測用
#   pause.flag           優雅暫停旗標；分片在 case 邊界輪詢，見旗標就寫尾記錄後收工
#   shard-NN.jsonl       逐案 append 的 checkpoint（一個 case 一行）
#   shard-NN.status.json 分片尾記錄（completed / paused ＋ candidate 身分）
#   shard-NN.skip        續跑時交給 runner 的跳過清單（已完成的 strategy:seed）
#
# 續跑不依賴任何駐留行程：重開機後執行同一條 -Resume 指令即可，狀態全在上列檔案裡。

$script:ScreeningCheckpointDirName = 'screening-checkpoint'
$script:ScreeningStrategyIds = @('tempo', 'economy', 'synergy')

function Get-ScreeningCheckpointRoot {
    param([Parameter(Mandatory = $true)][string]$ArtifactRoot)
    return (Join-Path $ArtifactRoot $script:ScreeningCheckpointDirName)
}

function Get-ScreeningMetaPath {
    param([Parameter(Mandatory = $true)][string]$ArtifactRoot)
    return (Join-Path (Get-ScreeningCheckpointRoot $ArtifactRoot) 'meta.json')
}

function Get-ScreeningStatePath {
    param([Parameter(Mandatory = $true)][string]$ArtifactRoot)
    return (Join-Path (Get-ScreeningCheckpointRoot $ArtifactRoot) 'state.json')
}

function Get-ScreeningPauseFlagPath {
    param([Parameter(Mandatory = $true)][string]$ArtifactRoot)
    return (Join-Path (Get-ScreeningCheckpointRoot $ArtifactRoot) 'pause.flag')
}

function Get-ScreeningShardPath {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactRoot,
        [Parameter(Mandatory = $true)][int]$ShardIndex,
        [ValidateSet('checkpoint', 'status', 'skip')][string]$Kind = 'checkpoint'
    )
    $name = switch ($Kind) {
        'checkpoint' { 'shard-{0:D2}.jsonl' -f $ShardIndex }
        'status' { 'shard-{0:D2}.status.json' -f $ShardIndex }
        'skip' { 'shard-{0:D2}.skip' -f $ShardIndex }
    }
    return (Join-Path (Get-ScreeningCheckpointRoot $ArtifactRoot) $name)
}

# 分片 k 拿到的 seed 數（seed_index % shard_count == k）；乘上三個策略就是該片的 case 數。
# run-sharded-cohort.ps1 的 launch 迴圈與網頁伺服器都必須用同一條公式。
function Get-ScreeningShardSeedCount {
    param(
        [Parameter(Mandatory = $true)][int]$SeedCount,
        [Parameter(Mandatory = $true)][int]$ShardCount,
        [Parameter(Mandatory = $true)][int]$ShardIndex
    )
    if ($ShardIndex -ge $SeedCount) { return 0 }
    return [int][math]::Floor(($SeedCount - 1 - $ShardIndex) / $ShardCount) + 1
}

function Get-ScreeningShardCaseCount {
    param(
        [Parameter(Mandatory = $true)][int]$SeedCount,
        [Parameter(Mandatory = $true)][int]$ShardCount,
        [Parameter(Mandatory = $true)][int]$ShardIndex
    )
    return (Get-ScreeningShardSeedCount -SeedCount $SeedCount -ShardCount $ShardCount -ShardIndex $ShardIndex) *
        $script:ScreeningStrategyIds.Count
}

function Get-ScreeningCaseKey {
    param(
        [Parameter(Mandatory = $true)][string]$StrategyId,
        [Parameter(Mandatory = $true)][int]$SeedIndex
    )
    # 必須與 tests/runners/balance_checkpoint_ledger.gd 的 case_key() 逐字相同。
    return "${StrategyId}:${SeedIndex}"
}

function Write-ScreeningJsonFile {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $json = $Value | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Read-ScreeningJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return ($text | ConvertFrom-Json) } catch { return $null }
}

# 讀一片的逐案 checkpoint。行程被強殺時最後一行可能只寫了一半：只有「最後一行」
# 允許被丟棄並就地截斷（那個 case 會在續跑時重跑）；中間任何一行壞掉都是真正的
# 資料損毀，直接具名拋出，不猜。
function Read-ScreeningCheckpointShard {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$RepairTrailingLine
    )
    $result = [ordered]@{
        path = $Path
        records = @()
        repaired_trailing_line = $false
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]$result }
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    if ([string]::IsNullOrWhiteSpace($text)) { return [pscustomobject]$result }
    $lines = @($text -split "`n" | ForEach-Object { $_.TrimEnd("`r") } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -eq 0) { return [pscustomobject]$result }
    # 快路徑：整片包成一個 JSON 陣列一次解析（30k 行時逐行解析太慢）。
    # PS 5.1 的 ConvertFrom-Json 會把陣列當「單一物件」輸出，先接進變數再 @() 展平，
    # 直接寫 @(... | ConvertFrom-Json) 會多包一層。
    $parsed = $null
    try { $parsed = ('[' + ($lines -join ',') + ']') | ConvertFrom-Json } catch { $parsed = $null }
    if ($null -ne $parsed) {
        $result.records = @($parsed)
        return [pscustomobject]$result
    }
    # 慢路徑：逐行解析，找出壞掉的是哪一行。
    $records = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $record = $null
        try { $record = $lines[$index] | ConvertFrom-Json } catch { $record = $null }
        if ($null -eq $record) {
            if ($index -ne $lines.Count - 1) {
                throw "BALANCE_CHECKPOINT_CORRUPT: $Path line $($index + 1) is not valid JSON."
            }
            $result.repaired_trailing_line = $true
            if ($RepairTrailingLine) {
                $kept = @($lines[0..($index - 1)])
                if ($index -eq 0) { $kept = @() }
                $content = if ($kept.Count -eq 0) { '' } else { ($kept -join "`n") + "`n" }
                [IO.File]::WriteAllText($Path, $content, (New-Object Text.UTF8Encoding($false)))
            }
            break
        }
        $records.Add($record)
    }
    $result.records = $records.ToArray()
    return [pscustomobject]$result
}

# 一片的 checkpoint 讀成「case 記錄清單」，同時做該片的結構檢查：
# seed 必須屬於這一片、不得重複、case 內外的 strategy/seed 必須一致。
function Read-ScreeningShardCases {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactRoot,
        [Parameter(Mandatory = $true)][int]$ShardIndex,
        [Parameter(Mandatory = $true)][int]$ShardCount,
        [switch]$RepairTrailingLine
    )
    $path = Get-ScreeningShardPath -ArtifactRoot $ArtifactRoot -ShardIndex $ShardIndex -Kind checkpoint
    $shard = Read-ScreeningCheckpointShard -Path $path -RepairTrailingLine:$RepairTrailingLine
    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($record in @($shard.records)) {
        $case = $record.case
        if ($null -eq $case) {
            throw "BALANCE_CHECKPOINT_CORRUPT: $path has a record without a case payload."
        }
        $strategyId = [string]$record.strategy_id
        $seedIndex = [int]$record.seed_index
        if ($strategyId -cne [string]$case.strategy_id -or $seedIndex -ne [int]$case.seed_index) {
            throw "BALANCE_CHECKPOINT_CORRUPT: $path record header does not match its case payload."
        }
        if ($ShardCount -gt 0 -and ($seedIndex % $ShardCount) -ne $ShardIndex) {
            throw "BALANCE_CHECKPOINT_SHARD_MISMATCH: $path holds seed $seedIndex which does not belong to shard $ShardIndex."
        }
        $key = Get-ScreeningCaseKey -StrategyId $strategyId -SeedIndex $seedIndex
        if (-not $seen.Add($key)) {
            throw "BALANCE_CHECKPOINT_DUPLICATE_CASE: $path holds $key twice."
        }
    }
    return $shard
}

function Get-ScreeningSkipKeys {
    param($Records)
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($record in @($Records)) {
        $keys.Add((Get-ScreeningCaseKey -StrategyId ([string]$record.strategy_id) -SeedIndex ([int]$record.seed_index)))
    }
    return @($keys | Sort-Object -CaseSensitive)
}

function Write-ScreeningSkipList {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Keys
    )
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $content = if ($Keys.Count -eq 0) { '' } else { ($Keys -join "`n") + "`n" }
    [IO.File]::WriteAllText($Path, $content, (New-Object Text.UTF8Encoding($false)))
}

# 續跑的具名拒絕。回空字串＝可以續跑；否則回傳一個穩定的拒絕碼，呼叫端直接拋出。
function Test-ScreeningResumeCompatibility {
    param(
        $Meta,
        [string]$SourceFreezeDigest,
        [string]$CandidateId,
        [string]$TuneDigest,
        [int]$SeedCount,
        [int]$ShardCount,
        [string]$GateMode
    )
    if ($null -eq $Meta) { return 'BALANCE_RESUME_META_MISSING' }
    foreach ($field in @('source_freeze_digest', 'candidate_id', 'tune_digest', 'seed_count', 'shard_count', 'gate_mode')) {
        if ($null -eq $Meta.$field -or [string]::IsNullOrWhiteSpace([string]$Meta.$field)) {
            return 'BALANCE_RESUME_META_INVALID'
        }
    }
    if ([string]$Meta.source_freeze_digest -cne $SourceFreezeDigest) {
        return 'BALANCE_RESUME_SOURCE_DRIFT'
    }
    if ([string]$Meta.candidate_id -cne $CandidateId -or [string]$Meta.tune_digest -cne $TuneDigest) {
        return 'BALANCE_RESUME_CANDIDATE_MISMATCH'
    }
    if ([int]$Meta.seed_count -ne $SeedCount -or [int]$Meta.shard_count -ne $ShardCount -or
        [string]$Meta.gate_mode -cne $GateMode) {
        return 'BALANCE_RESUME_PARAM_MISMATCH'
    }
    return ''
}

# 觀測用彙總：每片已完成幾個 case、尾記錄是什麼狀態。screening-ctl status 與
# tools/balance/screening-server.py 的 /status 都以這個形狀為準。
function Get-ScreeningCheckpointStatus {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactRoot
    )
    $meta = Read-ScreeningJsonFile (Get-ScreeningMetaPath $ArtifactRoot)
    $state = Read-ScreeningJsonFile (Get-ScreeningStatePath $ArtifactRoot)
    $paused = Test-Path -LiteralPath (Get-ScreeningPauseFlagPath $ArtifactRoot) -PathType Leaf
    $shards = New-Object System.Collections.Generic.List[object]
    $completedCases = 0
    $expectedCases = 0
    if ($null -ne $meta) {
        $seedCount = [int]$meta.seed_count
        $shardCount = [int]$meta.shard_count
        for ($shardIndex = 0; $shardIndex -lt $shardCount; $shardIndex++) {
            $path = Get-ScreeningShardPath -ArtifactRoot $ArtifactRoot -ShardIndex $shardIndex -Kind checkpoint
            $cases = 0
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $cases = @(Get-Content -Encoding UTF8 -LiteralPath $path |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
            }
            $statusFile = Read-ScreeningJsonFile (Get-ScreeningShardPath -ArtifactRoot $ArtifactRoot -ShardIndex $shardIndex -Kind status)
            $expected = Get-ScreeningShardCaseCount -SeedCount $seedCount -ShardCount $shardCount -ShardIndex $shardIndex
            $completedCases += $cases
            $expectedCases += $expected
            $shards.Add([ordered]@{
                shard_index = $shardIndex
                cases = $cases
                expected_cases = $expected
                status = if ($null -ne $statusFile) { [string]$statusFile.status } else { 'running' }
            })
        }
    }
    return [pscustomobject]([ordered]@{
        artifact_root = $ArtifactRoot
        meta = $meta
        state = $state
        pause_flag = $paused
        shards = $shards.ToArray()
        completed_cases = $completedCases
        expected_cases = $expectedCases
    })
}

# Source freeze：跑批開始時凍結「非 artifacts／非 .pipeline」的全部 git 檔案內容。
# 續跑時重算並與 meta 記錄的 digest 比對——樹被改過就具名拒絕，不讓半舊半新的
# 程式碼混進同一批證據。
function Get-ScreeningGitSourcePaths {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    $gitCommand = Get-Command git -ErrorAction Stop
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $gitCommand.Source
    $escapedRoot = $RepoRoot.Replace('"', '\"')
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

function Get-ScreeningSourceFreeze {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    $relativePaths = @(Get-ScreeningGitSourcePaths -RepoRoot $RepoRoot | Where-Object {
        $_ -and -not $_.StartsWith('artifacts/') -and -not $_.StartsWith('.pipeline/')
    } | Sort-Object -CaseSensitive)
    $entries = New-Object System.Collections.Generic.List[object]
    $fragments = New-Object Text.StringBuilder
    foreach ($relativePath in $relativePaths) {
        $absolutePath = Join-Path $RepoRoot $relativePath
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
    $head = (git -C $RepoRoot rev-parse HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'git rev-parse failed while building source freeze.' }
    return [pscustomobject]@{
        digest = $digest
        git_head = $head
        file_count = $entries.Count
        files = $entries.ToArray()
    }
}

function Write-ScreeningState {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactRoot,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Detail = '',
        [int]$CoordinatorPid = 0
    )
    Write-ScreeningJsonFile ([ordered]@{
        artifact_schema_version = 1
        runner = 'balance-screening-state'
        status = $Status
        detail = $Detail
        coordinator_pid = $CoordinatorPid
        updated_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }) (Get-ScreeningStatePath $ArtifactRoot)
}
