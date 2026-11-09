param(
    [string]$ArtifactDirectory = '',
    [long]$OriginalRunId = 100,
    [long]$ArtifactId = 200,
    [string]$ArtifactName = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scripts = (Resolve-Path "$PSScriptRoot/..").Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('recovery-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
if (-not $ArtifactDirectory) {
    $ArtifactDirectory = Join-Path $fixture 'release'
    New-Item -ItemType Directory -Path $ArtifactDirectory | Out-Null
    $commit = 'a' * 40
    foreach ($name in @('Example.2.0.0.nupkg', 'Example.2.0.0.snupkg')) {
        $zip = [IO.Compression.ZipFile]::Open((Join-Path $ArtifactDirectory $name), [IO.Compression.ZipArchiveMode]::Create)
        try {
            $writer = [IO.StreamWriter]::new($zip.CreateEntry('Example.nuspec').Open())
            try { $writer.Write("<package><metadata><id>Example</id><version>2.0.0</version><repository url='https://github.com/owner/library' commit='$commit'/></metadata></package>") } finally { $writer.Dispose() }
        } finally { $zip.Dispose() }
    }
    "- Feature`n  - Nested detail" | Set-Content (Join-Path $ArtifactDirectory 'release-notes.md') -Encoding utf8NoBOM
    $manifest = @{ repository = 'owner/library'; pullRequest = 7; commit = $commit; sdk = '10.0.401'; package = 'example'; packageId = 'Example'; version = '2.0.0'; tag = 'Example.2.0.0'; packageFile = 'Example.2.0.0.nupkg'; symbolFile = 'Example.2.0.0.snupkg' }
    $manifest.files = @('Example.2.0.0.nupkg', 'Example.2.0.0.snupkg', 'release-notes.md') | ForEach-Object { @{ name = $_; sha256 = (Get-FileHash (Join-Path $ArtifactDirectory $_)).Hash } }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $ArtifactDirectory 'manifest.json') -Encoding utf8NoBOM
}
$ArtifactDirectory = (Resolve-Path -LiteralPath $ArtifactDirectory).Path
$manifest = Get-Content (Join-Path $ArtifactDirectory 'manifest.json') -Raw | ConvertFrom-Json
if (-not $ArtifactName) { $ArtifactName = "release-pr-$($manifest.pullRequest)-attempt-1" }
$recoveryRun = @{ event = 'pull_request'; path = '.github/workflows/publish-release.yml'; display_title = "Publish release PR #$($manifest.pullRequest)"; status = 'completed'; conclusion = 'failure'; head_sha = 'original-pr-head'; head_branch = "release/$($manifest.package)/$($manifest.version)" }
$recoveryPr = @{ merged = $true; merge_commit_sha = $manifest.commit; head = @{ sha = 'original-pr-head'; ref = $recoveryRun.head_branch; repo = @{ full_name = $manifest.repository } }; base = @{ ref = 'main'; repo = @{ full_name = $manifest.repository } } }
$recoveryArtifact = @{ expired = $false; name = $ArtifactName; workflow_run = @{ id = $OriginalRunId } }
# Model GitHub metadata as a failed merge run. CI may supply real, downloaded
# sample packages, but no real failed PR/run is created and no GitHub API is called.
function Invoke-RestMethod([string]$Uri, [string]$Method, [hashtable]$Headers, [switch]$SkipHttpErrorCheck, [string]$StatusCodeVariable) {
    Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1
    if ($Uri.EndsWith("/actions/runs/$OriginalRunId")) { return $recoveryRun }
    if ($Uri.EndsWith("/pulls/$($manifest.pullRequest)")) { return $recoveryPr }
    if ($Uri.EndsWith("/actions/artifacts/$ArtifactId")) { return $recoveryArtifact }
    throw 'Unexpected recovery API request.'
}
function dotnet { throw 'Recovery must not rebuild or push packages.' }
function git { throw 'Recovery must not change Git refs.' }
function gh { throw 'Recovery must not create a release.' }
$oldOutput = $env:GITHUB_OUTPUT; $oldSummary = $env:GITHUB_STEP_SUMMARY
$env:GITHUB_OUTPUT = Join-Path $fixture 'outputs'; $env:GITHUB_STEP_SUMMARY = Join-Path $fixture 'summary'
$baseline = @{}
foreach ($file in Get-ChildItem -LiteralPath $ArtifactDirectory -File) { $baseline[$file.Name] = (Get-FileHash $file.FullName).Hash }
$checks = 0
function Recover {
    Set-Content -LiteralPath $env:GITHUB_OUTPUT -Value '' -NoNewline
    & "$scripts/Get-RecoveryPlan.ps1" -Repository $manifest.repository -OriginalRunId $OriginalRunId -ArtifactId $ArtifactId -ArtifactDirectory $ArtifactDirectory
}
function Reject([scriptblock]$Action, [string]$Expected) {
    $failed = $false
    try { & $Action } catch { if ($_.Exception.Message -notlike "*$Expected*") { throw }; $failed = $true }
    if (-not $failed -or (Get-Content $env:GITHUB_OUTPUT -Raw)) { throw "Invalid recovery was accepted or wrote outputs: $Expected" }
    $script:checks++
}
try {
    $downloadPath = Join-Path $fixture 'download'
    & "$scripts/Initialize-ReleaseRecovery.ps1" -Repository $manifest.repository -OriginalRunId $OriginalRunId -ArtifactId $ArtifactId -OutputDirectory $downloadPath
    if (-not (Test-Path $downloadPath) -or (Get-ChildItem $downloadPath -File)) { throw 'Recovery preflight should only create an empty download directory.' }
    Recover
    $outputs = @{}; foreach ($line in Get-Content $env:GITHUB_OUTPUT) { $parts = $line.Split('=', 2); $outputs[$parts[0]] = $parts[1] }
    if ($outputs.commit -ne $manifest.commit -or $outputs.artifact_id -ne [string]$ArtifactId -or $outputs.version -ne $manifest.version -or $outputs.artifacts_path -ne $ArtifactDirectory) { throw 'Recovery output identity changed.' }
    $checks += 2
    $recoveryRun.head_sha = $manifest.commit; Recover; $recoveryRun.head_sha = 'original-pr-head'; $checks++
    $recoveryRun.status = 'in_progress'; Reject { Recover } 'completed, unsuccessful'; $recoveryRun.status = 'completed'
    $recoveryRun.conclusion = 'success'; Reject { Recover } 'completed, unsuccessful'; $recoveryRun.conclusion = 'failure'
    $recoveryRun.head_sha = 'unrelated'; Reject { Recover } 'does not match'; $recoveryRun.head_sha = 'original-pr-head'
    $recoveryRun.path = '.github/workflows/test.yml'; Reject { Recover } 'merge-triggered'; $recoveryRun.path = '.github/workflows/publish-release.yml'
    $recoveryPr.head.repo.full_name = 'fork/library'; Reject { Recover } 'from this repository'; $recoveryPr.head.repo.full_name = $manifest.repository
    $recoveryArtifact.expired = $true; Reject { Recover } 'unexpired'; $recoveryArtifact.expired = $false
    $recoveryArtifact.workflow_run.id = $OriginalRunId + 1; Reject { Recover } 'from the original run'; $recoveryArtifact.workflow_run.id = $OriginalRunId
    $recoveryArtifact.name = 'publication-test-results-1'; Reject { Recover } 'release package artifact'; $recoveryArtifact.name = $ArtifactName
    $notesPath = Join-Path $ArtifactDirectory 'release-notes.md'
    $notesBytes = [IO.File]::ReadAllBytes($notesPath)
    try {
        Add-Content -LiteralPath $notesPath 'Unexpected change'
        Reject { Recover } 'checksum mismatch'
    } finally { [IO.File]::WriteAllBytes($notesPath, $notesBytes) }
    foreach ($name in $baseline.Keys) {
        if ((Get-FileHash (Join-Path $ArtifactDirectory $name)).Hash -ne $baseline[$name]) { throw 'Recovery changed artifact contents.' }
    }
    $checks++
    Write-Host "$checks recovery checks passed. Package bytes are unchanged; GitHub metadata is mocked and no publishing commands ran."
} finally { $env:GITHUB_OUTPUT = $oldOutput; $env:GITHUB_STEP_SUMMARY = $oldSummary }
