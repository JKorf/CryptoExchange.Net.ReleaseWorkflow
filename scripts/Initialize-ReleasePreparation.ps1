#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$Notes,
    [string]$Package = '',
    [string]$OverrideReason = '',
    [string]$ConfigPath = '.github/release-config.json',
    [Parameter(Mandatory)][string]$SelectedRef,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$directory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$results = Join-Path $directory 'test-results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
if ($env:GITHUB_OUTPUT) { "results_path=$results" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM }
& "$PSScriptRoot/Validate-Release.ps1" -Version $Version -Notes $Notes -Package $Package -OverrideReason $OverrideReason -ConfigPath $ConfigPath -SelectedRef $SelectedRef -OutputDirectory $directory
$planPath = Join-Path $directory 'plan.json'
$bodyPath = Join-Path $directory 'release-pr.md'
$plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
# Check the remote before changing source; the caller checks out with full history.
$refs = @(git ls-remote origin "refs/tags/$($plan.tag)" "refs/heads/$($plan.branch)")
if ($LASTEXITCODE -ne 0) { throw 'Cannot check remote release references.' }
if ($refs.Count) { throw "Tag or branch already exists. Inspect before retrying: $($refs -join ', ')" }
& "$PSScriptRoot/Prepare-Release.ps1" -Version $Version -Notes $Notes -Package $Package -OverrideReason $OverrideReason -ConfigPath $ConfigPath -BodyPath $bodyPath -ResultPath $planPath
