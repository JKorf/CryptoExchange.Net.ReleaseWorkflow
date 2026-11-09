#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EventPath,
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$ConfigPath = '.github/release-config.json'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$directory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$artifacts = Join-Path $directory 'release'
$results = Join-Path $directory 'test-results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
if ($env:GITHUB_OUTPUT) { "results_path=$results" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM }
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'A library Git checkout is required.' }
if ($changes.Count) { throw 'Final release build requires a clean checkout of the merged source commit.' }
& "$PSScriptRoot/Get-PublishPlan.ps1" -EventPath $EventPath -Repository $Repository -ConfigPath $ConfigPath -OutputDirectory $artifacts
$manifestPath = Join-Path $artifacts 'manifest.json'
$plan = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$attempt = if ($env:GITHUB_RUN_ATTEMPT) { $env:GITHUB_RUN_ATTEMPT } else { '1' }
if ($attempt -notmatch '^[1-9][0-9]*$') { throw 'Invalid workflow run attempt.' }
$outputs = [ordered]@{
    sdk = $plan.sdk; commit = $plan.commit; pull_request = $plan.pullRequest
    package = $plan.package; package_id = $plan.packageId; version = $plan.version
    tag = $plan.tag; manifest_path = $manifestPath; artifacts_path = $artifacts
    artifact_name = "release-pr-$($plan.pullRequest)-attempt-$attempt"
    test_artifact_name = "publication-test-results-$($plan.pullRequest)-$attempt"
}
foreach ($entry in $outputs.GetEnumerator()) {
    if ([string]$entry.Value -match '[\r\n]') { throw "Unexpected newline in output $($entry.Key)." }
}
if ($env:GITHUB_OUTPUT) {
    foreach ($entry in $outputs.GetEnumerator()) { "$($entry.Key)=$($entry.Value)" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM }
}
