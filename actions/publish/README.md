# Publish approved release

Publish the original verified packages and complete their GitHub release after
approval. This action does not build packages, obtain credentials or implement
the approval gate.

## Caller responsibilities

Keep the publishing job in the library's local `publish-release.yml` workflow,
protected by environment `release`. Install the SDK from build/recover's `sdk`
output and download the approved artifact by immutable ID. For recovery, download
from the original run, not the recovery run.

After approval, create a GitHub App token with Contents/Workflows write access
and obtain a short-lived key using `NuGet/login@v1`. GitHub Packages uses the
library workflow's `GITHUB_TOKEN` with Packages write permission. Keep credential
creation and NuGet login in the library workflow to preserve publishing identity.

```yaml
- name: Publish approved release
  id: published
  uses: JKorf/CryptoExchange.Net.ReleaseWorkflow/actions/publish@<commit-sha>
  with:
    artifact-directory: ${{ runner.temp }}/approved-release
    repository: ${{ github.repository }}
    commit: ${{ needs.build.outputs.commit }}
    pull-request: ${{ needs.build.outputs.pull_request }}
    github-token: ${{ steps.release-app.outputs.token }}
    github-packages-token: ${{ github.token }}
    nuget-api-key: ${{ steps.nuget.outputs.NUGET_API_KEY }}
```

Replace `<commit-sha>` with a tested full commit SHA. The example assumes a normal
build; select recover outputs instead for manual recovery. The local job keeps
Contents write, Actions read, Packages write and id-token write permissions as
needed for downloads, package publishing and its NuGet login.

## Inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `artifact-directory` | Required | Downloaded approved artifact directory. |
| `commit` | Required | Original merged source commit. |
| `pull-request` | Required | Original preparation PR number. |
| `repository` | `github.repository` | Library owner/repository. |
| `github-token` | `github.token` | Prefer the App token for tags/releases, especially recovery. |
| `github-packages-token` | `github.token` | Registry credential with Packages write permission. |
| `nuget-api-key` | Empty | Short-lived NuGet key; required for actual publication. |
| `validate-only` | `false` | Verify artifacts without external requests or publication. |

Validation-only checks package metadata, source identity and checksums. It does
not test credentials, remote registries or the ability to publish. It may be
called before credential creation to check downloaded artifacts early.

## Publication and recovery

Registry preflight permits an existing version only when its ZIP payload matches
the approved package, ignoring NuGet's repository signature. Existing tags must
resolve to the approved commit, and existing release assets must match exactly.
Differing files or package payloads are never replaced.

The action creates/reuses the tag and draft release, attaches packages, symbols,
notes and manifest, pushes the primary package to configured registries and
symbols to NuGet.org, then makes the GitHub release public. Accepted uploads
complete publication without waiting for NuGet indexing.

There is no atomic transaction across services. Failures can leave a tag/draft
or some uploaded packages. Correct the external issue and reuse the original
artifacts; do not rebuild or move the tag. If automation code changed, start a new
manual recovery run with the corrected action SHA and original artifact ID.

## Outputs and tests

`published` is `true` only after successful publication and `false` for
validation-only. `release_url` and `nuget_url` are populated only after successful
publication; indexing may delay NuGet availability. Other outputs are
`package_id`, `version`, `tag`, `commit`, and `pull_request`. Failures do not emit
success outputs.

CI uses real sample artifacts in validation-only mode. Full publishing logic is
tested with mocked HTTP/CLI transports covering partial failures, retries,
conflicts, credential separation and indexing delays. No publishing secrets are
needed and no sample packages are published. Manager announcements remain in
Manager and are not sent by this action.
