# Validate release

Validate a library release without changing its project or README. The action
checks the selected base branch, package/version/notes, existing tag and remote
release branch. It writes a release plan and approval preview to temporary files.

Major and unusual version changes require an explanation and output
`requires_approval: 'true'`. The caller must enforce its `version-approval`
environment gate and check its required reviewers; the action does not approve
releases or contact GitHub. Other shared actions are still placeholders.

## Usage

Check out the library with full history, then call the action. Replace
`<commit-sha>` with a tested full commit SHA from this repository.

```yaml
- uses: actions/checkout@v4.2.2
  with:
    ref: ${{ github.sha }}
    fetch-depth: 0
    persist-credentials: false

- name: Validate release
  id: plan
  uses: JKorf/CryptoExchange.Net.ReleaseWorkflow/actions/validate@<commit-sha>
  with:
    package: ${{ inputs.package }}
    version: ${{ inputs.version }}
    notes: ${{ inputs.notes }}
    override-reason: ${{ inputs.override_reason }}
```

## Inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `version` | Required | Next stable major.minor.patch version. |
| `notes` | Required | Markdown with actual newlines and nested indentation. |
| `package` | Empty | Package key; inferred for single-package repositories. |
| `override-reason` | Empty | Explanation for major/unusual changes. |
| `config-path` | `.github/release-config.json` | Config relative to the library root. |
| `selected-ref` | `github.ref` | Must match the configured main/master ref. |
| `working-directory` | `github.workspace` | Library checkout root. |

Scripts are loaded from the shared action directory and run relative to the
library checkout. Set `working-directory` for a library checked out elsewhere.
Override `selected-ref` only for a sample fixture or a deliberately supplied
caller ref; normal release workflows should use its default.

## Outputs

`requires_approval` is the string `true` or `false`. Other outputs are `sdk`,
`package`, `package_id`, `version`, `branch`, `tag`, and `base_branch`.
`body_path` and `plan_path` point to temporary preview/JSON files on the current
runner. For another job, pass scalar job outputs or upload/download artifacts;
the file paths alone cannot cross job boundaries.

The preview and source commit are appended to the job summary. The action does
not modify source, build a library, create a branch/PR/tag or publish packages.
Keep existing library workflows in place until all shared actions are ready.
