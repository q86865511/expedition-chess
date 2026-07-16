[CmdletBinding()]
param(
    [ValidateSet('All', 'Toolchain', 'Import', 'Smoke', 'Gut', 'Content', 'Canonical', 'Combat', 'Soak', 'Spec', 'RunnerContract')]
    [string]$Suite = 'All',
    [string]$TestPath = '',
    [string]$Case = '',
    [string]$GodotPath = '',
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 180,
    [ValidateRange(1, 1000000)]
    [int]$SeedCount = 10000
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$artifactRoot = Join-Path $repoRoot 'artifacts\test'
$executionPath = Join-Path $artifactRoot 'runner-execution.json'
$runnerLockPath = Join-Path $artifactRoot '.runner.lock'
$startedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$runs = New-Object System.Collections.Generic.List[object]
$finalExitCode = 3
$failureMessage = $null
$runnerLockStream = $null
$ownsRunnerLock = $false

function ConvertTo-WindowsCommandLineArgument {
    param([AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashCount = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashCount * 2) + 1)))
            [void]$builder.Append('"')
            $backslashCount = 0
            continue
        }
        if ($backslashCount -gt 0) {
            [void]$builder.Append(('\' * $backslashCount))
            $backslashCount = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashCount -gt 0) {
        [void]$builder.Append(('\' * ($backslashCount * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Get-GutTreeHash {
    param([Parameter(Mandatory = $true)][string]$Root)

    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $relativePaths = New-Object System.Collections.Generic.List[string]
    $caseFolded = @{}
    foreach ($file in Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File) {
        $relative = $file.FullName.Substring($resolvedRoot.Length + 1).Replace('\', '/')
        if ($relative -match '[^\x00-\x7f]') {
            throw "GUT tree contains a non-ASCII path: $relative"
        }
        $folded = $relative.ToLowerInvariant()
        if ($caseFolded.ContainsKey($folded)) {
            throw "GUT tree contains an ASCII case-fold collision: $relative"
        }
        $caseFolded[$folded] = $relative
        $relativePaths.Add($relative)
    }

    $paths = $relativePaths.ToArray()
    $comparison = [System.Comparison[string]]{
        param([string]$left, [string]$right)
        $primary = [StringComparer]::Ordinal.Compare($left.ToLowerInvariant(), $right.ToLowerInvariant())
        if ($primary -ne 0) { return $primary }
        return [StringComparer]::Ordinal.Compare($left, $right)
    }
    [Array]::Sort($paths, $comparison)

    $sha = [Security.Cryptography.SHA256]::Create()
    $utf8 = New-Object Text.UTF8Encoding($false)
    $nul = [byte[]]@(0)
    foreach ($relative in $paths) {
        $pathBytes = $utf8.GetBytes($relative)
        [void]$sha.TransformBlock($pathBytes, 0, $pathBytes.Length, $pathBytes, 0)
        [void]$sha.TransformBlock($nul, 0, 1, $nul, 0)
        $fileBytes = [IO.File]::ReadAllBytes((Join-Path $resolvedRoot $relative.Replace('/', '\')))
        if ($fileBytes.Length -gt 0) {
            [void]$sha.TransformBlock($fileBytes, 0, $fileBytes.Length, $fileBytes, 0)
        }
        [void]$sha.TransformBlock($nul, 0, 1, $nul, 0)
    }
    [void]$sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
    return (($sha.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Resolve-GodotExecutable {
    if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
        return [IO.Path]::GetFullPath($GodotPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
        return [IO.Path]::GetFullPath($env:GODOT_BIN)
    }
    throw 'Godot executable not provided. Use -GodotPath or GODOT_BIN.'
}

function Test-Toolchain {
    param([string]$Executable, [string]$LockPathOverride = '')

    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        return [pscustomobject]@{ ExitCode = 3; Message = "Godot executable not found: $Executable" }
    }
    $lockPath = if ([string]::IsNullOrWhiteSpace($LockPathOverride)) {
        Join-Path $repoRoot 'toolchain.lock.json'
    }
    else {
        [IO.Path]::GetFullPath($LockPathOverride)
    }
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        return [pscustomobject]@{ ExitCode = 3; Message = 'toolchain.lock.json is missing.' }
    }
    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $actualVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($Executable).ProductVersion
    $actualGodotHash = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash.ToLowerInvariant()
    $gutRoot = Join-Path $repoRoot 'addons\gut'
    if (-not (Test-Path -LiteralPath $gutRoot -PathType Container)) {
        return [pscustomobject]@{ ExitCode = 3; Message = 'Vendored GUT directory is missing.' }
    }
    $actualGutHash = Get-GutTreeHash -Root $gutRoot
    $gutUtilsText = Get-Content -LiteralPath (Join-Path $gutRoot 'utils.gd') -Raw -Encoding UTF8
    $gutVersionMatch = [regex]::Match($gutUtilsText, "VersionNumbers\.new\(\s*'([^']+)'")
    if (-not $gutVersionMatch.Success) {
        return [pscustomobject]@{ ExitCode = 3; Message = 'Unable to read vendored GUT version.' }
    }
    $actualGutVersion = $gutVersionMatch.Groups[1].Value
    $messages = New-Object System.Collections.Generic.List[string]
    if ([string]$lock.gut.source -cne 'vendored') {
        $messages.Add("GUT source mismatch: expected vendored, got $($lock.gut.source)")
    }
    if ($actualVersion -cne [string]$lock.godot.version) {
        $messages.Add("Godot version mismatch: expected $($lock.godot.version), got $actualVersion")
    }
    if ($actualGodotHash -cne [string]$lock.godot.sha256) {
        $messages.Add("Godot SHA-256 mismatch: expected $($lock.godot.sha256), got $actualGodotHash")
    }
    if ($actualGutHash -cne [string]$lock.gut.tree_sha256) {
        $messages.Add("GUT tree SHA-256 mismatch: expected $($lock.gut.tree_sha256), got $actualGutHash")
    }
    if ($actualGutVersion -cne [string]$lock.gut.version) {
        $messages.Add("GUT version mismatch: expected $($lock.gut.version), got $actualGutVersion")
    }
    if ($messages.Count -gt 0) {
        return [pscustomobject]@{ ExitCode = 2; Message = ($messages -join "`n") }
    }
    return [pscustomobject]@{
        ExitCode = 0
        Message = 'Toolchain lock verified.'
        GodotVersion = $actualVersion
        GodotSha256 = $actualGodotHash
        GutVersion = $actualGutVersion
        GutTreeSha256 = $actualGutHash
        GutFileCount = (Get-ChildItem -LiteralPath $gutRoot -Recurse -File).Count
    }
}

function Invoke-GodotChild {
    param(
        [string]$Executable,
        [string]$Name,
        [string[]]$Arguments,
        [int]$TimeoutOverrideSeconds = 0
    )

    $argumentLine = (($Arguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument -Value $_ }) -join ' ')
    $runStarted = [DateTime]::UtcNow
    $process = Start-Process -FilePath $Executable -ArgumentList $argumentLine -PassThru -WindowStyle Hidden
    $effectiveTimeoutSeconds = if ($TimeoutOverrideSeconds -gt 0) {
        $TimeoutOverrideSeconds
    }
    else {
        $TimeoutSeconds
    }
    $completed = $process.WaitForExit($effectiveTimeoutSeconds * 1000)
    if (-not $completed) {
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        try { $process.WaitForExit(10000) | Out-Null } catch {}
        $exitCode = 124
    }
    else {
        $nativeCode = $process.ExitCode
        $exitCode = if ($nativeCode -in @(0, 2, 3)) { $nativeCode } else { 3 }
    }
    $run = [pscustomobject]@{
        name = $Name
        exit_code = $exitCode
        started_at_utc = $runStarted.ToString('yyyy-MM-ddTHH:mm:ssZ')
        finished_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        arguments = $Arguments
    }
    $runs.Add($run)
    return $exitCode
}

function Invoke-RunnerScript {
    param(
        [string]$Executable,
        [string]$Name,
        [string]$ScriptPath,
        [string[]]$UserArguments = @(),
        [int]$TimeoutOverrideSeconds = 0
    )

    $logPath = Join-Path $artifactRoot ($Name.ToLowerInvariant() + '.godot.log')
    $arguments = @('--headless', '--path', $repoRoot, '--log-file', $logPath, '--script', $ScriptPath)
    if ($UserArguments.Count -gt 0) {
        $arguments += '--'
        $arguments += $UserArguments
    }
    return Invoke-GodotChild -Executable $Executable -Name $Name -Arguments $arguments -TimeoutOverrideSeconds $TimeoutOverrideSeconds
}

function Test-ImportResult {
    param([int]$ChildExitCode, [string]$LogPath)

    if ($ChildExitCode -ne 0) { return $ChildExitCode }
    $classCache = Join-Path $repoRoot '.godot\global_script_class_cache.cfg'
    if (-not (Test-Path -LiteralPath $classCache -PathType Leaf)) { return 3 }
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return 3 }
    $logText = Get-Content -LiteralPath $LogPath -Raw -Encoding UTF8
    if ($logText -match '(?m)^(SCRIPT ERROR:|ERROR: (Failed|Attempt|Could not)|.*Parse Error:)') { return 3 }
    return 0
}

function Invoke-RunnerContractProbe {
    param(
        [string]$Executable,
        [string]$ProbeName,
        [string]$TestPath,
        [int]$ExpectedExitCode,
        [int]$ProbeTimeoutSeconds = 0,
        [bool]$RequireJunit = $true,
        [string[]]$AdditionalUserArguments = @()
    )

    $sharedJunit = Join-Path $artifactRoot 'gut.xml'
    if (Test-Path -LiteralPath $sharedJunit -PathType Leaf) {
        Remove-Item -LiteralPath $sharedJunit -Force
    }
    $userArguments = @('--test-path', $TestPath)
    $userArguments += $AdditionalUserArguments
    $actualExitCode = Invoke-RunnerScript `
        -Executable $Executable `
        -Name ("RunnerContract" + $ProbeName) `
        -ScriptPath 'res://tests/runners/gut_runner.gd' `
        -UserArguments $userArguments `
        -TimeoutOverrideSeconds $ProbeTimeoutSeconds
    if ($actualExitCode -ne $ExpectedExitCode) {
        return [pscustomobject]@{
            ExitCode = 2
            Message = "Runner contract probe $ProbeName expected $ExpectedExitCode, got $actualExitCode."
        }
    }
    if ($RequireJunit) {
        if (-not (Test-Path -LiteralPath $sharedJunit -PathType Leaf)) {
            return [pscustomobject]@{
                ExitCode = 2
                Message = "Runner contract probe $ProbeName did not produce JUnit XML."
            }
        }
        try {
            [xml]$document = Get-Content -LiteralPath $sharedJunit -Raw -Encoding UTF8
            $root = $document.SelectSingleNode('/testsuites')
            if ($null -eq $root) {
                throw 'testsuites root is missing.'
            }
            $failures = [int]$root.GetAttribute('failures')
            $errors = [int]$root.GetAttribute('errors')
            $orphans = [int]$root.GetAttribute('orphans')
            if ($ExpectedExitCode -eq 0 -and ($failures + $errors + $orphans) -ne 0) {
                throw 'success probe reported failures/errors/orphans.'
            }
            if ($ExpectedExitCode -eq 2 -and ($failures + $errors + $orphans) -le 0) {
                throw 'test-failure probe did not report a JUnit failure/error/orphan.'
            }
            Copy-Item -LiteralPath $sharedJunit -Destination (Join-Path $artifactRoot ("runner-contract-" + $ProbeName.ToLowerInvariant() + '.xml')) -Force
        }
        catch {
            return [pscustomobject]@{
                ExitCode = 2
                Message = "Runner contract probe $ProbeName JUnit validation failed: $($_.Exception.Message)"
            }
        }
    }
    elseif (Test-Path -LiteralPath $sharedJunit -PathType Leaf) {
        return [pscustomobject]@{
            ExitCode = 2
            Message = "Runner contract probe $ProbeName published stale/partial JUnit XML."
        }
    }
    return [pscustomobject]@{ ExitCode = 0; Message = "Runner contract probe $ProbeName passed." }
}

function Test-RunnerContract {
    param([string]$Executable)

    $toolchainContract = Test-ToolchainNegativeContracts -Executable $Executable
    if ($toolchainContract.ExitCode -ne 0) {
        return $toolchainContract
    }

    $probes = @(
        [pscustomobject]@{ Name = 'Pass'; Path = 'res://runner_contract/fixtures/pass'; Expected = 0; Timeout = 0; Junit = $true; Extra = @() },
        [pscustomobject]@{ Name = 'Pause'; Path = 'res://runner_contract/fixtures/pause'; Expected = 0; Timeout = 0; Junit = $true; Extra = @() },
        [pscustomobject]@{ Name = 'Assertion'; Path = 'res://runner_contract/fixtures/assertion_failure'; Expected = 2; Timeout = 0; Junit = $true; Extra = @() },
        [pscustomobject]@{ Name = 'PushError'; Path = 'res://runner_contract/fixtures/push_error'; Expected = 2; Timeout = 0; Junit = $true; Extra = @() },
        [pscustomobject]@{ Name = 'EngineError'; Path = 'res://runner_contract/fixtures/test_engine_error.gd'; Expected = 2; Timeout = 0; Junit = $true; Extra = @() },
        [pscustomobject]@{ Name = 'EngineOrphan'; Path = 'res://runner_contract/fixtures/engine_orphan'; Expected = 2; Timeout = 0; Junit = $true; Extra = @() },
        [pscustomobject]@{ Name = 'ZeroTests'; Path = 'res://runner_contract/fixtures/zero_tests'; Expected = 3; Timeout = 0; Junit = $false; Extra = @() },
        [pscustomobject]@{ Name = 'Infrastructure'; Path = 'res://runner_contract/fixtures/pass'; Expected = 3; Timeout = 0; Junit = $false; Extra = @('--contract-force-infrastructure-error') },
        [pscustomobject]@{ Name = 'Timeout'; Path = 'res://runner_contract/fixtures/timeout'; Expected = 124; Timeout = 1; Junit = $false; Extra = @() },
        [pscustomobject]@{ Name = 'LoggerCleanup'; Path = 'res://runner_contract/fixtures/pass'; Expected = 0; Timeout = 0; Junit = $true; Extra = @() },
        [pscustomobject]@{ Name = 'LoggerLeak'; Path = 'res://runner_contract/fixtures/pass'; Expected = 3; Timeout = 0; Junit = $true; Extra = @('--contract-simulate-logger-leak') }
    )
    foreach ($probe in $probes) {
        $result = Invoke-RunnerContractProbe `
            -Executable $Executable `
            -ProbeName $probe.Name `
            -TestPath $probe.Path `
            -ExpectedExitCode $probe.Expected `
            -ProbeTimeoutSeconds $probe.Timeout `
            -RequireJunit $probe.Junit `
            -AdditionalUserArguments $probe.Extra
        if ($result.ExitCode -ne 0) {
            return $result
        }
    }
    return [pscustomobject]@{
        ExitCode = 0
        Message = 'Runner contract verified pass/assert/push/engine error/orphan/pause/logger cleanup/infra/timeout behavior.'
    }
}

function Test-ToolchainNegativeContracts {
    param([string]$Executable)

    $sourceLockPath = Join-Path $repoRoot 'toolchain.lock.json'
    $temporaryLockPath = Join-Path $artifactRoot 'runner-contract-toolchain.lock.json'
    $mutations = @(
        [pscustomobject]@{ Section = 'godot'; Field = 'version'; Value = '0.invalid' },
        [pscustomobject]@{ Section = 'godot'; Field = 'sha256'; Value = (('0' * 64) -join '') },
        [pscustomobject]@{ Section = 'gut'; Field = 'version'; Value = '0.invalid' },
        [pscustomobject]@{ Section = 'gut'; Field = 'tree_sha256'; Value = (('0' * 64) -join '') },
        [pscustomobject]@{ Section = 'gut'; Field = 'source'; Value = 'floating' }
    )
    try {
        foreach ($mutation in $mutations) {
            $lock = Get-Content -LiteralPath $sourceLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $lock.($mutation.Section).($mutation.Field) = $mutation.Value
            [IO.File]::WriteAllText(
                $temporaryLockPath,
                ($lock | ConvertTo-Json -Depth 8),
                (New-Object Text.UTF8Encoding($false))
            )
            $result = Test-Toolchain -Executable $Executable -LockPathOverride $temporaryLockPath
            if ([int]$result.ExitCode -ne 2) {
                return [pscustomobject]@{
                    ExitCode = 2
                    Message = "Toolchain mutation $($mutation.Section).$($mutation.Field) expected exit 2, got $($result.ExitCode)."
                }
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryLockPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryLockPath -Force
        }
    }
    return [pscustomobject]@{
        ExitCode = 0
        Message = 'Toolchain lock rejects every version/hash/source mutation.'
    }
}

function Write-ExecutionArtifact {
    param([int]$ExitCode, [string]$Message, [object]$Toolchain)

    New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
    $payload = [ordered]@{
        schema_version = 1
        suite = $Suite
        exit_code = $ExitCode
        message = $Message
        started_at_utc = $startedAt
        finished_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        toolchain = $Toolchain
        runs = $runs.ToArray()
    }
    $temporaryPath = $executionPath + '.tmp'
    [IO.File]::WriteAllText($temporaryPath, ($payload | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporaryPath -Destination $executionPath -Force
    $roundTrip = Get-Content -LiteralPath $executionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$roundTrip.exit_code -ne $ExitCode) {
        throw 'runner-execution.json read-back validation failed.'
    }
    if ($Suite -eq 'All') {
        Write-FoundationAcceptanceArtifact -AllExitCode $ExitCode -Toolchain $Toolchain
    }
    if ($Suite -in @('All', 'Soak')) {
        Write-CombatAcceptanceArtifact -Toolchain $Toolchain
    }
}

function Get-FoundationEvidenceEvaluation {
    param([object]$Toolchain)

    $observed = @{}
    $observed['toolchain:locked'] = (
        $null -ne $Toolchain -and
        [int]$Toolchain.ExitCode -eq 0 -and
        [string]$Toolchain.GodotVersion -eq '4.7.stable.official' -and
        [string]$Toolchain.GodotSha256 -eq 'b2ca888d5115a6cedee564764a2ee494a625f2ec2edbabd010fe33c9a88a6bf8' -and
        [string]$Toolchain.GutVersion -eq '9.7.1' -and
        [string]$Toolchain.GutTreeSha256 -eq '94cfb2346fa189bb358a499179161cabf6c3602485ce7f592683d5d3bb7f18d2'
    )

    $runExits = @{}
    foreach ($run in $runs) {
        $runExits[[string]$run.name] = [int]$run.exit_code
    }
    $observed['runner:import'] = $runExits.ContainsKey('Import') -and $runExits['Import'] -eq 0
    $runnerContractExits = [ordered]@{
        RunnerContractPass = 0
        RunnerContractPause = 0
        RunnerContractAssertion = 2
        RunnerContractPushError = 2
        RunnerContractEngineError = 2
        RunnerContractEngineOrphan = 2
        RunnerContractZeroTests = 3
        RunnerContractInfrastructure = 3
        RunnerContractTimeout = 124
        RunnerContractLoggerCleanup = 0
        RunnerContractLoggerLeak = 3
    }
    $runnerContractVerified = $true
    foreach ($name in $runnerContractExits.Keys) {
        if (-not $runExits.ContainsKey($name) -or $runExits[$name] -ne $runnerContractExits[$name]) {
            $runnerContractVerified = $false
        }
    }
    $observed['runner:contract'] = $runnerContractVerified

    $jsonArtifacts = @{}
    foreach ($artifactName in @('smoke.json', 'content-validation.json', 'canonical.json', 'spec-contract.json')) {
        $artifactPath = Join-Path $artifactRoot $artifactName
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            $jsonArtifacts[$artifactName] = $null
            continue
        }
        try {
            $jsonArtifacts[$artifactName] = Get-Content -LiteralPath $artifactPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            $jsonArtifacts[$artifactName] = $null
        }
    }
    $scopeRequirements = [ordered]@{
        'smoke:minimal_boot' = @('smoke.json', 'minimal_boot')
        'smoke:autoload_set' = @('smoke.json', 'autoload_set')
        'canonical:U64Bits/stable-id' = @('canonical.json', 'U64Bits/stable-id')
        'canonical:RuntimeKeyCodec-v1' = @('canonical.json', 'RuntimeKeyCodec-v1')
        'canonical:PCG32/RNG-v1' = @('canonical.json', 'PCG32/RNG-v1')
        'canonical:CanonicalBattleCodec-v1' = @('canonical.json', 'CanonicalBattleCodec-v1')
        'content:valid_fixture' = @('content-validation.json', 'content_validation_valid_fixture')
        'content:population_recompute' = @('content-validation.json', 'content_validation_population_recompute')
        'content:mutation_matrix' = @('content-validation.json', 'content_validation_mutation.stable_id')
        'content:alias_migration' = @('content-validation.json', 'content_registry_alias_receipt_migration')
        'content:tombstone_preservation' = @('content-validation.json', 'content_registry_required_tombstone_preservation')
        'content:generation_pinning' = @('content-validation.json', 'content_registry_generation_pinning')
        'spec:source_contracts' = @('spec-contract.json', 'source_contracts')
        'spec:manifest' = @('spec-contract.json', 'manifest')
    }
    foreach ($evidenceKey in $scopeRequirements.Keys) {
        $requirement = $scopeRequirements[$evidenceKey]
        $artifact = $jsonArtifacts[$requirement[0]]
        $observed[$evidenceKey] = (
            $null -ne $artifact -and
            [bool]$artifact.passed -and
            @($artifact.completed_scopes) -contains $requirement[1]
        )
    }

    $gutCases = @{}
    $gutPath = Join-Path $artifactRoot 'gut.xml'
    if (Test-Path -LiteralPath $gutPath -PathType Leaf) {
        try {
            [xml]$gutDocument = Get-Content -LiteralPath $gutPath -Raw -Encoding UTF8
            $gutRoot = $gutDocument.SelectSingleNode('/testsuites')
            if ($null -ne $gutRoot -and
                [int]$gutRoot.GetAttribute('failures') -eq 0 -and
                [int]$gutRoot.GetAttribute('errors') -eq 0 -and
                [int]$gutRoot.GetAttribute('orphans') -eq 0) {
                foreach ($testCase in $gutDocument.SelectNodes('//testcase')) {
                    if ([string]$testCase.GetAttribute('status') -eq 'pass') {
                        $gutCases[[string]$testCase.GetAttribute('name')] = $true
                    }
                }
            }
        }
        catch {
            $gutCases = @{}
        }
    }
    $requiredGutCases = @(
        'test_schema_zero_to_one_is_idempotent',
        'test_invalid_main_loads_backup_and_repairs_without_moving_only_backup_first',
        'test_existing_committed_copy_survives_each_second_save_fault',
        'test_all_declared_app_edges_are_accepted_with_repository_proofs',
        'test_declared_run_phase_edge_matrix',
        'test_schema_two_round_trip_is_byte_identical',
        'test_alias_probe_compiles_new_pinned_receipt',
        'test_required_tombstone_never_guesses_safe_replacement',
        'test_receipt_failure_preserves_profile_and_marks_run_incompatible',
        'test_valid_fixture_and_deep_clone_isolation',
        'test_view_projection_does_not_share_nested_state',
        'test_every_u64_boundary_uses_fixed_lowercase_hex',
        'test_every_initial_save_storage_invocation_can_be_faulted',
        'test_same_thread_reentrant_save_and_load_are_busy_before_second_storage_call',
        'test_registry_adapter_loads_matching_run_and_session_holds_generation_lease',
        'test_success_commits_then_swaps_and_publishes_once',
        'test_storage_and_final_readback_failures_never_publish_draft',
        'test_all_resolution_kinds_preserve_full_retry_identity'
    )
    foreach ($testName in $requiredGutCases) {
        $observed['gut:' + $testName] = $gutCases.ContainsKey($testName)
    }

    $rules = [ordered]@{
        'AC-025' = @('gut:test_schema_zero_to_one_is_idempotent')
        'AC-026' = @('gut:test_invalid_main_loads_backup_and_repairs_without_moving_only_backup_first', 'gut:test_existing_committed_copy_survives_each_second_save_fault')
        'AC-036' = @('toolchain:locked', 'runner:import', 'runner:contract')
        'AC-039' = @('smoke:minimal_boot', 'gut:test_all_declared_app_edges_are_accepted_with_repository_proofs', 'gut:test_declared_run_phase_edge_matrix')
        'AC-040' = @('gut:test_schema_two_round_trip_is_byte_identical', 'spec:source_contracts')
        'AC-051' = @('content:alias_migration', 'gut:test_alias_probe_compiles_new_pinned_receipt')
        'AC-052' = @('content:tombstone_preservation', 'gut:test_required_tombstone_never_guesses_safe_replacement')
        'AC-054' = @('spec:source_contracts')
        'AC-055' = @('gut:test_valid_fixture_and_deep_clone_isolation', 'gut:test_view_projection_does_not_share_nested_state', 'gut:test_schema_two_round_trip_is_byte_identical')
        'AC-063' = @('canonical:U64Bits/stable-id', 'canonical:PCG32/RNG-v1', 'gut:test_every_u64_boundary_uses_fixed_lowercase_hex')
        'AC-064' = @('canonical:CanonicalBattleCodec-v1')
        'AC-068' = @('smoke:autoload_set', 'spec:source_contracts')
        'AC-069' = @('gut:test_every_initial_save_storage_invocation_can_be_faulted', 'gut:test_existing_committed_copy_survives_each_second_save_fault', 'gut:test_same_thread_reentrant_save_and_load_are_busy_before_second_storage_call')
        'AC-070' = @('gut:test_receipt_failure_preserves_profile_and_marks_run_incompatible')
        'AC-078' = @('content:generation_pinning', 'gut:test_registry_adapter_loads_matching_run_and_session_holds_generation_lease')
        'AC-016' = @('content:valid_fixture', 'content:mutation_matrix')
        'AC-027' = @('canonical:PCG32/RNG-v1')
        'AC-034' = @('content:valid_fixture', 'content:population_recompute')
        'AC-047' = @('content:valid_fixture', 'content:mutation_matrix')
        'AC-065' = @('gut:test_success_commits_then_swaps_and_publishes_once', 'gut:test_storage_and_final_readback_failures_never_publish_draft')
        'AC-073' = @('canonical:RuntimeKeyCodec-v1', 'gut:test_all_resolution_kinds_preserve_full_retry_identity')
        'AC-075' = @('content:generation_pinning', 'canonical:CanonicalBattleCodec-v1')
    }
    $evaluations = @{}
    $allMissing = New-Object System.Collections.Generic.List[string]
    foreach ($acceptanceId in $rules.Keys) {
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($evidenceKey in @($rules[$acceptanceId])) {
            if (-not $observed.ContainsKey($evidenceKey) -or -not [bool]$observed[$evidenceKey]) {
                $missing.Add($evidenceKey)
                $allMissing.Add($acceptanceId + ':' + $evidenceKey)
            }
        }
        $evaluations[$acceptanceId] = [pscustomobject]@{
            Verified = ($missing.Count -eq 0)
            Required = @($rules[$acceptanceId])
            Missing = $missing.ToArray()
        }
    }
    return [pscustomobject]@{
        Verified = ($allMissing.Count -eq 0)
        Evaluations = $evaluations
        Missing = $allMissing.ToArray()
    }
}

function Test-FoundationEvidenceNegativeContract {
    param([object]$Toolchain)

    $path = Join-Path $artifactRoot 'canonical.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Verified = $false; Message = 'canonical.json is missing for evidence mutation.' }
    }
    $original = [IO.File]::ReadAllText($path, (New-Object Text.UTF8Encoding($false, $true)))
    $detected = $false
    try {
        $mutated = $original | ConvertFrom-Json
        $mutated.completed_scopes = @(
            $mutated.completed_scopes |
                Where-Object { [string]$_ -ne 'CanonicalBattleCodec-v1' }
        )
        [IO.File]::WriteAllText(
            $path,
            ($mutated | ConvertTo-Json -Depth 12),
            (New-Object Text.UTF8Encoding($false))
        )
        $evaluation = Get-FoundationEvidenceEvaluation -Toolchain $Toolchain
        $detected = (
            -not $evaluation.Verified -and
            @($evaluation.Missing) -contains 'AC-064:canonical:CanonicalBattleCodec-v1'
        )
    }
    finally {
        [IO.File]::WriteAllText($path, $original, (New-Object Text.UTF8Encoding($false)))
    }
    if (-not $detected) {
        return [pscustomobject]@{ Verified = $false; Message = 'Missing canonical scope did not fail its mapped AC.' }
    }
    $restored = Get-FoundationEvidenceEvaluation -Toolchain $Toolchain
    if (-not $restored.Verified -or [IO.File]::ReadAllText($path) -ne $original) {
        return [pscustomobject]@{ Verified = $false; Message = 'Evidence mutation restore/read-back failed.' }
    }
    return [pscustomobject]@{ Verified = $true; Message = 'Per-AC evidence mutation was detected and restored.' }
}

function Write-FoundationAcceptanceArtifact {
    param([int]$AllExitCode, [object]$Toolchain)

    $foundationF = @(
        'AC-025', 'AC-026', 'AC-036', 'AC-039', 'AC-040', 'AC-051',
        'AC-052', 'AC-054', 'AC-055', 'AC-063', 'AC-064', 'AC-068',
        'AC-069', 'AC-070', 'AC-078'
    )
    $foundationX = @('AC-016', 'AC-027', 'AC-034', 'AC-047', 'AC-065', 'AC-073', 'AC-075')
    $foundationD = @(
        'AC-007', 'AC-020', 'AC-023', 'AC-024', 'AC-035', 'AC-041',
        'AC-046', 'AC-058', 'AC-066', 'AC-072', 'AC-076'
    )
    $evaluation = Get-FoundationEvidenceEvaluation -Toolchain $Toolchain
    $evidence = New-Object System.Collections.Generic.List[object]
    foreach ($acceptanceId in $foundationF) {
        $item = $evaluation.Evaluations[$acceptanceId]
        $evidence.Add([ordered]@{
            acceptance_id = $acceptanceId
            classification = 'F'
            status = if ($AllExitCode -eq 0 -and $item.Verified) { 'pass' } else { 'not_verified' }
            required_evidence = $item.Required
            missing_evidence = $item.Missing
        })
    }
    foreach ($acceptanceId in $foundationX) {
        $item = $evaluation.Evaluations[$acceptanceId]
        $evidence.Add([ordered]@{
            acceptance_id = $acceptanceId
            classification = 'X'
            status = if ($AllExitCode -eq 0 -and $item.Verified) { 'foundation_pass_downstream_pending' } else { 'foundation_not_verified' }
            required_evidence = $item.Required
            missing_evidence = $item.Missing
        })
    }
    foreach ($acceptanceId in $foundationD) {
        $evidence.Add([ordered]@{
            acceptance_id = $acceptanceId
            classification = 'D'
            status = 'downstream_deferred'
            required_evidence = @()
            missing_evidence = @()
        })
    }
    $payload = [ordered]@{
        schema_version = 2
        suite = 'All'
        all_exit_code = $AllExitCode
        evidence_verified = [bool]$evaluation.Verified
        evidence_failures = $evaluation.Missing
        generated_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        toolchain = $Toolchain
        acceptance = $evidence.ToArray()
    }
    $path = Join-Path $artifactRoot 'foundation-acceptance.json'
    $temporaryPath = $path + '.tmp'
    [IO.File]::WriteAllText($temporaryPath, ($payload | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
    $roundTrip = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$roundTrip.acceptance.Count -ne 33 -or [int]$roundTrip.schema_version -ne 2) {
        throw 'foundation-acceptance.json read-back validation failed.'
    }
}

function Get-CombatEvidenceEvaluation {
    $observed = @{}
    $gutCases = @{}
    $gutPath = Join-Path $artifactRoot 'gut.xml'
    if (Test-Path -LiteralPath $gutPath -PathType Leaf) {
        try {
            [xml]$gutDocument = Get-Content -LiteralPath $gutPath -Raw -Encoding UTF8
            $gutRoot = $gutDocument.SelectSingleNode('/testsuites')
            if ($null -ne $gutRoot -and
                [int]$gutRoot.GetAttribute('failures') -eq 0 -and
                [int]$gutRoot.GetAttribute('errors') -eq 0 -and
                [int]$gutRoot.GetAttribute('orphans') -eq 0) {
                foreach ($testCase in $gutDocument.SelectNodes('//testcase')) {
                    if ([string]$testCase.GetAttribute('status') -eq 'pass') {
                        $gutCases[[string]$testCase.GetAttribute('name')] = $true
                    }
                }
            }
        }
        catch { $gutCases = @{} }
    }
    foreach ($testName in $gutCases.Keys) {
        $observed['gut:' + $testName] = $true
    }

    foreach ($artifactName in @('combat-runner.json', 'canonical.json', 'soak.json', 'spec-contract.json')) {
        $path = Join-Path $artifactRoot $artifactName
        $artifact = $null
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try { $artifact = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
            catch { $artifact = $null }
        }
        $observed['artifact:' + $artifactName] = (
            $null -ne $artifact -and [bool]$artifact.passed -and @($artifact.failures).Count -eq 0
        )
        if ($null -ne $artifact) {
            foreach ($scope in @($artifact.completed_scopes)) {
                $observed['scope:' + $artifactName + ':' + [string]$scope] = [bool]$artifact.passed
            }
            if ($artifactName -eq 'soak.json') {
                $observed['soak:10000'] = (
                    [bool]$artifact.passed -and [int]$artifact.seed_count -ge 10000 -and
                    [int]$artifact.maximum_final_tick -le 1800
                )
            }
        }
    }

    $rules = [ordered]@{
        'S2-AC-001' = @('gut:test_board_validator_collects_and_sorts_all_errors')
        'S2-AC-002' = @('gut:test_twelve_deployed_units_fit_capacity_and_thirteen_do_not', 'gut:test_all_thirty_two_player_half_cells_are_a_valid_physical_bound')
        'S2-AC-003' = @('gut:test_bench_compaction_preserves_player_relative_order', 'gut:test_command_compacts_validates_and_returns_complete_draft')
        'S2-AC-004' = @('gut:test_nine_one_star_units_chain_to_one_three_star_and_conserve_copies', 'gut:test_board_presence_then_cell_order_choose_primary_before_instance_id')
        'S2-AC-005' = @('gut:test_equipment_moves_by_consumed_unit_and_slot_with_inventory_overflow')
        'S2-AC-006' = @('gut:test_compile_is_deterministic_and_persists_boss_source_id', 'gut:test_lab_proxy_factory_builds_normal_and_source_bound_two_phase_boss')
        'S2-AC-007' = @('gut:test_v2_round_trip_hash_envelope_and_v1_golden_compatibility', 'gut:test_v2_effect_source_location_and_owner_are_hashed_and_strict')
        'S2-AC-008' = @('gut:test_same_setup_produces_identical_result_and_summary_hash', 'gut:test_speed_one_and_four_publish_identical_committed_result', 'gut:test_reload_of_committed_result_never_initializes_or_steps_simulation')
        'S2-AC-009' = @('gut:test_path_tie_uses_fixed_direction_order_and_blocks_corner_cutting')
        'S2-AC-010' = @('gut:test_integer_resistance_true_damage_and_minimum_damage_vectors', 'gut:test_simultaneous_lethal_attacks_resolve_both_deaths_as_player_loss', 'gut:test_damage_wave_uses_shared_final_health_and_deterministic_killer', 'gut:test_full_mana_cast_has_priority_and_applies_resolved_damage_next_tick', 'gut:test_boss_phase_uses_explicit_source_instance_and_fixed_phase_order')
        'S2-AC-011' = @('gut:test_progress_damage_mana_and_overtime_use_fixed_integer_thresholds', 'gut:test_overtime_starts_at_1200_and_forces_result_before_hard_limit')
        'S2-AC-012' = @('gut:test_boss_loss_uses_act_snapshot_and_encounter_survivor_formula_without_mutation')
        'S2-AC-013' = @('gut:test_all_nine_triggers_and_four_stacking_modes_are_accepted', 'gut:test_all_ten_conditions_have_matching_positive_fixture', 'gut:test_all_nine_battle_operations_produce_typed_atomic_operations', 'gut:test_unknown_operation_and_budget_failure_return_no_partial_resolution', 'gut:test_replace_uses_larger_amount_then_duration_canonical_tuple', 'gut:test_refresh_keeps_amount_and_only_extends_duration', 'gut:test_add_stacks_clamps_count_amount_and_takes_longer_duration', 'gut:test_independent_preserves_separate_application_sequences')
        'S2-AC-014' = @('gut:test_reactive_damage_cycle_requires_finite_max_uses_guard', 'gut:test_rmp2_payload_digest_golden_and_restore_are_exact', 'gut:test_runtime_dispatches_all_non_cast_triggers_and_persists_battle_end_intent', 'gut:test_fatal_effect_budget_rolls_back_tick_rng_events_and_enters_failed_lifecycle')
        'S2-AC-015' = @('scope:canonical.json:BattleResult/EventCodec-v1', 'gut:test_all_fourteen_event_payloads_round_trip_canonical_bytes', 'gut:test_unknown_type_wrong_payload_and_noncanonical_bytes_are_rejected', 'gut:test_same_setup_produces_identical_result_and_summary_hash')
        'S2-AC-016' = @('gut:test_start_combat_builds_committed_v2_setup_from_preview_and_roster', 'gut:test_record_result_requires_exact_setup_result_and_receipt_hashes', 'gut:test_result_commit_failure_hides_terminal_then_retry_publishes_once', 'gut:test_schema_one_prepare_and_pending_runs_preserve_profile_and_original_bytes', 'gut:test_schema_one_idle_map_migrates_generation_atomically_and_is_idempotent', 'gut:test_bsm1_cgm1_and_cgr1_golden_vectors_are_stable', 'gut:test_cgr1_rejects_tampering_of_every_receipt_field')
        'S2-AC-017' = @('gut:test_lab_builds_64_cells_nine_bench_slots_and_starts_proxy_battle', 'gut:test_lab_proxy_factory_builds_normal_and_source_bound_two_phase_boss', 'gut:test_presenter_returns_clone_isolated_setup_events_and_result')
        'S2-AC-018' = @('scope:combat-runner.json:battle_32v32_64_entity_stress', 'soak:10000')
    }
    $evaluations = [ordered]@{}
    $missingAll = New-Object System.Collections.Generic.List[string]
    foreach ($acceptanceId in $rules.Keys) {
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($key in @($rules[$acceptanceId])) {
            if (-not $observed.ContainsKey($key) -or -not [bool]$observed[$key]) {
                $missing.Add($key)
                $missingAll.Add($acceptanceId + ':' + $key)
            }
        }
        $evaluations[$acceptanceId] = [pscustomobject]@{
            Verified = ($missing.Count -eq 0)
            Required = @($rules[$acceptanceId])
            Missing = $missing.ToArray()
        }
    }
    return [pscustomobject]@{
        Verified = ($missingAll.Count -eq 0)
        Evaluations = $evaluations
        Missing = $missingAll.ToArray()
    }
}

function Write-CombatAcceptanceArtifact {
    param([object]$Toolchain)

    $evaluation = Get-CombatEvidenceEvaluation
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($acceptanceId in $evaluation.Evaluations.Keys) {
        $item = $evaluation.Evaluations[$acceptanceId]
        $items.Add([ordered]@{
            acceptance_id = $acceptanceId
            status = if ($item.Verified) { 'pass' } else { 'not_verified' }
            required_evidence = $item.Required
            missing_evidence = $item.Missing
        })
    }
    $payload = [ordered]@{
        schema_version = 2
        scope = 'combat-core'
        suite = $Suite
        evidence_verified = [bool]$evaluation.Verified
        evidence_failures = $evaluation.Missing
        generated_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        toolchain = $Toolchain
        global_downstream = @(
            'S3: expedition HP/income/reward/Boss retry settlement exactly-once',
            'S4: formal trait/equipment/relic population and effect sources',
            'G1/G2: minimum-PC 60 FPS presentation acceptance',
            'AC-030: full-run soak remains downstream'
        )
        acceptance = $items.ToArray()
    }
    $path = Join-Path $artifactRoot 'combat-acceptance.json'
    $temporaryPath = $path + '.tmp'
    [IO.File]::WriteAllText($temporaryPath, ($payload | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
    $roundTrip = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$roundTrip.acceptance.Count -ne 18 -or [int]$roundTrip.schema_version -ne 2) {
        throw 'combat-acceptance.json read-back validation failed.'
    }
}

$toolchainEvidence = $null
try {
    New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
    try {
        $runnerLockStream = [IO.File]::Open(
            $runnerLockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
        $ownsRunnerLock = $true
    }
    catch {
        throw 'Another test runner already owns artifacts/test; parallel runner execution is rejected.'
    }
    $resolvedGodot = Resolve-GodotExecutable
    $toolchain = Test-Toolchain -Executable $resolvedGodot
    $toolchainEvidence = $toolchain
    if ($toolchain.ExitCode -ne 0) {
        $finalExitCode = [int]$toolchain.ExitCode
        $failureMessage = [string]$toolchain.Message
    }
    elseif ($Suite -eq 'Toolchain') {
        $finalExitCode = 0
        $failureMessage = [string]$toolchain.Message
    }
    else {
        $selected = if ($Suite -eq 'All') { @('Import', 'RunnerContract', 'Smoke', 'Gut', 'Content', 'Canonical', 'Combat', 'Spec') } else { @($Suite) }
        $finalExitCode = 0
        foreach ($name in $selected) {
            if ($name -eq 'Import') {
                $logPath = Join-Path $artifactRoot 'import.godot.log'
                $childCode = Invoke-GodotChild -Executable $resolvedGodot -Name 'Import' -Arguments @('--headless', '--editor', '--path', $repoRoot, '--log-file', $logPath, '--import', '--quit')
                $code = Test-ImportResult -ChildExitCode $childCode -LogPath $logPath
            }
            elseif ($name -eq 'Gut' -or $name -eq 'RunnerContract') {
                if ($Suite -ne 'All') {
                    $logPath = Join-Path $artifactRoot 'import.godot.log'
                    $importCode = Invoke-GodotChild -Executable $resolvedGodot -Name 'Import' -Arguments @('--headless', '--editor', '--path', $repoRoot, '--log-file', $logPath, '--import', '--quit')
                    $importCode = Test-ImportResult -ChildExitCode $importCode -LogPath $logPath
                    if ($importCode -ne 0) { $code = $importCode } else { $code = 0 }
                }
                else { $code = 0 }
                if ($code -eq 0 -and $name -eq 'RunnerContract') {
                    $contractResult = Test-RunnerContract -Executable $resolvedGodot
                    $code = [int]$contractResult.ExitCode
                    if ($code -ne 0) {
                        $failureMessage = [string]$contractResult.Message
                    }
                }
                elseif ($code -eq 0) {
                    $userArgs = @()
                    if (-not [string]::IsNullOrWhiteSpace($TestPath)) { $userArgs += @('--test-path', $TestPath) }
                    $code = Invoke-RunnerScript -Executable $resolvedGodot -Name 'Gut' -ScriptPath 'res://tests/runners/gut_runner.gd' -UserArguments $userArgs
                }
            }
            else {
                $scriptName = switch ($name) {
                    'Smoke' { 'smoke_runner.gd' }
                    'Content' { 'content_validation_runner.gd' }
                    'Canonical' { 'canonical_runner.gd' }
                    'Combat' { 'combat_runner.gd' }
                    'Soak' { 'soak_runner.gd' }
                    'Spec' { 'spec_contract_runner.gd' }
                }
                $userArgs = @()
                if (-not [string]::IsNullOrWhiteSpace($Case)) { $userArgs += @('--case', $Case) }
                if ($name -eq 'Soak') { $userArgs += @('--seed-count', [string]$SeedCount) }
                $code = Invoke-RunnerScript -Executable $resolvedGodot -Name $name -ScriptPath ('res://tests/runners/' + $scriptName) -UserArguments $userArgs
            }
            if ($code -ne 0) {
                $finalExitCode = $code
                $failureMessage = "$name failed with exit code $code."
                break
            }
        }
        if ($finalExitCode -eq 0 -and $Suite -eq 'All') {
            $foundationEvidence = Get-FoundationEvidenceEvaluation -Toolchain $toolchainEvidence
            if (-not $foundationEvidence.Verified) {
                $finalExitCode = 2
                $failureMessage = 'Foundation acceptance evidence is incomplete: ' + ($foundationEvidence.Missing -join ', ')
            }
            else {
                $foundationNegative = Test-FoundationEvidenceNegativeContract -Toolchain $toolchainEvidence
                if (-not $foundationNegative.Verified) {
                    $finalExitCode = 2
                    $failureMessage = [string]$foundationNegative.Message
                }
            }
        }
        if ($finalExitCode -eq 0) { $failureMessage = 'Requested suites completed.' }
    }
}
catch {
    $finalExitCode = 3
    $failureMessage = $_.Exception.Message
}
finally {
    if ($ownsRunnerLock) {
        try {
            Write-ExecutionArtifact -ExitCode $finalExitCode -Message $failureMessage -Toolchain $toolchainEvidence
        }
        catch {
            Write-Error $_
            $finalExitCode = 3
        }
        finally {
            $runnerLockStream.Dispose()
            $runnerLockStream = $null
            $ownsRunnerLock = $false
        }
    }
}

Write-Host $failureMessage
exit $finalExitCode
