# Recover original release artifacts

Validate and download package artifacts from a completed, unsuccessful original
publication run. Recovery uses the original packages and merged source commit;
it does not rebuild, upload new artifacts, change tags or publish a release.

## Usage

Call from the library's manually dispatched `publish-release.yml` workflow on
main/master, using the original failed merge-triggered run ID and package artifact
ID. Keep publication in a separate job protected by environment `release`.

```yaml
permissions:
  contents: read
  actions: read

steps:
  - name: Recover original release
    id: recovered
    uses: JKorf/CryptoExchange.Net.ReleaseWorkflow/actions/recover@<commit-sha>
    with:
      original-run-id: ${{ inputs.original_run_id }}
      artifact-id: ${{ inputs.artifact_id }}
```

Replace `<commit-sha>` with a tested full commit SHA containing the corrected
automation. This action does not require checking out the old source: scripts
come from the action's pinned revision and the packages come from the original
artifact. Do not select a recovery run as the original run; it must be the failed
merge-triggered run named `Publish release PR #<number>`.

## Inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `original-run-id` | Required | Original unsuccessful publication run. |
| `artifact-id` | Required | Original package artifact, not test reports. |
| `repository` | `github.repository` | Library owner/repository. |
| `github-token` | `github.token` | Token with Contents/Actions read access to that repository. |

The App private key, registry tokens and NuGet publishing credentials are not
needed. Metadata is checked before the download, then rechecked when verifying
downloaded contents. Active or successful runs, fork/unmerged PRs, unrelated
source SHAs, expired artifacts, artifacts from another run and test-report
artifacts are rejected. Package ID/version, source repository/commit, notes and
checksums must match the original manifest.

## Outputs

`sdk`, `commit`, `pull_request`, `artifact_id`, `original_run_id`, `artifact_name`,
`package_id`, `version`, and `tag` describe the verified original release.
`artifacts_path` and `manifest_path` refer to the current runner only.

Pass scalar outputs to the publishing job. After approval, that job downloads
the original artifact again using `original_run_id` and `artifact_id`, checks it,
and publishes it without building. Recovery preserves the original artifact ID;
it does not replace it with an artifact from the recovery run.

Approval remains in the library workflow. Manager currently follows the original
merge-triggered run, so approve manual recovery in GitHub and use AnnounceRelease
in Manager after publication succeeds.

## Tests

The regression suite tests recovery with mocked GitHub metadata and real local
package ZIP/checksum validation. CI also downloads the sample package artifact
produced by build and runs those checks against its actual files. It does not
create a deliberately failed GitHub PR/run; metadata is modelled as a completed
failed merge run. A real end-to-end recovery is verified during library migration.
