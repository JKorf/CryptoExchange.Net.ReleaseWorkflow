param(
    [Parameter(Mandatory)][string]$Directory,
    [ValidateSet('main', 'master')][string]$BaseBranch = 'main',
    [switch]$Buildable
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $Directory -Force | Out-Null
$Directory = (Resolve-Path -LiteralPath $Directory).Path
foreach ($name in @('.git', 'Example.csproj', 'README.md', '.github/release-config.json')) {
    if (Test-Path -LiteralPath (Join-Path $Directory $name)) { throw "Fixture would overwrite existing input: $name" }
}
New-Item -ItemType Directory -Path (Join-Path $Directory '.github') -Force | Out-Null
$project = '<Project><PropertyGroup><PackageId>Example</PackageId><PackageVersion>1.3.0</PackageVersion><AssemblyVersion>1.3.0</AssemblyVersion><FileVersion>1.3.0</FileVersion></PropertyGroup></Project>'
if ($Buildable) { $project = $project.Replace('<Project>', '<Project Sdk="Microsoft.NET.Sdk">').Replace('<PropertyGroup>', '<PropertyGroup><TargetFramework>net10.0</TargetFramework>') }
$project | Set-Content -LiteralPath (Join-Path $Directory 'Example.csproj') -Encoding utf8NoBOM
"# Example`n`n## Release notes`n* Version 1.3.0 - Before`n    - Existing feature`n" | Set-Content -LiteralPath (Join-Path $Directory 'README.md') -Encoding utf8NoBOM
@{ baseBranch = $BaseBranch; sdk = '10.0.401'; packages = @(@{ key = 'example'; project = 'Example.csproj'; packageId = 'Example'; readme = 'README.md'; tagPrefix = 'Example.'; testProjects = @() }) } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Directory '.github/release-config.json') -Encoding utf8NoBOM
Push-Location $Directory
try {
    git init --quiet --initial-branch=$BaseBranch
    if ($LASTEXITCODE -ne 0) { throw 'Fixture git init failed.' }
    git add Example.csproj README.md .github/release-config.json
    if ($LASTEXITCODE -ne 0) { throw 'Fixture git add failed.' }
    git -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m fixture
    if ($LASTEXITCODE -ne 0) { throw 'Fixture commit failed.' }
} finally { Pop-Location }
