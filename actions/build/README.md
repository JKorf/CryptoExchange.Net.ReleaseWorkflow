# Build merged release

Build, test and pack the exact merged preparation PR commit. The action retains
verified NuGet/symbol packages, release notes, a checksum manifest and the final
publication review summary. It does not create tags/releases, publish packages,
request credentials or approve publication.

## Caller responsibilities

Run only for merged, same-repository preparation PRs targeting the configured
main/master branch. Check the `release` environment's required reviewers and
`NUGET_USER` configuration in the local workflow. Keep those policy checks and
the protected publishing job local to the library.

Check out the exact `merge_commit_sha` with full history and no persisted Git
credentials. The action also validates the merged event, source SHA, package,
version, README notes and clean working tree before building.

```yaml
- uses: actions/checkout@v4.2.2
  with:
    ref: ${{ github.event.pull_request.merge_commit_sha }}
    fetch-depth: 0
    persist-credentials: false

- name: Build final release
  id: built
  uses: JKorf/CryptoExchange.Net.ReleaseWorkflow/actions/build@<commit-sha>
```

Replace `<commit-sha>` with a tested full commit SHA. Do not pass publishing
credentials to this action. The separate publishing job must use environment
`release` and download the approved artifact by its `artifact_id` after approval;
it must not rebuild the package.

## Inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `event-path` | `github.event_path` | Merged pull_request event JSON. |
| `repository` | `github.repository` | Library owner/repository. |
| `working-directory` | `github.workspace` | Clean library checkout root. |
| `config-path` | `.github/release-config.json` | Configuration relative to that root. |

Normal callers use the default event/repository. CI supplies a synthetic merged
event and separate sample checkout to test this action without a real release.

## Outputs and artifacts

`artifact_id` identifies the immutable uploaded release package artifact.
`artifact_name` follows `release-pr-<number>-attempt-<run_attempt>` so recovery can
recognize it. Other scalar outputs are `sdk`, `commit`, `pull_request`,
`package_id`, `version`, and `tag`.

`artifacts_path`, `manifest_path`, `results_path`, and `summary_path` are local
runner paths. Pass scalar values as job outputs; use artifact upload/download for
files crossing jobs. Final artifacts and native test reports are retained for
30 days. Reports are retained when available after a failed build/test, while
package artifacts are uploaded only after successful checks, pack and review.

Builds are sequential to avoid shared documentation-file output conflicts. Source
commit metadata is supplied to both build and pack. Integration tests follow the
package's `releaseIntegrationTests` setting, independently of preparation inputs.
NUnit warnings appear in the final review; genuine test failures or missing
expected native test reports stop the action. A package without tests is reported
explicitly. Package IDs/versions, source repository/commit and SHA256 checksums
are verified before upload.
