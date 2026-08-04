[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [ValidateRange(10000, 10000)]
    [int]$SeedCount = 10000,
    [string]$OutputRoot = 'artifacts\rc\staging'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$godot = (Resolve-Path -LiteralPath $GodotPath).Path
if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) {
    throw 'Godot executable is missing.'
}
$version = (& $godot --version | Select-Object -First 1)
if ($version -notmatch '^4\.7') {
    throw "Godot 4.7 is required; found $version"
}

$resolvedOutput = [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\rc'))
$allowedPrefix = $allowedRoot.TrimEnd('\') + '\'
if ($resolvedOutput -eq $allowedRoot -or -not $resolvedOutput.StartsWith(
    $allowedPrefix, [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'OutputRoot must stay under artifacts\rc.'
}
if (Test-Path -LiteralPath $resolvedOutput) {
    Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $repoRoot 'tools\run-tests.ps1') -Suite All -GodotPath $godot `
    -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { throw 'All gate failed.' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $repoRoot 'tools\run-tests.ps1') -Suite ExpeditionSoak `
    -GodotPath $godot -SeedCount 10000 -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { throw 'ExpeditionSoak gate failed.' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $repoRoot 'tools\balance\run-final-cohort.ps1') `
    -GodotPath $godot -SeedCount $SeedCount -TimeoutSeconds 3600
if ($LASTEXITCODE -ne 0) { throw 'BalancePlaytest final gate failed.' }

$exePath = Join-Path $resolvedOutput 'ExpeditionChess.exe'
$exportLog = Join-Path $allowedRoot 'export.log'
$exportArguments = '--headless --path "{0}" --log-file "{1}" --export-release "Windows Provisional RC" "{2}"' -f `
    $repoRoot, $exportLog, $exePath
$exportProcess = Start-Process -FilePath $godot -ArgumentList $exportArguments `
    -Wait -PassThru -WindowStyle Hidden
if ($exportProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exePath)) {
    throw 'Windows export failed.'
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'PLAYTEST.md') -Destination $resolvedOutput
Copy-Item -LiteralPath (Join-Path $repoRoot 'PLAYTEST-LICENSES.txt') -Destination $resolvedOutput

$smokeProfile = Join-Path $allowedRoot 'fresh-profile'
if (Test-Path -LiteralPath $smokeProfile) {
    Remove-Item -LiteralPath $smokeProfile -Recurse -Force
}
New-Item -ItemType Directory -Path $smokeProfile -Force | Out-Null
$smokeLog = Join-Path $allowedRoot 'rc-smoke.log'
$startInfo = New-Object Diagnostics.ProcessStartInfo
$startInfo.FileName = $exePath
$startInfo.Arguments = '--headless --quit-after 5 --log-file "{0}"' -f $smokeLog
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.EnvironmentVariables['APPDATA'] = $smokeProfile
$smokeProcess = [Diagnostics.Process]::Start($startInfo)
if (-not $smokeProcess.WaitForExit(60000)) {
    Stop-Process -Id $smokeProcess.Id -Force
    throw 'Exported executable smoke timed out.'
}
$smokeText = Get-Content -Raw -Encoding UTF8 -LiteralPath $smokeLog
if ($smokeProcess.ExitCode -ne 0 -or $smokeText -match 'SCRIPT ERROR|Parse Error|ERROR:|content bootstrap failed') {
    throw 'Exported executable smoke failed.'
}

$zipPath = Join-Path $allowedRoot 'ExpeditionChess-g2-rc1-win64.zip'
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $resolvedOutput '*') -DestinationPath $zipPath
$digest = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$shaPath = $zipPath + '.sha256'
Set-Content -LiteralPath $shaPath -Encoding ASCII -Value "$digest  $([IO.Path]::GetFileName($zipPath))"
Write-Output $zipPath
Write-Output $shaPath
