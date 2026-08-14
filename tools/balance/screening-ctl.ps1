# 分片 screening 的操作台：start / pause / resume / status 四個子命令。
#
#   start   開新的一輪（預設先跑 -Suite All，依現行紀律；-SkipAll 才略過）
#   pause   建立暫停旗標；各分片跑完手上的 case 就收工，進度全在 checkpoint 裡
#   resume  接著跑（重開機後也是同一條指令，不依賴任何駐留行程）
#   status  盤點 meta／各分片進度／暫停旗標／合併結果
#
# 用法（GODOT_BIN 已設好時 -GodotPath 可省略）：
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\balance\screening-ctl.ps1 start -SeedCount 1000 -ShardCount 16
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\balance\screening-ctl.ps1 start -SkipAll
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\balance\screening-ctl.ps1 pause
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\balance\screening-ctl.ps1 resume
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\balance\screening-ctl.ps1 status
#
# 退出碼：0 成功／已受理，2 gate FAIL 或前置 All 失敗，3 操作被拒（狀態不符），
#         4 本輪處於暫停狀態（start/resume 在前景等到分片暫停時）。

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('start', 'pause', 'resume', 'status')]
    [string]$Command,
    [string]$GodotPath = '',
    [ValidateRange(1, 10000)]
    [int]$SeedCount = 1000,
    [ValidateRange(1, 16)]
    [int]$ShardCount = 16,
    [ValidateSet('Screening', 'Final')]
    [string]$GateMode = 'Screening',
    [ValidateRange(600, 604800)]
    [int]$TimeoutSeconds = 43200,
    # 預設 $false：start 先跑 tools\run-tests.ps1 -Suite All，跑批前的紀律不放寬。
    [switch]$SkipAll,
    # 前景執行（測試與證據用）；預設是背景協調行程，關掉終端機也不影響。
    [switch]$Foreground
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'screening-checkpoint.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$artifactRoot = Join-Path $repoRoot 'artifacts\test'
$cohortScript = Join-Path $PSScriptRoot 'run-sharded-cohort.ps1'
$pauseFlagPath = Get-ScreeningPauseFlagPath $artifactRoot
$metaPath = Get-ScreeningMetaPath $artifactRoot

function Resolve-GodotPath {
    $candidate = if ([string]::IsNullOrWhiteSpace($GodotPath)) { [string]$env:GODOT_BIN } else { $GodotPath }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw 'Set -GodotPath or the GODOT_BIN environment variable.'
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

# 退出碼放 $script:CohortExitCode 而不是回傳值：函式的「回傳值」是它寫進成功流的
# 全部東西（含協調端 stdout），`exit (Invoke-Cohort ...)` 會拿到陣列而炸掉。
$script:CohortExitCode = 0

function Invoke-Cohort {
    param([string[]]$CohortArguments)
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cohortScript
    ) + $CohortArguments
    if ($Foreground) {
        & powershell.exe @arguments
        $script:CohortExitCode = $LASTEXITCODE
        return
    }
    $stdout = Join-Path $artifactRoot 'balance-screening-coordinator.stdout.log'
    $stderr = Join-Path $artifactRoot 'balance-screening-coordinator.stderr.log'
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Write-Output "Coordinator started as PID $($process.Id); stdout: $stdout"
    Write-Output 'Progress: tools\balance\screening-ctl.ps1 status (or the screening-progress web page)'
    $script:CohortExitCode = 0
}

# 注意：本函式把盤點結果寫進成功流，呼叫端不可以 `exit (Show-Status)`。
function Show-Status {
    $status = Get-ScreeningCheckpointStatus -ArtifactRoot $artifactRoot
    if ($null -eq $status.meta) {
        Write-Output 'No screening checkpoint found; nothing has been started yet.'
        return
    }
    $meta = $status.meta
    Write-Output ('candidate      : {0}' -f [string]$meta.candidate_id)
    Write-Output ('tune digest    : {0}' -f [string]$meta.tune_digest)
    Write-Output ('source freeze  : {0}' -f [string]$meta.source_freeze_digest)
    Write-Output ('git head       : {0}' -f [string]$meta.git_head)
    Write-Output ('cohort         : {0} seeds x {1} shards ({2}), started {3}, resumes {4}' -f `
        [int]$meta.seed_count, [int]$meta.shard_count, [string]$meta.gate_mode,
        [string]$meta.started_at_utc, [int]$meta.resume_count)
    $state = if ($null -ne $status.state) { [string]$status.state.status } else { 'unknown' }
    Write-Output ('state          : {0}{1}' -f $state, $(if ($status.pause_flag) { ' (pause flag present)' } else { '' }))
    Write-Output ('cases          : {0} / {1}' -f $status.completed_cases, $status.expected_cases)
    foreach ($shard in $status.shards) {
        Write-Output ('  shard {0:D2} : {1,6} / {2,-6} {3}' -f `
            [int]$shard.shard_index, [int]$shard.cases, [int]$shard.expected_cases, [string]$shard.status)
    }
    $mergedName = if ([string]$meta.gate_mode -eq 'Final') { 'balance-playtest.json' } else { 'balance-playtest-screening.json' }
    $merged = Read-ScreeningJsonFile (Join-Path $artifactRoot $mergedName)
    if ($null -ne $merged -and [string]$merged.candidate_id -ceq [string]$meta.candidate_id) {
        Write-Output ('merged gate    : {0} {1}' -f [string]$merged.gate, (@($merged.gate_reasons) -join ','))
    }
    else {
        Write-Output 'merged gate    : (not published for this candidate yet)'
    }
}

switch ($Command) {
    'start' {
        $status = Get-ScreeningCheckpointStatus -ArtifactRoot $artifactRoot
        if ($null -ne $status.meta -and $null -ne $status.state -and
            [string]$status.state.status -eq 'running') {
            Write-Output 'A cohort is already marked running; pause it or delete the checkpoint before starting a new one.'
            exit 3
        }
        if (-not $SkipAll) {
            $testScript = Join-Path $repoRoot 'tools\run-tests.ps1'
            Write-Output 'Running -Suite All before the cohort (use -SkipAll to bypass).'
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testScript -Suite All
            if ($LASTEXITCODE -ne 0) {
                Write-Output "Pre-flight -Suite All failed with exit code $LASTEXITCODE; cohort not started."
                exit 2
            }
        }
        if (Test-Path -LiteralPath $pauseFlagPath) { Remove-Item -LiteralPath $pauseFlagPath -Force }
        Invoke-Cohort @(
            '-GodotPath', (Resolve-GodotPath),
            '-SeedCount', [string]$SeedCount,
            '-ShardCount', [string]$ShardCount,
            '-GateMode', $GateMode,
            '-TimeoutSeconds', [string]$TimeoutSeconds
        )
        exit $script:CohortExitCode
    }
    'pause' {
        if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
            Write-Output 'No screening checkpoint found; nothing to pause.'
            exit 3
        }
        $directory = Split-Path -Parent $pauseFlagPath
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        [IO.File]::WriteAllText(
            $pauseFlagPath,
            ([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') + "`n"),
            (New-Object Text.UTF8Encoding($false))
        )
        Write-Output "Pause requested: $pauseFlagPath"
        Write-Output 'Each shard finishes the case it is on, writes its tail record, and exits; progress is kept.'
        exit 0
    }
    'resume' {
        $meta = Read-ScreeningJsonFile $metaPath
        if ($null -eq $meta) {
            Write-Output 'No screening checkpoint found; use start instead.'
            exit 3
        }
        if (Test-Path -LiteralPath $pauseFlagPath) { Remove-Item -LiteralPath $pauseFlagPath -Force }
        # 續跑一律沿用 meta 記下的 cohort 形狀，避免手打參數與 checkpoint 不符。
        Invoke-Cohort @(
            '-GodotPath', (Resolve-GodotPath),
            '-SeedCount', [string][int]$meta.seed_count,
            '-ShardCount', [string][int]$meta.shard_count,
            '-GateMode', [string]$meta.gate_mode,
            '-TimeoutSeconds', [string]$TimeoutSeconds,
            '-Resume'
        )
        exit $script:CohortExitCode
    }
    'status' {
        Show-Status
        exit 0
    }
}
