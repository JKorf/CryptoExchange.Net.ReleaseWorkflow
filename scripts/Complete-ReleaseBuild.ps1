#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$ResultsDirectory,
    [string]$RunUrl = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
$directory = Split-Path -Parent $ManifestPath
$plan = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
dotnet pack $plan.project --configuration Release --no-build --no-restore --output $directory -p:IncludeSymbols=true -p:SymbolPackageFormat=snupkg "-p:RepositoryCommit=$($plan.commit)" "-p:SourceRevisionId=$($plan.commit)"
if ($LASTEXITCODE -ne 0) { throw 'Packing failed.' }
$files = @($plan.packageFile, $plan.symbolFile, 'release-notes.md') | ForEach-Object {
    @{ name = $_; sha256 = (Get-FileHash -LiteralPath (Join-Path $directory $_) -Algorithm SHA256).Hash }
}
$plan | Add-Member -NotePropertyName files -NotePropertyValue @($files) -Force
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding utf8NoBOM
& "$PSScriptRoot/Publish-Release.ps1" -ArtifactDirectory $directory -Repository $plan.repository -Commit $plan.commit -PullRequest $plan.pullRequest -ValidateOnly
$summary = "# Publication review`n`nPackage: $($plan.packageId) $($plan.version)`n`nPR: #$($plan.pullRequest)`n`nCommit: $($plan.commit)`n`nTag: $($plan.tag)`n`nIntegration tests enabled: $($plan.integrationTests)`n`nGitHub Packages enabled: $($plan.publishToGitHubPackages)`n`n## Release notes`n`n"
$summary += Get-Content -LiteralPath (Join-Path $directory 'release-notes.md') -Raw
$summary += "`n## Artifact SHA256 checksums`n`n"
foreach ($file in $plan.files) { $summary += "$($file.name): $($file.sha256)`n`n" }
$reviewPath = Join-Path $directory 'release-summary.md'
$summary | Set-Content -LiteralPath $reviewPath -Encoding utf8NoBOM
$warningPath = Join-Path (Split-Path -Parent $directory) 'test-warnings.md'
& "$PSScriptRoot/Add-TestWarnings.ps1" -ResultsDirectory $ResultsDirectory -BodyPath $reviewPath -SummaryPath $warningPath -RunUrl $RunUrl -Stage Publication -ExpectResults:(@($plan.testProjects).Count -gt 0)
if ($env:GITHUB_STEP_SUMMARY) { Get-Content -LiteralPath $reviewPath -Raw | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8NoBOM }
if ($env:GITHUB_OUTPUT) { "summary_path=$reviewPath" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM }
