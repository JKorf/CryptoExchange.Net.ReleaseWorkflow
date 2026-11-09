#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][string]$ResultsDirectory,
    [ValidateSet('true', 'false')][string]$IntegrationTests = 'false'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $ResultsDirectory -Force | Out-Null
$ResultsDirectory = (Resolve-Path -LiteralPath $ResultsDirectory).Path
$projects = @(@($plan.project) + @($plan.test_projects) | Select-Object -Unique)
foreach ($project in $projects) {
    dotnet restore $project
    if ($LASTEXITCODE -ne 0) { throw "Restore failed: $project" }
    dotnet build $project --configuration Release --no-restore -m:1 -p:GeneratePackageOnBuild=false
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $project" }
}
$oldIntegration = $env:INTEGRATION
try {
    $env:INTEGRATION = if ($IntegrationTests -eq 'true') { '1' } else { '0' }
    $index = 0
    foreach ($project in @($plan.test_projects)) {
        $index++
        $results = Join-Path $ResultsDirectory "project-$index"
        New-Item -ItemType Directory -Path $results -Force | Out-Null
        dotnet test $project --configuration Release --no-build --no-restore --verbosity normal --results-directory $results --logger trx -- "NUnit.TestOutputXml=$results" NUnit.NewOutputXmlFileForEachRun=true NUnit.MapWarningTo=Passed
        if ($LASTEXITCODE -ne 0) { throw "Tests failed: $project" }
    }
} finally { $env:INTEGRATION = $oldIntegration }
