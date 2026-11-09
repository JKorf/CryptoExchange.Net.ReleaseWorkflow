$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$publisher = (Resolve-Path "$PSScriptRoot/../Publish-Release.ps1").Path
$root = Join-Path ([IO.Path]::GetTempPath()) ('publishing-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$oldEnvironment = @{}
foreach ($name in @('GH_TOKEN', 'GITHUB_PACKAGES_TOKEN', 'NUGET_API_KEY', 'GITHUB_OUTPUT', 'GITHUB_STEP_SUMMARY')) { $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name) }
$oldExitVariable = Get-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
$hadExit = $null -ne $oldExitVariable
$oldExit = if ($hadExit) { $oldExitVariable.Value } else { 0 }
$commit = 'a' * 40
$checks = 0
function NewCase([bool]$GitHubPackages = $true) {
    $path = Join-Path $root ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path | Out-Null
    foreach ($name in @('Example.2.0.0.nupkg', 'Example.2.0.0.snupkg')) {
        $zip = [IO.Compression.ZipFile]::Open((Join-Path $path $name), [IO.Compression.ZipArchiveMode]::Create)
        try {
            $writer = [IO.StreamWriter]::new($zip.CreateEntry('Example.nuspec').Open())
            try { $writer.Write("<package><metadata><id>Example</id><version>2.0.0</version><repository url='https://github.com/owner/library' commit='$commit'/></metadata></package>") } finally { $writer.Dispose() }
        } finally { $zip.Dispose() }
    }
    "- Feature`n  - Nested detail" | Set-Content (Join-Path $path 'release-notes.md') -Encoding utf8NoBOM
    $manifest = @{ repository = 'owner/library'; commit = $commit; pullRequest = 7; packageId = 'Example'; version = '2.0.0'; tag = 'Example.2.0.0'; publishToGitHubPackages = $GitHubPackages; packageFile = 'Example.2.0.0.nupkg'; symbolFile = 'Example.2.0.0.snupkg' }
    $manifest.files = @($manifest.packageFile, $manifest.symbolFile, 'release-notes.md') | ForEach-Object { @{ name = $_; sha256 = (Get-FileHash (Join-Path $path $_)).Hash } }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $path 'manifest.json') -Encoding utf8NoBOM
    $assets = Join-Path $path 'remote-assets'; New-Item -ItemType Directory -Path $assets | Out-Null
    return @{ Path = $path; Assets = $assets; Tag = $null; Release = $null; Remote = @{}; Pushes = [Collections.Generic.List[object]]::new(); GitTokens = [Collections.Generic.List[string]]::new(); Downloads = 0; Uploads = 0; Tags = 0; Drafts = 0; FailSource = ''; FailSymbols = $false; NeverIndex = $false }
}
function Invoke-RestMethod([string]$Uri, [string]$Method = 'GET', [hashtable]$Headers, [switch]$SkipHttpErrorCheck, [string]$StatusCodeVariable, [string]$Body, [string]$ContentType) {
    if ($Uri.EndsWith('/index.json')) {
        $base = if ($Uri.Contains('nuget.pkg.github.com')) { 'https://nuget.pkg.github.com/owner/flat/' } else { 'https://api.nuget.org/flat/' }
        return [pscustomobject]@{ resources = @([pscustomobject]@{ '@type' = 'PackageBaseAddress/3.0.0'; '@id' = $base }) }
    }
    if (-not $Uri.StartsWith('https://api.github.com/repos/owner/library/')) { throw 'Unexpected publishing API request.' }
    $publishMock.GitTokens.Add($Headers.Authorization)
    Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1
    $path = ([uri]$Uri).AbsolutePath
    if ($path.Contains('/git/ref/tags/')) {
        if ($null -eq $publishMock.Tag) { Set-Variable -Name $StatusCodeVariable -Value 404 -Scope 1; return $null }
        return [pscustomobject]@{ object = [pscustomobject]@{ type = 'commit'; sha = $publishMock.Tag } }
    }
    if ($path.EndsWith('/git/refs') -and $Method -eq 'POST') {
        $publishMock.Tag = ($Body | ConvertFrom-Json).sha; $publishMock.Tags++
        return [pscustomobject]@{ ref = 'refs/tags/Example.2.0.0' }
    }
    if ($path.Contains('/releases/tags/')) {
        if ($null -eq $publishMock.Release -or $publishMock.Release.draft) { Set-Variable -Name $StatusCodeVariable -Value 404 -Scope 1; return $null }
        return $publishMock.Release
    }
    if ($path.EndsWith('/releases') -and $Method -eq 'GET') {
        if ($null -ne $publishMock.Release) { return @($publishMock.Release) }
        return @()
    }
    if ($path.EndsWith('/releases') -and $Method -eq 'POST') {
        $request = $Body | ConvertFrom-Json
        if ($request.target_commitish -ne $commit -or -not $request.draft) { throw 'Draft did not use approved source.' }
        $publishMock.Release = [pscustomobject]@{ id = 1; tag_name = 'Example.2.0.0'; draft = $true; html_url = 'https://github.com/owner/library/releases/tag/Example.2.0.0'; assets = @(); body = $request.body }
        $publishMock.Drafts++
        return $publishMock.Release
    }
    if ($path.EndsWith('/releases/1') -and $Method -eq 'PATCH') { $publishMock.Release.draft = $false; return $publishMock.Release }
    throw 'Unexpected publishing API operation.'
}
function Invoke-WebRequest([string]$Uri, [hashtable]$Headers, [string]$OutFile, [switch]$SkipHttpErrorCheck, [switch]$PassThru) {
    $registry = if ($Uri.Contains('nuget.pkg.github.com')) { 'github' } else { 'nuget' }
    $publishMock.Downloads++
    if ($registry -eq 'github') {
        $expected = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('owner:test-package-token'))
        if ($Headers.Authorization -ne $expected) { throw 'Registry lookup used the wrong credential.' }
    }
    if ($publishMock.Remote.ContainsKey($registry)) {
        Copy-Item -LiteralPath $publishMock.Remote[$registry] -Destination $OutFile
        return [pscustomobject]@{ StatusCode = 200 }
    }
    'not found' | Set-Content -LiteralPath $OutFile
    return [pscustomobject]@{ StatusCode = 404 }
}
function gh {
    Set-Variable LASTEXITCODE 0 -Scope Global
    if ($env:GH_TOKEN -ne 'test-app-token') { throw 'Release CLI used the wrong credential.' }
    if ($args[1] -eq 'upload') {
        $name = Split-Path -Leaf $args[3]
        Copy-Item -LiteralPath $args[3] -Destination (Join-Path $publishMock.Assets $name)
        $publishMock.Release.assets += [pscustomobject]@{ name = $name }
        $publishMock.Uploads++
    } elseif ($args[1] -eq 'download') {
        $name = $args[([array]::IndexOf($args, '--pattern') + 1)]
        $destination = $args[([array]::IndexOf($args, '--dir') + 1)]
        Copy-Item -LiteralPath (Join-Path $publishMock.Assets $name) -Destination (Join-Path $destination $name)
    } else { throw 'Unexpected release CLI operation.' }
}
function dotnet {
    Set-Variable LASTEXITCODE 0 -Scope Global
    if ($args[0] -ne 'nuget' -or $args[1] -ne 'push') { throw 'Publishing must not restore/build/pack.' }
    $source = $args[([array]::IndexOf($args, '--source') + 1)]
    $key = $args[([array]::IndexOf($args, '--api-key') + 1)]
    $registry = if ($source.Contains('nuget.pkg.github.com')) { 'github' } else { 'nuget' }
    $symbols = ([string]$args[2]).EndsWith('.snupkg')
    $publishMock.Pushes.Add([pscustomobject]@{ Registry = $registry; Symbols = $symbols; Key = $key })
    if ($symbols) {
        if ($publishMock.FailSymbols) { Set-Variable LASTEXITCODE 1 -Scope Global }
        return
    }
    if ($publishMock.FailSource -eq $registry) { Set-Variable LASTEXITCODE 1 -Scope Global; return }
    if (-not ($publishMock.NeverIndex -and $registry -eq 'nuget')) { $publishMock.Remote[$registry] = $args[2] }
}
function Publish([switch]$ValidateOnly) {
    Set-Content -LiteralPath $env:GITHUB_OUTPUT -Value '' -NoNewline
    & $publisher -ArtifactDirectory $publishMock.Path -Repository owner/library -Commit $commit -PullRequest 7 -ValidateOnly:$ValidateOnly
}
function Reject([string]$Expected) {
    $failed = $false
    try { Publish } catch { if ($_.Exception.Message -notlike "*$Expected*") { throw }; $failed = $true }
    if (-not $failed -or (Get-Content $env:GITHUB_OUTPUT -Raw)) { throw "Expected failure without publication outputs: $Expected" }
}
try {
    $env:GITHUB_OUTPUT = Join-Path $root 'outputs'; $env:GITHUB_STEP_SUMMARY = Join-Path $root 'summary'
    $publishMock = NewCase
    $env:GH_TOKEN = ''; $env:GITHUB_PACKAGES_TOKEN = ''; $env:NUGET_API_KEY = ''
    Publish -ValidateOnly
    if ((Get-Content $env:GITHUB_OUTPUT -Raw) -notmatch 'published=false' -or $publishMock.Downloads -ne 0) { throw 'Validation-only published or queried a registry.' }
    $checks++
    $env:GH_TOKEN = 'test-app-token'; $env:GITHUB_PACKAGES_TOKEN = 'test-package-token'; $env:NUGET_API_KEY = 'test-nuget-key'
    $publishMock = NewCase; Publish
    if ($publishMock.Release.draft -or $publishMock.Uploads -ne 4 -or $publishMock.Pushes.Count -ne 3) { throw 'Publication did not complete.' }
    if (@($publishMock.GitTokens | Where-Object { $_ -ne 'Bearer test-app-token' }).Count -or @($publishMock.Pushes | Where-Object { ($_.Registry -eq 'github' -and $_.Key -ne 'test-package-token') -or ($_.Registry -eq 'nuget' -and $_.Key -ne 'test-nuget-key') }).Count) { throw 'Credential separation failed.' }
    if (-not $publishMock.Release.body.Contains("- Feature`n  - Nested detail") -or (Get-Content $env:GITHUB_OUTPUT -Raw) -notmatch 'published=true') { throw 'Published notes or outputs are incorrect.' }
    $checks++
    $publishMock = NewCase; $publishMock.NeverIndex = $true; Publish
    if ($publishMock.Release.draft -or $publishMock.Downloads -ne 2) { throw 'Publication waited for registry indexing.' }
    $checks++
    $publishMock = NewCase; $publishMock.FailSource = 'github'; Reject 'Package push failed'
    if (-not $publishMock.Release.draft) { throw 'Partial upload published the release.' }
    $publishMock.FailSource = ''; Publish
    if ($publishMock.Tags -ne 1 -or $publishMock.Drafts -ne 1 -or $publishMock.Uploads -ne 4 -or @($publishMock.Pushes | Where-Object { $_.Registry -eq 'nuget' -and -not $_.Symbols }).Count -ne 1) { throw 'Retry duplicated tag/assets/NuGet upload.' }
    $checks++
    $publishMock = NewCase; $publishMock.Tag = 'b' * 40; Reject 'different commit'
    if ($publishMock.Pushes.Count -or $publishMock.Uploads) { throw 'Conflicting tag caused publication writes.' }
    $checks++
    $publishMock = NewCase
    $conflict = Join-Path $publishMock.Path 'conflict.nupkg'
    Copy-Item -LiteralPath (Join-Path $publishMock.Path 'Example.2.0.0.nupkg') -Destination $conflict
    $zip = [IO.Compression.ZipFile]::Open($conflict, [IO.Compression.ZipArchiveMode]::Update)
    try { $zip.CreateEntry('different.txt') | Out-Null } finally { $zip.Dispose() }
    $publishMock.Remote.nuget = $conflict; Reject 'different contents'
    if ($publishMock.Tags -or $publishMock.Pushes.Count) { throw 'Conflicting registry version caused writes.' }
    $checks++
    $publishMock = NewCase; $publishMock.FailSource = 'github'; Reject 'Package push failed'
    Add-Content -LiteralPath (Join-Path $publishMock.Assets 'manifest.json') 'changed'
    $publishMock.FailSource = ''; Reject 'Existing release asset differs'
    if (-not $publishMock.Release.draft) { throw 'Changed asset was accepted.' }
    $checks++
    $publishMock = NewCase; $publishMock.FailSymbols = $true; Reject 'Symbol package publishing failed'
    if (-not $publishMock.Release.draft) { throw 'Failed symbols published the release.' }
    $publishMock.FailSymbols = $false; Publish
    if (@($publishMock.Pushes | Where-Object { -not $_.Symbols }).Count -ne 2) { throw 'Symbol retry duplicated primary package uploads.' }
    $checks++
    $publishMock = NewCase $false; Publish
    if (@($publishMock.Pushes | Where-Object { $_.Registry -eq 'github' }).Count -or $publishMock.Downloads -ne 1) { throw 'NuGet-only publication accessed GitHub Packages.' }
    $checks++
    $publishMock = NewCase; $env:NUGET_API_KEY = ''; Reject 'Publishing credentials'
    if ($publishMock.Downloads -or $publishMock.Tags) { throw 'Missing credentials caused writes.' }
    $env:NUGET_API_KEY = 'test-nuget-key'; $checks++
    $publishMock = NewCase; Add-Content -LiteralPath (Join-Path $publishMock.Path 'release-notes.md') 'changed'; Reject 'checksum mismatch'
    if ($publishMock.Downloads -or $publishMock.Tags) { throw 'Corrupted artifact caused writes.' }
    $checks++
    Write-Host "$checks publishing scenarios passed with mocked registries, GitHub API and CLI commands. No external requests or real uploads."
} finally {
    foreach ($name in $oldEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $oldEnvironment[$name]) }
    if ($hadExit) { Set-Variable LASTEXITCODE $oldExit -Scope Global } else { Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
}
