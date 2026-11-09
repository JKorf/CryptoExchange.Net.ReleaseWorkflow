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
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if ($SelectedRef -cne "refs/heads/$($config.baseBranch)") { throw "Run this workflow from $($config.baseBranch)." }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$directory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$bodyPath = Join-Path $directory 'release-pr.md'
$planPath = Join-Path $directory 'plan.json'
& "$PSScriptRoot/Prepare-Release.ps1" -Version $Version -Notes $Notes -Package $Package -OverrideReason $OverrideReason -ConfigPath $ConfigPath -BodyPath $bodyPath -ResultPath $planPath -ValidateOnly
$plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
foreach ($ref in @("refs/tags/$($plan.tag)", "refs/heads/$($plan.branch)")) {
    git check-ref-format $ref
    if ($LASTEXITCODE -ne 0) { throw "Invalid release Git ref: $ref" }
}
$tag = @(git tag --list $plan.tag)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect existing release tags.' }
if ($tag.Count) { throw "Release tag already exists: $($plan.tag)" }
$branch = @(git branch --remotes --list "origin/$($plan.branch)")
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect existing release branches.' }
if ($branch.Count) { throw "Release branch already exists: $($plan.branch)" }
$commit = git rev-parse --verify HEAD
if ($LASTEXITCODE -ne 0) { throw 'A library Git checkout with a source commit is required.' }
$outputs = [ordered]@{
    requires_approval = $plan.requires_approval.ToString().ToLowerInvariant()
    sdk = $plan.sdk; package = $plan.package; package_id = $plan.package_id
    version = $plan.version; branch = $plan.branch; tag = $plan.tag; base_branch = $plan.base_branch
    body_path = $bodyPath; plan_path = $planPath
}
foreach ($entry in $outputs.GetEnumerator()) {
    if ([string]$entry.Value -match '[\r\n]') { throw "Unexpected newline in output $($entry.Key)." }
}
if ($env:GITHUB_OUTPUT) {
    foreach ($entry in $outputs.GetEnumerator()) { "$($entry.Key)=$($entry.Value)" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM }
}
if ($env:GITHUB_STEP_SUMMARY) {
    Get-Content -LiteralPath $bodyPath -Raw | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8NoBOM
    "`nSource commit: $commit" | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8NoBOM
}
Write-Host "Validation passed; approval required: $($outputs.requires_approval). Preview: $bodyPath"
