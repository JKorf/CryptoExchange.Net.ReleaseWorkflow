# Prepare release

Update the selected library's project/README, build its package and test projects,
run tests and add a native NUnit warning summary to the PR description. The action
does not create branches, commit/push changes, open a PR or publish packages.

## Caller responsibilities

Run validate first. If its `requires_approval` output is `true`, enforce the
protected `version-approval` environment before this action. Keep the environment
reviewer check and approval job in the library workflow. An override reason alone
is not approval, and this composite action does not implement that gate.

Check out the library's source commit with `fetch-depth: 0` and
`persist-credentials: false`. The checkout must have a readable `origin`; public
library repositories can use unauthenticated reads. Remote release refs are
checked again before any project/README changes are written.

```yaml
- name: Prepare release
  id: prepared
  uses: JKorf/CryptoExchange.Net.ReleaseWorkflow/actions/prepare@<commit-sha>
  with:
    package: ${{ inputs.package }}
    version: ${{ inputs.version }}
    notes: ${{ inputs.notes }}
    override-reason: ${{ inputs.override_reason }}
    integration-tests: ${{ inputs.integration_tests }}
```

Replace `<commit-sha>` with a tested full commit SHA. The action installs the SDK
from the library's configuration. After it succeeds, the local workflow creates
the GitHub App token, reads `plan_path`, stages the plan's project/README, commits
and pushes the plan's branch, and opens the PR using `body_path`.
Keep the App private key out of the build/test action.

## Inputs and outputs

Required inputs: `version`, `notes`. Optional inputs: `package`, `override-reason`,
`integration-tests` (`false` by default), `config-path`
(`.github/release-config.json`), `selected-ref` (`github.ref`),
`working-directory` (`github.workspace`) and `artifact-name`
(`release-preparation-test-results`). Use a unique artifact name if calling the
action more than once in the same workflow run.

Outputs: `sdk`, `package`, `package_id`, `version`, `branch`, `tag`, `base_branch`,
`body_path`, `plan_path`, `results_path`, `warnings_path`. Paths refer to the current
runner only; subsequent PR-creation steps should run in the same job.

## Tests and warnings

Projects are built sequentially in Release with package-on-build disabled. Test
execution uses native NUnit XML plus TRX reports. NUnit warnings are mapped to
Passed for VSTest but retained in the warning summary; genuine test failures stop
the action. Missing native results for a configured test project also fail rather
than imply a clean run. A package without test projects is reported explicitly.

Integration testing sets `INTEGRATION=1` only when requested. Preparation reports
are retained for 14 days when available, including after build/test failures.
Credentials and the actual PR creation remain in the caller workflow.
