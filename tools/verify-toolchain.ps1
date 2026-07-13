[CmdletBinding()]
param(
    [string]$GodotPath = ''
)

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'run-tests.ps1'
$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $runner,
    '-Suite', 'Toolchain'
)
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
    $arguments += @('-GodotPath', $GodotPath)
}

& powershell.exe @arguments
exit $LASTEXITCODE
