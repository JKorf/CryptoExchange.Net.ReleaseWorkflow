#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][long]$OriginalRunId,
    [Parameter(Mandatory)][long]$ArtifactId
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/Release-PackageFunctions.ps1"
if ($OriginalRunId -lt 1 -or $ArtifactId -lt 1) { throw 'Run and artifact IDs must be positive.' }
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Expected owner/repository.' }
$run = Invoke-ReleaseApi "repos/$Repository/actions/runs/$OriginalRunId"
if ($run.event -ne 'pull_request' -or $run.path -ne '.github/workflows/publish-release.yml' -or $run.display_title -notmatch '^Publish release PR #(?<number>[1-9][0-9]*)$') {
    throw 'Recovery requires an original merge-triggered publish-release.yml run.'
}
$number = [int]$Matches.number
if ($run.status -ne 'completed' -or $run.conclusion -eq 'success') { throw 'Only a completed, unsuccessful original run may be recovered.' }
$pr = Invoke-ReleaseApi "repos/$Repository/pulls/$number"
if (-not $pr.merged -or $pr.head.repo.full_name -cne $Repository -or $pr.base.repo.full_name -cne $Repository -or $pr.base.ref -notin @('main', 'master')) {
    throw 'Original PR must be merged from this repository into main/master.'
}
if ($pr.merge_commit_sha -cnotmatch '^[0-9a-f]{40}$') { throw 'Original PR has an invalid merged source commit.' }
if ($run.head_sha -cne $pr.merge_commit_sha -and ($run.head_sha -cne $pr.head.sha -or $run.head_branch -cne $pr.head.ref)) {
    throw 'Original run does not match the merged PR or its final head.'
}
$artifact = Invoke-ReleaseApi "repos/$Repository/actions/artifacts/$ArtifactId"
if ($artifact.expired -or $artifact.workflow_run.id -ne $OriginalRunId -or $artifact.name -notmatch "^release-pr-$number-attempt-[1-9][0-9]*$") {
    throw 'Artifact must be an unexpired release package artifact from the original run.'
}
[pscustomobject]@{
    Repository = $Repository; RunId = $OriginalRunId; ArtifactId = $ArtifactId
    Number = $number; Commit = $pr.merge_commit_sha; Branch = $pr.head.ref; ArtifactName = $artifact.name
}
