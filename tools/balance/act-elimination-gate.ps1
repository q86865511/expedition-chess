# DC-REQ-008 (difficulty-curve T08): PowerShell mirror of the per-act
# elimination gate implemented in domain/balance/balance_bot_report.gd
# (ACT_ELIMINATION_MIN_SEED_COUNT, act_curve(), _act_elimination_flat()).
# Both halves must produce byte-identical act_curve tokens and gate reasons for
# the same input; tests/fixtures/balance_playtest/act_elimination_golden.json
# pins that equality and tools/balance/tests/test-act-elimination-gate.ps1
# checks this half. Change one side and the golden turns red on both.

# TUNE: below this cohort seed count a single-act concentration is statistical
# noise, so the gate is not evaluated.
$script:BalanceActEliminationMinSeedCount = 1000

function Get-BalanceActCurve {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$CaseProofs,
        [Parameter(Mandatory = $true)]
        [int]$SeedCount
    )
    $rows = New-Object System.Collections.Generic.List[object]
    $tokenParts = New-Object System.Collections.Generic.List[string]
    $tokenParts.Add('ACT-CURVE-V1')
    $tokenParts.Add("seed_count=$SeedCount")
    $eliminationTotal = 0
    $eliminationActs = New-Object System.Collections.Generic.List[int]
    foreach ($actIndex in @(1, 2, 3)) {
        $entered = 0
        $eliminated = 0
        $wins = 0
        $losses = 0
        foreach ($proof in $CaseProofs) {
            if ($null -eq $proof -or $null -eq $proof.act_snapshots) { continue }
            foreach ($snapshot in @($proof.act_snapshots)) {
                if ($null -eq $snapshot -or [int]$snapshot.act_index -ne $actIndex) { continue }
                $entered += 1
                $wins += [int]$snapshot.battle_wins
                $losses += [int]$snapshot.battle_losses
                if (-not [string]::IsNullOrEmpty([string]$snapshot.elimination_node_id)) {
                    $eliminated += 1
                }
            }
        }
        $rows.Add([ordered]@{
            act_index = $actIndex
            entered = $entered
            eliminated = $eliminated
            battle_wins = $wins
            battle_losses = $losses
        })
        $tokenParts.Add(('{0}:{1}:{2}:{3}:{4}' -f $actIndex, $entered, $eliminated, $wins, $losses))
        $eliminationTotal += $eliminated
        if ($eliminated -gt 0) { $eliminationActs.Add($actIndex) }
    }
    $tokenParts.Add("total=$eliminationTotal")
    $tokenParts.Add("acts=$(($eliminationActs.ToArray()) -join ',')")
    return [ordered]@{
        min_seed_count = $script:BalanceActEliminationMinSeedCount
        enforced = ($SeedCount -ge $script:BalanceActEliminationMinSeedCount)
        acts = $rows.ToArray()
        elimination_total = $eliminationTotal
        elimination_acts = $eliminationActs.ToArray()
        token = ($tokenParts.ToArray() -join '|')
    }
}

function Get-BalanceActEliminationGateReasons {
    param(
        [Parameter(Mandatory = $true)]
        $ActCurve
    )
    # Every loss landing in one act is the "clear that act and you always win"
    # pathology; zero losses is covered by the perfect-win-rate gate instead.
    if (-not [bool]$ActCurve.enforced) { return @() }
    if ([int]$ActCurve.elimination_total -le 0) { return @() }
    if (@($ActCurve.elimination_acts).Count -ne 1) { return @() }
    return @('BALANCE_ACT_ELIMINATION_FLAT')
}
