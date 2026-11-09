$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scripts = (Resolve-Path "$PSScriptRoot/..").Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('preparation-test-' + [guid]::NewGuid().ToString('N'))
& "$PSScriptRoot/New-ValidationFixture.ps1" -Directory $fixture
$oldOutput = $env:GITHUB_OUTPUT; $oldSummary = $env:GITHUB_STEP_SUMMARY; $oldIntegration = $env:INTEGRATION
$output = Join-Path ([IO.Path]::GetTempPath()) ('preparation-output-' + [guid]::NewGuid().ToString('N'))
$env:GITHUB_OUTPUT = $output
$env:GITHUB_STEP_SUMMARY = "$output.summary"
$directory = "$output.files"
$notes = "- Feature`n  - Nested detail"
$checks = 0
function Reject([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action } catch { if ($_.Exception.Message -notlike "*$Message*") { throw }; $failed = $true }
    if (-not $failed) { throw "Expected preparation failure: $Message" }
    $script:checks++
}
Push-Location $fixture
try {
    git remote add origin $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create local fixture origin.' }
    git update-ref refs/heads/release/example/1.3.1 HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create fixture collision.' }
    $hash = (Get-FileHash Example.csproj).Hash
    Reject { & "$scripts/Initialize-ReleasePreparation.ps1" -Version 1.3.1 -Notes $notes -SelectedRef refs/heads/main -OutputDirectory $directory } 'Tag or branch already exists'
    if ((Get-FileHash Example.csproj).Hash -ne $hash) { throw 'Remote collision modified source.' }
    git update-ref -d refs/heads/release/example/1.3.1
    if ($LASTEXITCODE -ne 0) { throw 'Cannot reset fixture collision.' }
    & "$scripts/Initialize-ReleasePreparation.ps1" -Version 1.3.1 -Notes $notes -SelectedRef refs/heads/main -OutputDirectory $directory
    if (([xml](Get-Content Example.csproj -Raw)).Project.PropertyGroup.PackageVersion -ne '1.3.1') { throw 'Project version was not updated.' }
    $readme = (Get-Content README.md -Raw).ReplaceLineEndings("`n")
    if (-not $readme.Contains("    - Feature`n      - Nested detail")) { throw 'README notes lost indentation.' }
    $checks += 2
    $planPath = Join-Path $directory 'plan.json'; $bodyPath = Join-Path $directory 'release-pr.md'; $results = Join-Path $directory 'test-results'
    $plan = Get-Content $planPath -Raw | ConvertFrom-Json
    $plan.test_projects = @('Example.Tests.csproj')
    $plan | ConvertTo-Json -Depth 8 | Set-Content $planPath -Encoding utf8NoBOM
    $preparationMock = @{ Calls = [Collections.Generic.List[string]]::new(); Fail = ''; Integration = '' }
    function dotnet {
        $command = [string]$args[0]
        $preparationMock.Calls.Add(($args -join ' '))
        Set-Variable LASTEXITCODE 0 -Scope Global
        if ($preparationMock.Fail -eq $command) { Set-Variable LASTEXITCODE 1 -Scope Global; return }
        if ($command -eq 'test') {
            $preparationMock.Integration = $env:INTEGRATION
            $index = [array]::IndexOf($args, '--results-directory')
            '<test-run><test-case name="WarningTest" result="Warning"><assertions><assertion result="Warning"><message>Missing property example</message></assertion></assertions></test-case></test-run>' |
                Set-Content -LiteralPath (Join-Path $args[$index + 1] 'nunit.xml')
        }
    }
    $env:INTEGRATION = 'previous-value'
    & "$scripts/Invoke-PreparationChecks.ps1" -PlanPath $planPath -ResultsDirectory $results -IntegrationTests true
    if ($preparationMock.Integration -ne '1' -or $env:INTEGRATION -ne 'previous-value') { throw 'Integration setting/restore failed.' }
    if ($preparationMock.Calls.Count -ne 5 -or ($preparationMock.Calls | Where-Object { $_ -like 'build*' -and $_ -notmatch '-m:\s*1' })) { throw "Unexpected build/test calls: $($preparationMock.Calls -join '; ')" }
    & "$scripts/Complete-ReleasePreparation.ps1" -PlanPath $planPath -BodyPath $bodyPath -ResultsDirectory $results
    $body = Get-Content $bodyPath -Raw
    if (-not $body.Contains('Missing property example') -or -not $body.Contains($notes)) { throw 'PR warning summary or original notes were lost.' }
    $checks += 3
    $preparationMock.Fail = 'test'
    Reject { & "$scripts/Invoke-PreparationChecks.ps1" -PlanPath $planPath -ResultsDirectory $results } 'Tests failed'
    if ($env:INTEGRATION -ne 'previous-value') { throw 'Failed test did not restore integration setting.' }
    $preparationMock.Fail = 'build'
    $preparationMock.Calls.Clear()
    Reject { & "$scripts/Invoke-PreparationChecks.ps1" -PlanPath $planPath -ResultsDirectory $results } 'Build failed'
    if ($preparationMock.Calls | Where-Object { $_ -like 'test*' }) { throw 'Tests ran after a failed build.' }
    $empty = Join-Path $directory 'empty-results'; New-Item -ItemType Directory -Path $empty | Out-Null
    Reject { & "$scripts/Complete-ReleasePreparation.ps1" -PlanPath $planPath -BodyPath $bodyPath -ResultsDirectory $empty } 'No NUnit XML'
    $checks++
    Write-Host "$checks preparation checks passed. Git origin and test reports are local fixtures; dotnet is mocked."
} finally { Pop-Location; $env:GITHUB_OUTPUT = $oldOutput; $env:GITHUB_STEP_SUMMARY = $oldSummary; $env:INTEGRATION = $oldIntegration }
