[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][long]$OriginalRunId,
    [Parameter(Mandatory)][long]$ArtifactId,
    [Parameter(Mandatory)][string]$ArtifactDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/Release-PackageFunctions.ps1"
$source = & "$PSScriptRoot/Get-RecoverySource.ps1" -Repository $Repository -OriginalRunId $OriginalRunId -ArtifactId $ArtifactId
$number = $source.Number
$manifest = Assert-ReleaseArtifacts $ArtifactDirectory $Repository $source.Commit $number
if ($manifest.sdk -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid SDK version in artifact manifest.' }
if ($source.Branch -cne "release/$($manifest.package)/$($manifest.version)") { throw 'Artifact package/version differs from the merged preparation PR.' }
$directory = (Resolve-Path -LiteralPath $ArtifactDirectory).Path
$outputs = [ordered]@{
    sdk = $manifest.sdk; commit = $source.Commit; pull_request = $number
    artifact_id = $ArtifactId; original_run_id = $OriginalRunId; artifact_name = $source.ArtifactName
    package_id = $manifest.packageId; version = $manifest.version; tag = $manifest.tag
    artifacts_path = $directory; manifest_path = (Join-Path $directory 'manifest.json')
}
foreach ($entry in $outputs.GetEnumerator()) {
    if ([string]$entry.Value -match '[\r\n]') { throw "Unexpected newline in recovery output $($entry.Key)." }
}
if ($env:GITHUB_OUTPUT) {
    foreach ($entry in $outputs.GetEnumerator()) { "$($entry.Key)=$($entry.Value)" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM }
}
if ($env:GITHUB_STEP_SUMMARY) {
    "Recover $($manifest.packageId) $($manifest.version) from PR #$number, source commit $($source.Commit), original run $OriginalRunId, artifact $ArtifactId. No packages will be rebuilt." | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8NoBOM
}
Write-Host 'Original source identity, package metadata and checksums verified for recovery.'
