param([Parameter(Mandatory = $true)][string]$Repo)

$ErrorActionPreference = 'Stop'
$repoPath = [System.IO.Path]::GetFullPath($Repo)
$prepareScript = Join-Path $repoPath 'tools\content-production\prepare-imagegen-attempt.ps1'
$attemptRoot = Join-Path $repoPath 'assets\production\attempts'

Get-ChildItem -LiteralPath $attemptRoot -Directory | Sort-Object Name | ForEach-Object {
    $latest = Get-ChildItem -LiteralPath $_.FullName -Directory -Filter 'attempt-*' | Sort-Object Name | Select-Object -Last 1
    & $prepareScript -Repo $repoPath -Unit $_.Name -Attempt $latest.Name
}
