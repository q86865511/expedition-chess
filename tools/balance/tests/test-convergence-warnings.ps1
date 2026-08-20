[CmdletBinding()]
param()

# G2 Phase 2 R0: PowerShell half of the section 6.3b convergence golden. It
# consumes the same fixture as
# tests/unit/balance_playtest/test_balance_convergence_warnings.gd, so both
# implementations are pinned to identical convergence tokens and WARN lists.
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/balance/tests/test-convergence-warnings.ps1
# Exit codes: 0 = all assertions passed, 1 = mismatch (red).

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\convergence-warnings.ps1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    Write-Output "FAIL missing mirrored implementation: $modulePath"
    exit 1
}
. $modulePath

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$goldenPath = Join-Path $repoRoot 'tests\fixtures\balance_playtest\convergence_golden.json'
if (-not (Test-Path -LiteralPath $goldenPath -PathType Leaf)) {
    Write-Output "FAIL missing golden: $goldenPath"
    exit 1
}
$golden = Get-Content -Raw -Encoding UTF8 -LiteralPath $goldenPath | ConvertFrom-Json

$failures = New-Object System.Collections.Generic.List[string]
$checked = 0
foreach ($scenario in @($golden.scenarios)) {
    $name = [string]$scenario.name
    $report = Get-BalanceConvergenceReport -CaseProofs @($scenario.case_proofs)
    $expectedToken = [string]$scenario.expected_convergence_token
    $expectedWarnings = @($scenario.expected_warnings | ForEach-Object { [string]$_ })
    $actualWarnings = @($report.warnings | ForEach-Object { [string]$_ })
    $checked += 1
    if ([string]$report.token -cne $expectedToken) {
        $failures.Add("$name token`n  expected: $expectedToken`n  actual  : $($report.token)")
    }
    if (($actualWarnings -join ',') -cne ($expectedWarnings -join ',')) {
        $failures.Add("$name warnings expected [$($expectedWarnings -join ',')] actual [$($actualWarnings -join ',')]")
    }
    if ([int]$report.win_rate_band_low_bps -ne 4500 -or
        [int]$report.win_rate_band_high_bps -ne 6000 -or
        [int]$report.win_hp_ceiling_warn_bps -ne 5000) {
        $failures.Add("$name published TUNE thresholds drifted from the pinned 4500/6000/5000")
    }
    Write-Output ("CHECK {0} token={1} warnings=[{2}]" -f $name, $report.token, ($actualWarnings -join ','))
}

if ($checked -ne 6) {
    $failures.Add("golden must cover 6 scenarios, saw $checked")
}

# The aggregate runner must consume the shared function and must never fold the
# convergence warnings into the gate; an inlined copy or an Add-GateReason call
# would break exactly what this mirror exists to guarantee.
$aggregatePath = Join-Path $repoRoot 'tools\balance\run-sharded-cohort.ps1'
$aggregateText = Get-Content -Raw -Encoding UTF8 -LiteralPath $aggregatePath
foreach ($token in @('convergence-warnings.ps1', 'Get-BalanceConvergenceReport', 'convergence = $convergence')) {
    if ($aggregateText -notmatch [regex]::Escape($token)) {
        $failures.Add("run-sharded-cohort.ps1 does not wire '$token'")
    }
}
foreach ($line in ($aggregateText -split "`n")) {
    if ($line -match 'Add-GateReason' -and $line -match 'BALANCE_WARN_') {
        $failures.Add("run-sharded-cohort.ps1 must not turn a convergence WARN into a gate reason: $($line.Trim())")
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Output "FAIL $failure" }
    Write-Output "RESULT FAIL ($($failures.Count) assertion failures)"
    exit 1
}
Write-Output "RESULT PASS ($checked golden scenarios, GDScript-mirrored tokens and warnings)"
exit 0
