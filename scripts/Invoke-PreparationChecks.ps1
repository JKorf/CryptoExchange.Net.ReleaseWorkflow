#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][string]$ResultsDirectory,
    [ValidateSet('true', 'false')][string]$IntegrationTests = 'false',
    [switch]$Publication
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $ResultsDirectory -Force | Out-Null
$ResultsDirectory = (Resolve-Path -LiteralPath $ResultsDirectory).Path
$testProjects = @(if ($Publication) { $plan.testProjects } else { $plan.test_projects })
$sourceArguments = @()
if ($Publication) {
    $sourceArguments = @("-p:RepositoryCommit=$($plan.commit)", "-p:SourceRevisionId=$($plan.commit)")
    $IntegrationTests = if ($plan.integrationTests) { 'true' } else { 'false' }
}
$projects = @(@($plan.project) + @($testProjects) | Select-Object -Unique)
foreach ($project in $projects) {
    dotnet restore $project
    if ($LASTEXITCODE -ne 0) { throw "Restore failed: $project" }
    dotnet build $project --configuration Release --no-restore -m:1 -p:GeneratePackageOnBuild=false @sourceArguments
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $project" }
}
$oldIntegration = $env:INTEGRATION
try {
    $env:INTEGRATION = if ($IntegrationTests -eq 'true') { '1' } else { '0' }
    $index = 0
    foreach ($project in @($testProjects)) {
        $index++
        $results = Join-Path $ResultsDirectory "project-$index"
        New-Item -ItemType Directory -Path $results -Force | Out-Null
        dotnet test $project --configuration Release --no-build --no-restore --verbosity normal --results-directory $results --logger trx -- "NUnit.TestOutputXml=$results" NUnit.NewOutputXmlFileForEachRun=true NUnit.MapWarningTo=Passed
        if ($LASTEXITCODE -ne 0) { throw "Tests failed: $project" }
    }
} finally { $env:INTEGRATION = $oldIntegration }
