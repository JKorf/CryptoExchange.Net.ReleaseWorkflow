# CryptoExchange.Net.ReleaseWorkflow

Shared release automation for CryptoExchange.Net client libraries. It provides
PowerShell scripts for preparing release PRs, building and verifying packages,
publishing approved releases, and recovering interrupted publications.

The first shared composite action, [validate](actions/validate/README.md), is
implemented and exercised by CI against a separate sample library. The other
action folders are placeholders; existing libraries should keep using their
current workflows until the complete shared flow is ready.

## Repository layout

```text
.github/workflows/test.yml         Windows and Linux regression checks
scripts/
  Prepare-Release.ps1              Validate the version; update project and README
  Validate-Release.ps1             Validation-only orchestration and action outputs
  Add-TestWarnings.ps1             Add native NUnit warnings to a review summary
  Get-PublishPlan.ps1              Validate a merged PR and extract release metadata
  Get-RecoveryPlan.ps1             Validate an original run and its retained artifacts
  Release-PackageFunctions.ps1     Package verification and registry/GitHub helpers
  Publish-Release.ps1              Publish approved packages, tag and GitHub release
  tests/                          Offline/localhost regression tests
templates/
  prepare-release.yml             Library preparation workflow template
  publish-release.yml             Library publication and recovery workflow template
  release-config.example.json     Example library-specific package configuration
actions/validate/                  Shared validation action and usage documentation
```

## Execution requirements

- Use **PowerShell 7.2 or newer** (`pwsh`). Windows PowerShell 5.1 is unsupported.
- Git is required for preparation, source validation and the package test fixtures.
- Real builds and publishing also need the configured .NET SDK and GitHub CLI.
- Run release scripts with the **library checkout as the working directory**.
  Project, README and configuration paths are relative to that directory, even
  when a script is loaded from a separate automation checkout.
- Scripts locate their helper scripts relative to `$PSScriptRoot`.
- Keep library source, project versions, release notes and package configuration
  in the library repository. Keep credentials out of this repository's files.

For example, after checking out both repositories locally (choose a version
greater than the library's current version):

```powershell
Set-Location C:\Projects\HyperLiquid.Net
$previewPath = (New-TemporaryFile).FullName
& C:\Projects\CryptoExchange.Net.ReleaseWorkflow\scripts\Prepare-Release.ps1 `
    -Package hyperliquid -Version 5.9.2 `
    -Notes "- Feature 1`n  - Additional detail" -BodyPath $previewPath -ValidateOnly
```

`-ValidateOnly` validates the preparation inputs without changing project/README
files; it still writes the PR-body preview to `BodyPath` (and metadata to
`ResultPath` when supplied). It does not provide a full publication dry run. Use the regression tests
below for checking the shared scripts without publishing anything.

## Library configuration

Each library owns `.github/release-config.json`. Start with
[the example configuration](templates/release-config.example.json), then set:

| Setting | Purpose |
| --- | --- |
| `baseBranch` | Release target: `main` or `master`. |
| `sdk` | .NET SDK used by release builds. |
| `packages[].key` | Selects a package in `release/<key>/<version>` branches. |
| `project` / `testProjects` | Project and test paths relative to the library root. |
| `packageId` | Exact NuGet package ID from the project. |
| `readme` | README containing the version's release notes. |
| `tagPrefix` | Package-specific tag prefix, followed by the release version. |
| `releaseIntegrationTests` | Whether to run integration tests on the merged commit; defaults to false. |
| `publishToGitHubPackages` | Whether to publish the primary package to GitHub Packages; defaults to true. |

Repositories with multiple packages list each package separately. Each release
selects one package, and tag prefixes should distinguish their releases. Stable
three-part versions are supported. Major releases and unusual version jumps
require an override reason and the separate version-approval gate.

README release entries use `* Version <version> - <date>`, with notes indented by
four spaces. Preparation adds that indentation and publication removes it again,
preserving the supplied Markdown bullets and nested indentation. Publication
reads the final merged README entry, including edits made during PR review.

## Release flow and library setup

The library's preparation workflow validates inputs, obtains any exceptional
version approval, builds/tests, updates versions and notes, and opens a release
PR. After the maintainer reviews and merges it, the publication workflow builds,
tests and packs the exact merged commit. It retains the packages for review and
waits at the `release` environment before publishing.

After approval, publication verifies the artifact identity and checksums, creates
the tag and draft GitHub release, uploads its assets, publishes the primary
package to NuGet.org/GitHub Packages and symbols to NuGet.org, and publishes the
GitHub release. It does not wait for NuGet indexing. NUnit warnings are reported
without blocking release; real test failures prevent publication.

Each consuming library still needs:

- Local `prepare-release.yml` and `publish-release.yml` workflows and package config.
- `version-approval` and `release` environments with required reviewers. For a
  solo maintainer, leave Prevent self-review unchecked. Allow `main`/`master` on
  version-approval; allow `refs/pull/*/merge` plus the base branch on release.
- The release GitHub App installed on that repository, with Contents, Pull
  requests and Workflows write permissions. Configure variable `RELEASE_APP_ID`
  and secret `RELEASE_APP_PRIVATE_KEY`. Publishing requests the App token only
  after approval; GitHub Packages uses the library workflow's `GITHUB_TOKEN`.
- Variable `NUGET_USER` and a NuGet trusted publishing policy for that library
  repository, filename `publish-release.yml`, environment `release`, and its
  package scope. No persistent NuGet API-key secret is needed.
- GitHub package access and Manager credential access to the library repository.

Manager dispatches preparation, waits for the browser merge, requests publication
approval and monitors completion. News API and Discord announcements run in
Manager after successful PrepareAndRelease; these scripts do not send them.
Keep the local workflow names, dispatch inputs and publication run title
`Publish release PR #<number>` stable when migrating to shared actions.

## Running tests

From this repository's root:

```powershell
pwsh -NoProfile -File ./scripts/tests/Test-TestWarnings.ps1
pwsh -NoProfile -File ./scripts/tests/Test-PublishRelease.ps1
pwsh -NoProfile -File ./scripts/tests/Test-ReleaseHttp.ps1
pwsh -NoProfile -File ./scripts/tests/Test-ReleaseValidation.ps1
```

The tests use temporary files/Git repositories, mocked GitHub responses, and a
localhost HTTP server. They do not publish packages, create remote tags/releases,
or send announcements. They do not build a real library or verify live credentials.

[The test workflow](.github/workflows/test.yml) runs on pushes and PRs to `main`,
and can also be started manually. Its Windows/Linux matrix runs syntax checks and
all four suites, then exercises the validate action for patch and major releases
using a separate sample library. CI needs no repository secrets. Both matrix jobs should pass
before a shared automation version is released.

## Recovering a release

If access, credentials or service availability caused a failure, fix that issue
and use **Re-run failed jobs** to reuse the original artifacts. Existing tags must
point to the same source commit; existing release assets and registry package
payloads must match. Published versions are never replaced with different code.

If the publishing code itself was fixed, rerunning an old job still uses its old
script revision. Update the library's automation reference/code, then manually
dispatch its Publish release workflow with `original_run_id` and `artifact_id`
from the original failed run. Choose the `release-pr-<number>-attempt-<attempt>`
artifact, not the test reports. Recovery validates and publishes those original
packages without rebuilding or changing the original source commit.

Approve manual recovery through GitHub. Manager's ApproveRelease follows the
original merge-triggered run; use AnnounceRelease after recovery succeeds.
Avoid **Re-run all jobs** after partial publication, since rebuilding can produce
different package bytes. Final publication artifacts in the templates are kept
for 30 days; preparation test reports are kept for 14 days.

