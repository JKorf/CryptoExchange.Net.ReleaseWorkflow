$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scripts = (Resolve-Path "$PSScriptRoot/..").Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('build-test-' + [guid]::NewGuid().ToString('N'))
& "$PSScriptRoot/New-ValidationFixture.ps1" -Directory $fixture
$oldExit = $LASTEXITCODE
$oldOutput = $env:GITHUB_OUTPUT; $oldSummary = $env:GITHUB_STEP_SUMMARY; $oldIntegration = $env:INTEGRATION
$root = Join-Path ([IO.Path]::GetTempPath()) ('build-output-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$env:GITHUB_OUTPUT = Join-Path $root 'outputs'; $env:GITHUB_STEP_SUMMARY = Join-Path $root 'summary'
$checks = 0
function Reject([scriptblock]$Action, [string]$Expected) {
    $failed = $false
    try { & $Action } catch { if ($_.Exception.Message -notlike "*$Expected*") { throw }; $failed = $true }
    if (-not $failed) { throw "Expected final build failure: $Expected" }
    $script:checks++
}
Push-Location $fixture
try {
    '<Project />' | Set-Content Example.Tests.csproj
    $config = Get-Content .github/release-config.json -Raw | ConvertFrom-Json
    $config.packages[0].testProjects = @('Example.Tests.csproj')
    $config.packages[0] | Add-Member releaseIntegrationTests $true
    $config | ConvertTo-Json -Depth 8 | Set-Content .github/release-config.json
    "## Release notes`n* Version 1.3.0 - Before`n    - Feature`n      - Nested detail" | Set-Content README.md
    git add Example.Tests.csproj .github/release-config.json README.md
    git -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m 'Test release inputs'
    if ($LASTEXITCODE -ne 0) { throw 'Could not commit build fixture.' }
    $commit = git rev-parse HEAD
    $event = @{ action = 'closed'; pull_request = @{ number = 77; merged = $true; merge_commit_sha = $commit; head = @{ ref = 'release/example/1.3.0'; repo = @{ full_name = 'owner/library' } }; base = @{ ref = 'main'; repo = @{ full_name = 'owner/library' } } } }
    $eventPath = Join-Path $root 'event.json'; $event | ConvertTo-Json -Depth 8 | Set-Content $eventPath
    $directory = Join-Path $root 'valid'
    Add-Content README.md 'uncommitted edit'
    Reject { & "$scripts/Initialize-ReleaseBuild.ps1" -EventPath $eventPath -Repository owner/library -OutputDirectory $directory } 'clean checkout'
    git restore README.md
    if ($LASTEXITCODE -ne 0) { throw 'Could not reset build fixture.' }
    & "$scripts/Initialize-ReleaseBuild.ps1" -EventPath $eventPath -Repository owner/library -OutputDirectory $directory
    $manifestPath = Join-Path $directory 'release/manifest.json'; $results = Join-Path $directory 'test-results'
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.commit -ne $commit -or $manifest.pullRequest -ne 77) { throw 'Source identity was lost.' }
    $checks++
    $buildMock = @{ Calls = [Collections.Generic.List[string]]::new(); Fail = ''; Integration = ''; Plan = $manifest }
    function dotnet {
        $command = [string]$args[0]
        $buildMock.Calls.Add(($args -join ' '))
        Set-Variable LASTEXITCODE 0 -Scope Global
        if ($buildMock.Fail -eq $command) { Set-Variable LASTEXITCODE 1 -Scope Global; return }
        if ($command -eq 'test') {
            $buildMock.Integration = $env:INTEGRATION
            $index = [array]::IndexOf($args, '--results-directory')
            '<test-run><test-case name="FinalWarning" result="Warning"><failure><message>Final warning details</message></failure></test-case></test-run>' |
                Set-Content -LiteralPath (Join-Path $args[$index + 1] 'nunit.xml')
        }
        if ($command -eq 'pack') {
            $index = [array]::IndexOf($args, '--output'); $destination = $args[$index + 1]
            foreach ($name in @($buildMock.Plan.packageFile, $buildMock.Plan.symbolFile)) {
                $stream = [IO.FileStream]::new((Join-Path $destination $name), [IO.FileMode]::Create)
                $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
                try {
                    $entry = $zip.CreateEntry('Example.nuspec')
                    $writer = [IO.StreamWriter]::new($entry.Open())
                    try { $writer.Write("<package><metadata><id>Example</id><version>1.3.0</version><repository url='https://github.com/owner/library' commit='$($buildMock.Plan.commit)'/></metadata></package>") } finally { $writer.Dispose() }
                } finally { $zip.Dispose(); $stream.Dispose() }
            }
        }
    }
    $env:INTEGRATION = 'previous-value'
    & "$scripts/Invoke-PreparationChecks.ps1" -PlanPath $manifestPath -ResultsDirectory $results -Publication
    if ($buildMock.Integration -ne '1' -or $env:INTEGRATION -ne 'previous-value') { throw 'Final integration-test policy was not respected.' }
    if (@($buildMock.Calls | Where-Object { $_ -like 'build*' -and $_ -like "*RepositoryCommit=$commit*" }).Count -ne 2) { throw 'Builds were not tied to source commit.' }
    $checks += 2
    & "$scripts/Complete-ReleaseBuild.ps1" -ManifestPath $manifestPath -ResultsDirectory $results
    $verified = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if (@($verified.files).Count -ne 3) { throw 'Package/notes checksums are missing.' }
    $review = (Get-Content (Join-Path $directory 'release/release-summary.md') -Raw).ReplaceLineEndings("`n")
    if (-not $review.Contains('Final warning details') -or -not $review.Contains("- Feature`n  - Nested detail")) { throw 'Review lost final warnings or nested notes.' }
    $checks += 2
    $buildMock.Fail = 'test'
    Reject { & "$scripts/Invoke-PreparationChecks.ps1" -PlanPath $manifestPath -ResultsDirectory $results -Publication } 'Tests failed'
    $buildMock.Fail = 'build'
    Reject { & "$scripts/Invoke-PreparationChecks.ps1" -PlanPath $manifestPath -ResultsDirectory $results -Publication } 'Build failed'
    $buildMock.Fail = 'pack'
    Reject { & "$scripts/Complete-ReleaseBuild.ps1" -ManifestPath $manifestPath -ResultsDirectory $results } 'Packing failed'
    $buildMock.Fail = ''
    $empty = Join-Path $root 'empty-results'; New-Item -ItemType Directory -Path $empty | Out-Null
    Reject { & "$scripts/Complete-ReleaseBuild.ps1" -ManifestPath $manifestPath -ResultsDirectory $empty } 'No NUnit XML'
    Write-Host "$checks final build checks passed. No packages were published; dotnet and test XML are local fixtures."
} finally {
    Pop-Location
    $env:GITHUB_OUTPUT = $oldOutput; $env:GITHUB_STEP_SUMMARY = $oldSummary; $env:INTEGRATION = $oldIntegration
    Set-Variable LASTEXITCODE $oldExit -Scope Global
}
