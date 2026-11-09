#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][long]$OriginalRunId,
    [Parameter(Mandatory)][long]$ArtifactId,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = & "$PSScriptRoot/Get-RecoverySource.ps1" -Repository $Repository -OriginalRunId $OriginalRunId -ArtifactId $ArtifactId
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$directory = (Resolve-Path -LiteralPath $OutputDirectory).Path
if ($env:GITHUB_OUTPUT) {
    @("original_run_id=$($source.RunId)", "artifact_id=$($source.ArtifactId)", "artifacts_path=$directory") |
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM
}
Write-Host "Validated original PR #$($source.Number), run $OriginalRunId and artifact $ArtifactId before download."
