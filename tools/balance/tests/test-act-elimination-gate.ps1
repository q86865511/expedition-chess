[CmdletBinding()]
param()

# DC-REQ-008 (difficulty-curve T08): PowerShell half of the per-act elimination
# gate golden. It consumes the same fixture as
# tests/unit/balance_playtest/test_balance_act_elimination_gate.gd, so both
# implementations are pinned to identical act_curve tokens and gate reasons.
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/balance/tests/test-act-elimination-gate.ps1
# Exit codes: 0 = all assertions passed, 1 = mismatch (red).

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\act-elimination-gate.ps1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    Write-Output "FAIL missing mirrored implementation: $modulePath"
    exit 1
}
. $modulePath

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$goldenPath = Join-Path $repoRoot 'tests\fixtures\balance_playtest\act_elimination_golden.json'
if (-not (Test-Path -LiteralPath $goldenPath -PathType Leaf)) {
    Write-Output "FAIL missing golden: $goldenPath"
    exit 1
}
$golden = Get-Content -Raw -Encoding UTF8 -LiteralPath $goldenPath | ConvertFrom-Json

$failures = New-Object System.Collections.Generic.List[string]
$checked = 0
foreach ($scenario in @($golden.scenarios)) {
    $name = [string]$scenario.name
    $seedCount = [int]$scenario.cohort_seed_count
    $curve = Get-BalanceActCurve -CaseProofs @($scenario.case_proofs) -SeedCount $seedCount
    $reasons = @(Get-BalanceActEliminationGateReasons -ActCurve $curve)
    $expectedToken = [string]$scenario.expected_act_curve_token
    $expectedReasons = @($scenario.expected_gate_reasons | ForEach-Object { [string]$_ })
    $checked += 1
    if ([string]$curve.token -cne $expectedToken) {
        $failures.Add("$name token`n  expected: $expectedToken`n  actual  : $($curve.token)")
    }
    if (($reasons -join ',') -cne ($expectedReasons -join ',')) {
        $failures.Add("$name gate_reasons expected [$($expectedReasons -join ',')] actual [$($reasons -join ',')]")
    }
    if ([bool]$curve.enforced -ne ($seedCount -ge 1000)) {
        $failures.Add("$name enforced flag must follow the 1000-seed TUNE threshold")
    }
    Write-Output ("CHECK {0} token={1} reasons=[{2}]" -f $name, $curve.token, ($reasons -join ','))
}

if ($checked -ne 5) {
    $failures.Add("golden must cover 5 scenarios, saw $checked")
}

# The aggregate runner must consume the shared function; an inlined copy would
# let the two implementations drift while this golden stays green.
$aggregatePath = Join-Path $repoRoot 'tools\balance\run-sharded-cohort.ps1'
$aggregateText = Get-Content -Raw -Encoding UTF8 -LiteralPath $aggregatePath
foreach ($token in @('act-elimination-gate.ps1', 'Get-BalanceActCurve', 'Get-BalanceActEliminationGateReasons')) {
    if ($aggregateText -notmatch [regex]::Escape($token)) {
        $failures.Add("run-sharded-cohort.ps1 does not wire '$token'")
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Output "FAIL $failure" }
    Write-Output "RESULT FAIL ($($failures.Count) assertion failures)"
    exit 1
}
Write-Output "RESULT PASS ($checked golden scenarios, GDScript-mirrored tokens and gate reasons)"
exit 0
