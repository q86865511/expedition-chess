[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [string]$CandidatePath = 'specs\balance-playtest\candidates\balance.g2.6dfc5cb624a9.json',
    [string]$PinnedProductionCandidatePath = 'application\balance\production_balance_candidate.json',
    [string]$FrozenScreeningPath = 'artifacts\test\balance-playtest-screening.json',
    [string]$Tier2EvidencePath = 'artifacts\test\balance-phase0-tier2plus-evidence.json',
    [Parameter(Mandatory = $true)]
    [string]$NulEvidencePath,
    [string]$OutputRoot = 'artifacts\rc\staging',
    [ValidateRange(10, 600)]
    [int]$SmokeTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\rc'))
$resolvedOutput = [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))
$allowedPrefix = $allowedRoot.TrimEnd('\') + '\'
$utf8NoBom = New-Object Text.UTF8Encoding($false)

function Resolve-RepoFile {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Label)
    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }
    $repoPrefix = $repoRoot.TrimEnd('\') + '\'
    if (-not $candidate.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "$Label must be an existing file under the repository: $Path"
    }
    return $candidate
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Label)
    try {
        return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json)
    }
    catch {
        throw "$Label is not valid JSON: $Path"
    }
}

function Write-JsonAtomic {
    param([Parameter(Mandatory = $true)]$Value, [Parameter(Mandatory = $true)][string]$Path)
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 20), $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
    $null = Read-Json -Path $Path -Label ([IO.Path]::GetFileName($Path))
}

function Copy-SealedArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    $sourceHash = Get-Sha256 $Source
    $destinationHash = Get-Sha256 $Destination
    if ($sourceHash -ne $destinationHash) {
        throw "Artifact copy read-back mismatch: $Destination"
    }
    return $destinationHash
}

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $previousGlobalConfig = $env:GIT_CONFIG_GLOBAL
    try {
        $env:GIT_CONFIG_GLOBAL = 'NUL'
        # Some managed Windows images expose an unreadable global excludes file.
        # Pin the excludes source to this repository so warnings cannot masquerade
        # as porcelain status rows or make a clean tree fail for the wrong reason.
        $repoExclude = Join-Path $repoRoot '.git\info\exclude'
        $result = @(& git -c "core.excludesFile=$repoExclude" -C $repoRoot @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "git $($Arguments -join ' ') failed: $($result -join [Environment]::NewLine)"
        }
        return $result
    }
    finally {
        $env:GIT_CONFIG_GLOBAL = $previousGlobalConfig
    }
}

function Assert-SourceIdentity {
    param([string]$ExpectedCommit = '')
    $status = @(Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all'))
    if ($status.Count -ne 0) {
        throw "Source tree must remain clean throughout packaging:`n$($status -join [Environment]::NewLine)"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit)) {
        $actualCommit = [string](Invoke-Git @('rev-parse', '--verify', 'HEAD') | Select-Object -First 1)
        if ($actualCommit -ne $ExpectedCommit) {
            throw "Source commit changed during packaging: expected $ExpectedCommit, found $actualCommit"
        }
    }
}

function Invoke-TestSuite {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('All', 'ExpeditionSoak')][string]$Suite,
        [Parameter(Mandatory = $true)][string]$Godot
    )
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        (Join-Path $repoRoot 'tools\run-tests.ps1'), '-Suite', $Suite,
        '-GodotPath', $Godot, '-TimeoutSeconds', '600'
    )
    if ($Suite -eq 'ExpeditionSoak') {
        $arguments += @('-SeedCount', '10000')
    }
    & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Suite gate failed with exit code $LASTEXITCODE."
    }
}

function Get-GodotVersion {
    param([Parameter(Mandatory = $true)][string]$Executable)
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.Arguments = '--version'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Godot version probe did not start.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) {
        $process.Kill()
        $process.WaitForExit()
        throw 'Godot version probe timed out.'
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    if ($process.ExitCode -ne 0) {
        throw "Godot version probe failed with exit code $($process.ExitCode): $stderr"
    }
    $versionLines = @(($stdout + [Environment]::NewLine + $stderr) -split '\r?\n' |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique)
    if ($versionLines.Count -ne 1) {
        throw "Godot version probe must emit exactly one unique non-empty line; found $($versionLines.Count)."
    }
    return [string]$versionLines[0]
}

function Invoke-RcSmokePhase {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string]$ProfileRoot,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )
    $safePhase = $Phase.Replace(':', '-').Replace('/', '-')
    $godotLog = Join-Path $allowedRoot "rc-smoke-$safePhase.godot.log"
    $processLog = Join-Path $allowedRoot "rc-smoke-$safePhase.process.log"
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $confirmFlag = ''
    if ($Phase -eq 'restart-abandon-verify') { $confirmFlag = ' --rc-smoke-confirm' }
    $startInfo.Arguments = ('--headless --log-file "{0}" -- --rc-smoke-phase={1}{2}' -f $godotLog, $Phase, $confirmFlag)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables['APPDATA'] = $ProfileRoot
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "RC smoke phase did not start: $Phase" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill()
        $process.WaitForExit()
        throw "RC smoke phase timed out: $Phase"
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    [IO.File]::WriteAllText($processLog, ($stdout + $stderr), $utf8NoBom)
    $godotText = if (Test-Path -LiteralPath $godotLog) { Get-Content -Raw -Encoding UTF8 -LiteralPath $godotLog } else { '' }
    if ($process.ExitCode -ne 0) { throw "RC smoke phase failed with exit code $($process.ExitCode): $Phase" }
    $combinedText = $stdout + $stderr + $godotText
    $fatalLines = @($combinedText -split '\r?\n' | Where-Object {
        ($_ -match 'SCRIPT ERROR|Parse Error|CRASH|content bootstrap failed|^ERROR:') -and
        ($_ -notmatch '^ERROR: \d+ resources still in use at exit')
    })
    if ($fatalLines.Count -ne 0) {
        throw "RC smoke phase emitted a fatal engine error: $Phase`n$($fatalLines -join [Environment]::NewLine)"
    }
    $matches = [regex]::Matches($stdout, '(?m)^RC_SMOKE_RESULT=(\{[^\r\n]+\})\s*$')
    if ($matches.Count -ne 1) { throw "RC smoke phase must emit exactly one result marker: $Phase" }
    try { $result = $matches[0].Groups[1].Value | ConvertFrom-Json }
    catch { throw "RC smoke phase emitted invalid result JSON: $Phase" }
    if ($null -eq $result.PSObject.Properties['ok'] -or -not [bool]$result.ok) {
        throw "RC smoke phase marker did not report ok=true: $Phase"
    }
    if ($null -ne $result.PSObject.Properties['passed'] -and -not [bool]$result.passed) {
        throw "RC smoke phase reported passed=false: $Phase"
    }
    $phaseArtifacts = @(Get-ChildItem -LiteralPath $ProfileRoot -Recurse -File -Filter "phase-$Phase.json")
    if ($phaseArtifacts.Count -ne 1) { throw "RC smoke phase artifact is missing or ambiguous: $Phase" }
    return [ordered]@{
        phase = $Phase
        exit_code = $process.ExitCode
        marker = $result
        phase_artifact_sha256 = Get-Sha256 $phaseArtifacts[0].FullName
        godot_log_sha256 = Get-Sha256 $godotLog
        process_log_sha256 = Get-Sha256 $processLog
    }
}

if ($resolvedOutput -eq $allowedRoot -or
    -not $resolvedOutput.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must stay under artifacts\rc.'
}
$godot = (Resolve-Path -LiteralPath $GodotPath).Path
if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) { throw 'Godot executable is missing.' }
$godotVersion = Get-GodotVersion $godot
if ($godotVersion -notmatch '^4\.7') {
    throw "Godot 4.7 is required; found $godotVersion"
}
$godotSha256 = Get-Sha256 $godot

Assert-SourceIdentity
$gitCommit = [string](Invoke-Git @('rev-parse', '--verify', 'HEAD') | Select-Object -First 1)
if ($gitCommit -notmatch '^[0-9a-f]{40}$') { throw 'git HEAD is not a full commit SHA.' }

$candidateFile = Resolve-RepoFile $CandidatePath 'CandidatePath'
$pinnedCandidateFile = Resolve-RepoFile $PinnedProductionCandidatePath 'PinnedProductionCandidatePath'
$screeningFile = Resolve-RepoFile $FrozenScreeningPath 'FrozenScreeningPath'
$tier2File = Resolve-RepoFile $Tier2EvidencePath 'Tier2EvidencePath'
$nulFile = Resolve-RepoFile $NulEvidencePath 'NulEvidencePath'
$candidate = Read-Json $candidateFile 'candidate'
$pinnedCandidate = Read-Json $pinnedCandidateFile 'pinned production candidate'
$screening = Read-Json $screeningFile 'frozen 3k screening'
$tier2 = Read-Json $tier2File 'tier2 evidence'
$nulEvidence = Read-Json $nulFile 'NUL equivalence evidence'
$screeningSha256 = Get-Sha256 $screeningFile
if ([string]$screening.gate -ne 'PASS' -or [int]$screening.strategy_seed_case_count -ne 3000) {
    throw 'Frozen screening must be the PASS 3k artifact.'
}
if ([string]$candidate.candidate_id -ne [string]$screening.candidate_id -or
    [string]$candidate.content_version -ne [string]$screening.content_version -or
    [string]$candidate.tune_digest -ne [string]$screening.tune_digest) {
    throw 'Candidate and frozen screening identity do not match.'
}
if ([string]$screening.manifest_digest -notmatch '^[0-9a-f]{64}$') {
    throw 'Frozen screening canonical manifest digest is invalid.'
}
if ([string]$pinnedCandidate.candidate_id -ne [string]$screening.candidate_id -or
    [string]$pinnedCandidate.content_version -ne [string]$screening.content_version -or
    [string]$pinnedCandidate.manifest_digest -ne [string]$screening.manifest_digest -or
    [string]$pinnedCandidate.tune_digest -ne [string]$screening.tune_digest -or
    @($pinnedCandidate.tune_entries).Count -lt 1) {
    throw 'Pinned production candidate does not match the frozen screening identity.'
}
if ([string]$tier2.candidate_id -ne [string]$candidate.candidate_id -or
    [string]$tier2.source_sha256 -ne $screeningSha256 -or
    -not [bool]$tier2.all_sources_match) {
    throw 'Tier2 evidence does not pass source reconciliation.'
}
if ([string]$nulEvidence.candidate_id -ne [string]$candidate.candidate_id -or
    [string]$nulEvidence.frozen_artifact_sha256 -ne $screeningSha256 -or
    [int]$nulEvidence.case_count -ne 24 -or
    [int]$nulEvidence.digest_mismatch_count -ne 0 -or
    [int]$nulEvidence.unexpected_nul_warning_count -ne 0 -or
    -not [bool]$nulEvidence.passed) {
    throw 'NUL equivalence evidence reported passed=false.'
}

New-Item -ItemType Directory -Force -Path $allowedRoot | Out-Null
if (Test-Path -LiteralPath $resolvedOutput) { Remove-Item -LiteralPath $resolvedOutput -Recurse -Force }
New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null

$sourceManifestPath = Join-Path $allowedRoot 'source-manifest.json'
$sourceManifest = [ordered]@{
    schema_version = 1
    kind = 'balance-phase0-source-manifest'
    git_commit = $gitCommit
    content_version = [string]$candidate.content_version
    tune_digest = [string]$candidate.tune_digest
    candidate_id = [string]$candidate.candidate_id
    canonical_manifest_digest = [string]$screening.manifest_digest
    pinned_production_candidate = [ordered]@{
        path = $PinnedProductionCandidatePath.Replace('\', '/')
        sha256 = Get-Sha256 $pinnedCandidateFile
        manifest_digest = [string]$pinnedCandidate.manifest_digest
    }
    frozen_source_digest = [string]$screening.source_freeze_digest
    godot_version = $godotVersion
    godot_executable_sha256 = $godotSha256
    frozen_3k = [ordered]@{ path = $FrozenScreeningPath.Replace('\', '/'); sha256 = $screeningSha256 }
    tier2_evidence = [ordered]@{ path = $Tier2EvidencePath.Replace('\', '/'); sha256 = Get-Sha256 $tier2File }
    nul_equivalence_evidence = [ordered]@{ path = $NulEvidencePath.Replace('\', '/'); sha256 = Get-Sha256 $nulFile }
    generated_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}
Write-JsonAtomic $sourceManifest $sourceManifestPath
$sourceManifestSha256 = Get-Sha256 $sourceManifestPath

Invoke-TestSuite -Suite All -Godot $godot
Assert-SourceIdentity -ExpectedCommit $gitCommit
$runnerExecution = Join-Path $repoRoot 'artifacts\test\runner-execution.json'
$allArchive = Join-Path $allowedRoot 'final-all-runner-execution.json'
$allArchiveHash = Copy-SealedArtifact $runnerExecution $allArchive
$allResult = Read-Json $allArchive 'fresh All runner execution'
if ([string]$allResult.suite -ne 'All' -or [int]$allResult.exit_code -ne 0) { throw 'Fresh All runner evidence is invalid.' }

$standardStepNames = @('Import', 'Smoke', 'Gut', 'Content', 'Canonical', 'Combat', 'Expedition', 'Spec')
$stepEvidence = New-Object System.Collections.Generic.List[object]
foreach ($stepName in $standardStepNames) {
    $matches = @($allResult.runs | Where-Object { [string]$_.name -eq $stepName })
    if ($matches.Count -ne 1 -or [int]$matches[0].exit_code -ne 0) {
        throw "Fresh All step is missing, duplicated, or failed: $stepName"
    }
    $stepEvidence.Add([ordered]@{
        name = $stepName
        exit_code = 0
        started_at_utc = [string]$matches[0].started_at_utc
        finished_at_utc = [string]$matches[0].finished_at_utc
    })
}
$contractExpected = [ordered]@{
    RunnerContractPass = 0; RunnerContractPause = 0; RunnerContractAssertion = 2
    RunnerContractPushError = 2; RunnerContractEngineError = 2; RunnerContractEngineOrphan = 2
    RunnerContractZeroTests = 3; RunnerContractInfrastructure = 3; RunnerContractTimeout = 124
    RunnerContractLoggerCleanup = 0; RunnerContractLoggerLeak = 3
}
$contractProbes = New-Object System.Collections.Generic.List[object]
foreach ($probeName in $contractExpected.Keys) {
    $probeMatches = @($allResult.runs | Where-Object { [string]$_.name -eq $probeName })
    if ($probeMatches.Count -ne 1 -or [int]$probeMatches[0].exit_code -ne [int]$contractExpected[$probeName]) {
        throw "Fresh All RunnerContract probe did not match its expected exit: $probeName"
    }
    $contractProbes.Add([ordered]@{
        name = $probeName
        expected_exit_code = [int]$contractExpected[$probeName]
        actual_exit_code = [int]$probeMatches[0].exit_code
    })
}
$stepEvidence.Insert(1, [ordered]@{ name = 'RunnerContract'; exit_code = 0; probes = $contractProbes.ToArray() })
if ($stepEvidence.Count -ne 9) { throw 'Fresh All compact evidence must contain exactly nine runner steps.' }

$allLogRoot = Join-Path $allowedRoot 'final-all-logs'
if (Test-Path -LiteralPath $allLogRoot) { Remove-Item -LiteralPath $allLogRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $allLogRoot | Out-Null
$testArtifactRoot = Join-Path $repoRoot 'artifacts\test'
$requiredLogNames = @(
    'import.godot.log', 'smoke.godot.log', 'gut.godot.log', 'content.godot.log',
    'canonical.godot.log', 'combat.godot.log', 'expedition.godot.log', 'spec.godot.log'
)
$allLogs = New-Object System.Collections.Generic.List[IO.FileInfo]
foreach ($logName in $requiredLogNames) {
    $logPath = Join-Path $testArtifactRoot $logName
    if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { throw "Fresh All log is missing: $logName" }
    $allLogs.Add((Get-Item -LiteralPath $logPath))
}
$contractLogs = @(Get-ChildItem -LiteralPath $testArtifactRoot -File -Filter 'runnercontract*.godot.log')
if ($contractLogs.Count -ne $contractExpected.Count) {
    throw "Fresh All RunnerContract log count mismatch: expected $($contractExpected.Count), found $($contractLogs.Count)."
}
foreach ($contractLog in $contractLogs) { $allLogs.Add($contractLog) }
$archivedLogs = New-Object System.Collections.Generic.List[object]
$nulWarningCount = 0
foreach ($log in @($allLogs.ToArray() | Sort-Object Name)) {
    $destination = Join-Path $allLogRoot $log.Name
    $hash = Copy-SealedArtifact $log.FullName $destination
    $logText = Get-Content -Raw -Encoding UTF8 -LiteralPath $destination
    $fileNulCount = [regex]::Matches($logText, 'Unexpected NUL character', [Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
    $nulWarningCount += $fileNulCount
    $archivedLogs.Add([ordered]@{ file = $log.Name; sha256 = $hash; nul_warning_count = $fileNulCount })
}
$gutXmlSource = Join-Path $testArtifactRoot 'gut.xml'
$gutXmlArchive = Join-Path $allLogRoot 'gut.xml'
$gutXmlHash = Copy-SealedArtifact $gutXmlSource $gutXmlArchive
try { [xml]$gutDocument = Get-Content -Raw -Encoding UTF8 -LiteralPath $gutXmlArchive }
catch { throw 'Fresh All gut.xml is invalid XML.' }
$gutRoot = $gutDocument.SelectSingleNode('/testsuites')
if ($null -eq $gutRoot) { throw 'Fresh All gut.xml is missing the testsuites root.' }
$gutStats = [ordered]@{
    tests = [int]$gutRoot.GetAttribute('tests')
    assertions = [int]$gutRoot.GetAttribute('assertions')
    failures = [int]$gutRoot.GetAttribute('failures')
    errors = [int]$gutRoot.GetAttribute('errors')
    orphans = [int]$gutRoot.GetAttribute('orphans')
}
if ($gutStats.tests -lt 1 -or $gutStats.assertions -lt 1 -or
    $gutStats.failures -ne 0 -or $gutStats.errors -ne 0 -or $gutStats.orphans -ne 0) {
    throw 'Fresh All GUT statistics are not a clean pass.'
}
if ($nulWarningCount -ne 0) { throw "Fresh All emitted $nulWarningCount Unexpected NUL character warnings." }
$allWrapperPath = Join-Path $allowedRoot 'final-all-evidence.json'
Write-JsonAtomic ([ordered]@{
    schema_version = 1; kind = 'balance-phase0-final-all'; passed = $true
    source_manifest_sha256 = $sourceManifestSha256
    runner_execution = [ordered]@{ file = 'final-all-runner-execution.json'; sha256 = $allArchiveHash }
    steps = $stepEvidence.ToArray()
    gut = [ordered]@{ file = 'final-all-logs/gut.xml'; sha256 = $gutXmlHash; statistics = $gutStats }
    nul_warning_count = $nulWarningCount
    logs = $archivedLogs.ToArray()
    finished_at_utc = [string]$allResult.finished_at_utc
}) $allWrapperPath

Invoke-TestSuite -Suite ExpeditionSoak -Godot $godot
Assert-SourceIdentity -ExpectedCommit $gitCommit
$soakRunnerArchive = Join-Path $allowedRoot 'expedition-soak-runner-execution.json'
$soakRunnerHash = Copy-SealedArtifact $runnerExecution $soakRunnerArchive
$soakSource = Join-Path $repoRoot 'artifacts\test\expedition-soak.json'
$soakArchive = Join-Path $allowedRoot 'expedition-soak-10000.json'
$soakHash = Copy-SealedArtifact $soakSource $soakArchive
$soakResult = Read-Json $soakArchive 'ExpeditionSoak 10k evidence'
if (-not [bool]$soakResult.passed -or [int]$soakResult.seed_count -ne 10000 -or @($soakResult.failures).Count -ne 0) {
    throw 'ExpeditionSoak evidence is not a clean 10k pass.'
}
$soakWrapperPath = Join-Path $allowedRoot 'expedition-soak-evidence.json'
Write-JsonAtomic ([ordered]@{
    schema_version = 1; kind = 'balance-phase0-expedition-soak'; passed = $true
    source_manifest_sha256 = $sourceManifestSha256
    runner_execution = [ordered]@{ file = 'expedition-soak-runner-execution.json'; sha256 = $soakRunnerHash }
    soak = [ordered]@{
        file = 'expedition-soak-10000.json'; sha256 = $soakHash
        seed_count = [int]$soakResult.seed_count
        case_count = [int]$soakResult.case_count
        pool_conservation_checks = [int]$soakResult.pool_conservation_checks
        deterministic_replay_count = [int]$soakResult.deterministic_replay_count
        build_operation_count = [int]$soakResult.build_operation_count
        failures = @($soakResult.failures)
    }
}) $soakWrapperPath

$exePath = Join-Path $resolvedOutput 'ExpeditionChess.exe'
$exportLog = Join-Path $allowedRoot 'export.log'
$exportArguments = '--headless --path "{0}" --log-file "{1}" --export-release "Windows Provisional RC" "{2}"' -f $repoRoot, $exportLog, $exePath
$exportProcess = Start-Process -FilePath $godot -ArgumentList $exportArguments -Wait -PassThru -WindowStyle Hidden
if ($exportProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exePath)) { throw 'Windows export failed.' }
$exportText = Get-Content -Raw -Encoding UTF8 -LiteralPath $exportLog
if ($exportText -match 'SCRIPT ERROR|Parse Error|ERROR:|CRASH|content bootstrap failed') { throw 'Windows export emitted a fatal engine error.' }
$pckPath = [IO.Path]::ChangeExtension($exePath, '.pck')
if (-not (Test-Path -LiteralPath $pckPath -PathType Leaf)) { throw 'Windows export did not produce a PCK.' }
Copy-Item -LiteralPath (Join-Path $repoRoot 'PLAYTEST.md') -Destination $resolvedOutput
Copy-Item -LiteralPath (Join-Path $repoRoot 'PLAYTEST-LICENSES.txt') -Destination $resolvedOutput

$smokeProfile = Join-Path $allowedRoot 'fresh-profile'
if (Test-Path -LiteralPath $smokeProfile) { Remove-Item -LiteralPath $smokeProfile -Recurse -Force }
New-Item -ItemType Directory -Force -Path $smokeProfile | Out-Null
$smokePhases = New-Object System.Collections.Generic.List[object]
$inventoryPath = Join-Path $allowedRoot 'pck-inventory.json'
$inventoryHash = ''
foreach ($phase in @('start-save', 'restart-terminal', 'restart-abandon-verify')) {
    $smokePhases.Add((Invoke-RcSmokePhase -Executable $exePath -Phase $phase -ProfileRoot $smokeProfile -TimeoutSeconds $SmokeTimeoutSeconds))
    if ($phase -eq 'start-save') {
        $runtimeInventories = @(Get-ChildItem -LiteralPath $smokeProfile -Recurse -File -Filter 'pck-inventory.json')
        if ($runtimeInventories.Count -ne 1) {
            throw "Exported runtime PCK inventory is missing or ambiguous; found $($runtimeInventories.Count)."
        }
        $inventoryHash = Copy-SealedArtifact $runtimeInventories[0].FullName $inventoryPath
        $inventory = Read-Json $inventoryPath 'runtime-mounted PCK inventory'
        if ([string]$inventory.source -ne 'runtime-mounted-res' -or
            [int]$inventory.file_count -lt 1 -or
            -not [bool]$inventory.passed -or
            $null -eq $inventory.PSObject.Properties['forbidden_entries'] -or
            $null -eq $inventory.PSObject.Properties['forbidden_entry_count'] -or
            [int]$inventory.forbidden_entry_count -ne 0 -or
            @($inventory.forbidden_entries).Count -ne 0) {
            throw "Runtime-mounted PCK inventory contains forbidden entries: $(@($inventory.forbidden_entries) -join ', ')"
        }
        $pinnedInventoryEntries = @($inventory.entries | Where-Object {
            [string]$_.logical_res_path -eq 'res://application/balance/production_balance_candidate.json'
        })
        if ($pinnedInventoryEntries.Count -ne 1) {
            throw "Runtime-mounted PCK inventory must contain exactly one pinned production candidate; found $($pinnedInventoryEntries.Count)."
        }
    }
}
if ([string]::IsNullOrWhiteSpace($inventoryHash)) { throw 'Runtime-mounted PCK inventory was not sealed.' }
Assert-SourceIdentity -ExpectedCommit $gitCommit
$reports = @(Get-ChildItem -LiteralPath $smokeProfile -Recurse -File -Filter 'session-*.json' |
    Where-Object { $_.DirectoryName.Replace('\', '/').EndsWith('/playtest_reports') })
if ($reports.Count -ne 2) { throw "RC smoke must produce exactly two playtest reports; found $($reports.Count)." }
$reportSampleRoot = Join-Path $allowedRoot 'report-samples'
if (Test-Path -LiteralPath $reportSampleRoot) { Remove-Item -LiteralPath $reportSampleRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $reportSampleRoot | Out-Null
$reportEvidence = @($reports | Sort-Object Name | ForEach-Object {
    $null = Read-Json $_.FullName 'RC smoke playtest report'
    $samplePath = Join-Path $reportSampleRoot $_.Name
    $sampleHash = Copy-SealedArtifact $_.FullName $samplePath
    [ordered]@{ file = "report-samples/$($_.Name)"; sha256 = $sampleHash }
})
$rcWrapperPath = Join-Path $allowedRoot 'rc-evidence.json'
Write-JsonAtomic ([ordered]@{
    schema_version = 1; kind = 'balance-phase0-rc'; passed = $true
    source_manifest_sha256 = $sourceManifestSha256
    executable_sha256 = Get-Sha256 $exePath
    pck_inventory_sha256 = $inventoryHash
    phases = $smokePhases.ToArray()
    reports = $reportEvidence
}) $rcWrapperPath

$zipPath = Join-Path $allowedRoot 'ExpeditionChess-g2-rc1-win64.zip'
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $resolvedOutput '*') -DestinationPath $zipPath
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $zipNames = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    $requiredTopLevel = @('ExpeditionChess.exe', 'ExpeditionChess.pck', 'PLAYTEST.md', 'PLAYTEST-LICENSES.txt')
    if ($zipNames.Count -ne $requiredTopLevel.Count) {
        throw "RC ZIP must contain exactly four top-level files; found $($zipNames.Count)."
    }
    foreach ($required in $requiredTopLevel) {
        if ($zipNames -notcontains $required) { throw "RC ZIP is missing required top-level entry: $required" }
    }
    if (@($zipNames | Where-Object { $_ -match '/' }).Count -ne 0) {
        throw 'RC ZIP contains an unexpected directory or non-top-level entry.'
    }
}
finally { $zip.Dispose() }
$zipDigest = Get-Sha256 $zipPath
$shaPath = $zipPath + '.sha256'
[IO.File]::WriteAllText($shaPath, "$zipDigest  $([IO.Path]::GetFileName($zipPath))`r`n", [Text.Encoding]::ASCII)
$shaReadBack = (Get-Content -Raw -Encoding ASCII -LiteralPath $shaPath).Trim()
if ($shaReadBack -ne "$zipDigest  $([IO.Path]::GetFileName($zipPath))" -or (Get-Sha256 $zipPath) -ne $zipDigest) {
    throw 'RC ZIP SHA-256 read-back failed.'
}

Write-Output $sourceManifestPath
Write-Output $allWrapperPath
Write-Output $soakWrapperPath
Write-Output $inventoryPath
Write-Output $rcWrapperPath
Write-Output $zipPath
Write-Output $shaPath
