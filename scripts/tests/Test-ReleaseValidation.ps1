$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scriptPath = (Resolve-Path "$PSScriptRoot/../Validate-Release.ps1").Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('validation-test-' + [guid]::NewGuid().ToString('N'))
& "$PSScriptRoot/New-ValidationFixture.ps1" -Directory $fixture -BaseBranch master
$oldOutput = $env:GITHUB_OUTPUT; $oldSummary = $env:GITHUB_STEP_SUMMARY
$env:GITHUB_OUTPUT = Join-Path $fixture 'output.txt'; $env:GITHUB_STEP_SUMMARY = Join-Path $fixture 'summary.md'
$checks = 0
Push-Location $fixture
try {
    $sourceHash = (Get-FileHash Example.csproj).Hash
    $readmeHash = (Get-FileHash README.md).Hash
    $notes = "- Feature 1`n  - Nested detail`n- Literal | pipe and `$value"
    function Validate([string]$Version = '1.3.1', [string]$Reason = '', [string]$Ref = 'refs/heads/master') {
        Set-Content -LiteralPath $env:GITHUB_OUTPUT -Value '' -NoNewline
        & $scriptPath -Version $Version -Notes $notes -OverrideReason $Reason -SelectedRef $Ref -OutputDirectory (Join-Path $fixture ([guid]::NewGuid().ToString('N')))
    }
    function Reject([scriptblock]$Action) {
        $failed = $false
        try { & $Action } catch { $failed = $true }
        if (-not $failed -or (Get-Content $env:GITHUB_OUTPUT -Raw)) { throw 'Invalid release was accepted or wrote success outputs.' }
        $script:checks++
    }
    Validate
    $outputs = Get-Content $env:GITHUB_OUTPUT -Raw
    if ($outputs -notmatch '(?m)^requires_approval=false\r?$' -or $outputs -notmatch '(?m)^package=example\r?$' -or $outputs -notmatch '(?m)^sdk=10.0.401\r?$') { throw 'Normal validation outputs are incorrect.' }
    if (-not (Get-Content $env:GITHUB_STEP_SUMMARY -Raw).Contains($notes)) { throw 'Multiline Markdown notes were altered.' }
    $checks += 2
    Validate '2.0.0' 'Breaking API changes'
    if ((Get-Content $env:GITHUB_OUTPUT -Raw) -notmatch '(?m)^requires_approval=true\r?$') { throw 'Major release bypassed approval.' }
    $checks++
    Reject { Validate '2.0.0' }
    Reject { Validate '1.3.1' '' 'refs/heads/main' }
    Reject { Validate '1.3.0' }
    git tag Example.1.3.1
    if ($LASTEXITCODE -ne 0) { throw 'Fixture tag setup failed.' }
    Reject { Validate }
    git update-ref refs/remotes/origin/release/example/1.4.0 HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Fixture remote branch setup failed.' }
    Reject { Validate '1.4.0' }
    if ((Get-FileHash Example.csproj).Hash -ne $sourceHash -or (Get-FileHash README.md).Hash -ne $readmeHash) { throw 'Validation modified library source.' }
    $checks++
    Write-Host "$checks validation checks passed using a separate sample library. No source updates or external requests."
} finally { Pop-Location; $env:GITHUB_OUTPUT = $oldOutput; $env:GITHUB_STEP_SUMMARY = $oldSummary }
