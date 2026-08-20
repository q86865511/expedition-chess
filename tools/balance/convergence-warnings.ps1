# G2 Phase 2 R0: PowerShell mirror of the section 6.3b convergence report implemented in
# domain/balance/balance_bot_report.gd (WIN_RATE_BAND_*_BPS,
# WIN_HP_CEILING_WARN_BPS, _convergence()). Both halves must produce
# byte-identical convergence tokens and warning lists for the same input;
# tests/fixtures/balance_playtest/convergence_golden.json pins that equality,
# tools/balance/tests/test-convergence-warnings.ps1 checks this half and
# tests/unit/balance_playtest/test_balance_convergence_warnings.gd the other.
# Change one side and the golden turns red on both.
#
# These are WARN-only signals: they are reported and listed, never folded into
# gate_reasons. A mid-iteration cohort that misses the band must still be able to
# produce a PASS gate, otherwise the gate stops carrying information.

# TUNE (g2-roadmap section 6.3b): target win-rate band for all three strategies,
# boundaries inclusive.
$script:BalanceWinRateBandLowBps = 4500
$script:BalanceWinRateBandHighBps = 6000
# TUNE (g2-roadmap section 6.3b): when this share of winning cases ends on the highest
# terminal HP observed in the cohort, the wins are flat (full-HP clears). The
# report carries no max-HP field, so the observed ceiling is the proxy for full.
$script:BalanceWinHpCeilingWarnBps = 5000

function Get-BalanceConvergenceRateBps {
    param([long]$Numerator, [long]$Denominator)
    if ($Denominator -le 0) { return 0 }
    return [int][math]::Floor(($Numerator * 10000.0) / $Denominator)
}

function Get-BalanceConvergenceReport {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$CaseProofs
    )
    $rows = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    $tokenParts = New-Object System.Collections.Generic.List[string]
    $tokenParts.Add('CONVERGENCE-V1')
    $tokenParts.Add(('band={0}-{1}' -f $script:BalanceWinRateBandLowBps,
        $script:BalanceWinRateBandHighBps))
    # Strategy order mirrors BalanceBotStrategy.IDS; the token is position based.
    foreach ($strategyId in @('tempo', 'economy', 'synergy')) {
        $cases = 0
        $wins = 0
        foreach ($proof in $CaseProofs) {
            if ($null -eq $proof -or [string]$proof.strategy_id -cne $strategyId) { continue }
            $cases += 1
            # Win rate follows `won` alone (no terminal filter) so both halves
            # share one definition.
            if ([bool]$proof.won) { $wins += 1 }
        }
        $rate = Get-BalanceConvergenceRateBps -Numerator $wins -Denominator $cases
        $evaluated = $cases -gt 0
        $inBand = $evaluated -and $rate -ge $script:BalanceWinRateBandLowBps -and
            $rate -le $script:BalanceWinRateBandHighBps
        $rows.Add([ordered]@{
            strategy_id = $strategyId
            cases = $cases
            wins = $wins
            win_rate_bps = $rate
            evaluated = $evaluated
            in_band = $inBand
        })
        $tokenParts.Add(('{0}:{1}:{2}:{3}:{4}:{5}' -f $strategyId, $cases, $wins, $rate,
            $(if ($evaluated) { 1 } else { 0 }), $(if ($inBand) { 1 } else { 0 })))
        if ($evaluated -and -not $inBand) {
            $warnings.Add("BALANCE_WARN_$($strategyId.ToUpperInvariant())_WIN_RATE_OUT_OF_BAND")
        }
    }
    $winHp = New-Object System.Collections.Generic.List[int]
    $distinct = New-Object System.Collections.Generic.List[int]
    $minimum = 0
    $maximum = 0
    foreach ($proof in $CaseProofs) {
        if ($null -eq $proof -or -not [bool]$proof.won) { continue }
        $hp = [int]$proof.ending_hp
        if ($winHp.Count -eq 0) {
            $minimum = $hp
            $maximum = $hp
        }
        else {
            if ($hp -lt $minimum) { $minimum = $hp }
            if ($hp -gt $maximum) { $maximum = $hp }
        }
        $winHp.Add($hp)
        if (-not $distinct.Contains($hp)) { $distinct.Add($hp) }
    }
    $ceilingWins = 0
    foreach ($hp in $winHp) {
        if ($hp -eq $maximum) { $ceilingWins += 1 }
    }
    $ceilingRate = Get-BalanceConvergenceRateBps -Numerator $ceilingWins -Denominator $winHp.Count
    $evaluatedHp = $winHp.Count -gt 0
    $distributed = $evaluatedHp -and $ceilingRate -lt $script:BalanceWinHpCeilingWarnBps
    $distribution = [ordered]@{
        win_case_count = $winHp.Count
        distinct_hp_count = $distinct.Count
        min_hp = $minimum
        max_hp = $maximum
        ceiling_win_count = $ceilingWins
        ceiling_win_rate_bps = $ceilingRate
        evaluated = $evaluatedHp
        distributed = $distributed
    }
    $tokenParts.Add(('hp:{0}:{1}:{2}:{3}:{4}:{5}:{6}:{7}' -f $winHp.Count, $distinct.Count,
        $minimum, $maximum, $ceilingWins, $ceilingRate,
        $(if ($evaluatedHp) { 1 } else { 0 }), $(if ($distributed) { 1 } else { 0 })))
    if ($evaluatedHp -and -not $distributed) {
        $warnings.Add('BALANCE_WARN_WIN_HP_NOT_DISTRIBUTED')
    }
    $tokenParts.Add("warn=$(($warnings.ToArray()) -join ',')")
    return [ordered]@{
        win_rate_band_low_bps = $script:BalanceWinRateBandLowBps
        win_rate_band_high_bps = $script:BalanceWinRateBandHighBps
        win_hp_ceiling_warn_bps = $script:BalanceWinHpCeilingWarnBps
        strategy_win_rates = $rows.ToArray()
        win_hp_distribution = $distribution
        warnings = $warnings.ToArray()
        token = ($tokenParts.ToArray() -join '|')
    }
}
