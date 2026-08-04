[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [ValidateRange(8, 8)]
    [int]$ShardCount = 8,
    [ValidateRange(1, 16)]
    [int]$SeedsPerShard = 1,
    [ValidateRange(600, 7200)]
    [int]$TimeoutSeconds = 1800,
    [ValidateRange(1, 600000)]
    [int]$SingleProcessBaselineMeanMs = 56429
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
    $relativePaths = @(Get-GitSourcePaths)
    $relativePaths = @($relativePaths | Where-Object {
        $_ -and -not $_.StartsWith('artifacts/') -and -not $_.StartsWith('.pipeline/')
    } | Sort-Object -CaseSensitive)
    $entries = New-Object System.Collections.Generic.List[object]
    $fragments = New-Object System.Text.StringBuilder
    foreach ($relativePath in $relativePaths) {
        $absolutePath = Join-Path $repoRoot $relativePath
        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            throw "Source freeze path missing: $relativePath"
        }
        $sha = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $entries.Add([ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = $sha })
        [void]$fragments.Append($relativePath.Replace('\', '/'))
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
    $json = $Value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
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
$freezePath = Join-Path $artifactRoot 'balance-calibration-source-freeze.json'
Write-Utf8Json ([ordered]@{
    schema_version = 1
    kind = 'balance-calibration-source-freeze'
    source_freeze_digest = $freezeBefore.digest
    git_head = $freezeBefore.git_head
    file_count = $freezeBefore.file_count
    files = $freezeBefore.files
}) $freezePath

$processes = New-Object System.Collections.Generic.List[object]
for ($shardIndex = 0; $shardIndex -lt $ShardCount; $shardIndex++) {
    $artifactName = 'balance-calibration-shard-{0:D2}.json' -f $shardIndex
    $artifactPath = Join-Path $artifactRoot $artifactName
    $logPath = Join-Path $artifactRoot ('balance-calibration-shard-{0:D2}.godot.log' -f $shardIndex)
    if (Test-Path -LiteralPath $artifactPath) { Remove-Item -LiteralPath $artifactPath -Force }
    if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
    $arguments = @(
        '--headless', '--path', $repoRoot, '--log-file', $logPath,
        '--script', 'res://tests/runners/balance_playtest_runner.gd', '--',
        '--seed-start', [string]$shardIndex,
        '--seed-count', [string]$SeedsPerShard,
        '--seed-stride', [string]$ShardCount,
        '--artifact-path', "res://artifacts/test/$artifactName",
        '--shard'
    )
    $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -WindowStyle Hidden
    $processes.Add([pscustomobject]@{
        Index = $shardIndex
        SeedStart = $shardIndex
        SeedStride = $ShardCount
        SeedCount = $SeedsPerShard
        Process = $process
        Artifact = $artifactPath
        Log = $logPath
    })
}

foreach ($entry in $processes) {
    if (-not $entry.Process.WaitForExit($TimeoutSeconds * 1000)) {
        & taskkill.exe /PID $entry.Process.Id /T /F | Out-Null
        throw "Calibration shard $($entry.Index) timed out."
    }
    if ($entry.Process.ExitCode -ne 0) {
        throw "Calibration shard $($entry.Index) failed with exit code $($entry.Process.ExitCode)."
    }
    if (-not (Test-Path -LiteralPath $entry.Artifact -PathType Leaf)) {
        throw "Calibration shard $($entry.Index) did not publish an artifact."
    }
}

$freezeAfter = Get-SourceFreeze
if ($freezeAfter.digest -cne $freezeBefore.digest) {
    throw 'Source changed during calibration; all shard evidence is rejected.'
}

$candidateFields = @('candidate_id', 'content_version', 'manifest_digest', 'tune_digest')
$reports = New-Object System.Collections.Generic.List[object]
$mapping = New-Object System.Collections.Generic.List[object]
$primaryElapsedTotal = 0L
$primaryCaseCount = 0
$replayElapsedTotal = 0L
$replayCaseCount = 0
$failedSeeds = New-Object System.Collections.Generic.List[object]
foreach ($entry in $processes) {
    $report = Get-Content -Raw -Encoding UTF8 -LiteralPath $entry.Artifact | ConvertFrom-Json
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
    $mapping.Add([ordered]@{
        shard_index = $entry.Index
        seed_rule = "seed_index % $ShardCount == $($entry.Index)"
        seed_start = $entry.SeedStart
        seed_stride = $entry.SeedStride
        seed_count = $entry.SeedCount
        artifact = [IO.Path]::GetFileName($entry.Artifact)
        primary_case_count = [int]$report.execution_metrics.primary_case_count
        primary_mean_elapsed_ms = [double]$report.execution_metrics.primary_mean_elapsed_ms
        replay_sample_count = [int]$report.execution_metrics.replay_sample_count
        replay_mean_elapsed_ms = [double]$report.execution_metrics.replay_mean_elapsed_ms
    })
    $primaryElapsedTotal += [long]$report.execution_metrics.primary_elapsed_ms_total
    $primaryCaseCount += [int]$report.execution_metrics.primary_case_count
    $replayElapsedTotal += [long]$report.execution_metrics.replay_elapsed_ms_total
    $replayCaseCount += [int]$report.execution_metrics.replay_sample_count
    foreach ($failed in @($report.failed_seeds)) { $failedSeeds.Add($failed) }
}

foreach ($field in $candidateFields) {
    if (@($reports | ForEach-Object { [string]$_.$field } | Select-Object -Unique).Count -ne 1) {
        throw "Calibration shard candidate mismatch: $field"
    }
}
$expectedCases = $ShardCount * $SeedsPerShard * 3
if ($primaryCaseCount -ne $expectedCases) {
    throw "Calibration expected $expectedCases primary cases, got $primaryCaseCount."
}
if ($failedSeeds.Count -gt 0) { throw 'Calibration contains failed seeds.' }

$primaryMean = [double]$primaryElapsedTotal / $primaryCaseCount
$replayMean = if ($replayCaseCount -gt 0) { [double]$replayElapsedTotal / $replayCaseCount } else { 0.0 }
$slowdownPercent = (($primaryMean / $SingleProcessBaselineMeanMs) - 1.0) * 100.0
$decision = if ($slowdownPercent -gt 30.0) {
    'USE_4_SHARDS'
}
elseif ($slowdownPercent -lt 10.0) {
    'ELIGIBLE_FOR_12_SHARD_TRIAL'
}
else {
    'USE_8_SHARDS'
}
$summary = [ordered]@{
    artifact_schema_version = 1
    runner = 'balance-calibration'
    source_freeze_digest = $freezeBefore.digest
    source_freeze_artifact = [IO.Path]::GetFileName($freezePath)
    git_head = $freezeBefore.git_head
    candidate_id = [string]$reports[0].candidate_id
    content_version = [string]$reports[0].content_version
    manifest_digest = [string]$reports[0].manifest_digest
    tune_digest = [string]$reports[0].tune_digest
    shard_count = $ShardCount
    strategy_seed_case_count = $primaryCaseCount
    single_process_baseline_mean_ms = $SingleProcessBaselineMeanMs
    primary_mean_elapsed_ms = $primaryMean
    replay_sample_count = $replayCaseCount
    replay_mean_elapsed_ms = $replayMean
    slowdown_percent = $slowdownPercent
    threshold_decision = $decision
    shard_mapping = $mapping.ToArray()
    started_at_utc = $startedAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
    finished_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$summaryPath = Join-Path $artifactRoot 'balance-calibration.json'
Write-Utf8Json $summary $summaryPath
$readBack = Get-Content -Raw -Encoding UTF8 -LiteralPath $summaryPath | ConvertFrom-Json
if ([int]$readBack.strategy_seed_case_count -ne $expectedCases -or
    [string]$readBack.source_freeze_digest -cne $freezeBefore.digest) {
    throw 'Calibration summary read-back failed.'
}
Write-Output $summaryPath
