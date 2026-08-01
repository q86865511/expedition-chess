param([Parameter(Mandatory = $true)][string]$Repo)

$ErrorActionPreference = 'Stop'
$repoPath = [System.IO.Path]::GetFullPath($Repo)
$sourcePath = Join-Path $repoPath 'tools\content-production\production_shared_atlas_generator.cs'
Add-Type -Path $sourcePath -ReferencedAssemblies 'System.Drawing.dll'
$output = Join-Path $repoPath 'assets\production\shared_attempts\attempt-001'
[ProductionSharedAtlasGenerator]::Generate($output)
Get-ChildItem -LiteralPath $output -Filter '*.png' | Sort-Object Name | ForEach-Object {
    "{0} {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.Name
}
