#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][string]$BodyPath,
    [Parameter(Mandatory)][string]$ResultsDirectory,
    [string]$RunUrl = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
$summary = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $PlanPath).Path) 'test-warnings.md'
$expectResults = @($plan.test_projects).Count -gt 0
& "$PSScriptRoot/Add-TestWarnings.ps1" -ResultsDirectory $ResultsDirectory -BodyPath $BodyPath -SummaryPath $summary -RunUrl $RunUrl -ExpectResults:$expectResults
if ($env:GITHUB_OUTPUT) { "warnings_path=$summary" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM }
if ($env:GITHUB_STEP_SUMMARY) { Get-Content -LiteralPath $summary -Raw | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8NoBOM }
