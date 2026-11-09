# Installing the library workflows

Copy `prepare-release.yml` and `publish-release.yml` into the library's
`.github/workflows/` directory. Keep these filenames: Manager and NuGet trusted
publishing identify them. Keep `.github/release-config.json` in the library;
use `release-config.example.json` as a starting point for a new library.

The templates pin every shared action to tested commit
`93e3e075a0b3a42dd909630615f7361a8c16c32b`. No checkout or copy of the shared
scripts is required in the library. The preparation workflow still creates its
branch, commit and PR locally. The publishing workflow still owns the `release`
approval gate, GitHub App credentials and `NuGet/login` step. Keeping that login
in the library workflow preserves the existing NuGet trusted publishing policy.

## Migrating an existing library

1. Replace the two workflow files with these templates. Preserve any intentional
   library-specific changes and review the diff before merging.
2. Keep the existing package configuration, GitHub App installation, variables,
   secrets, protected environments and NuGet trusted publishing policy. Check
   the setup requirements in the repository README if configuring a new library.
3. Remove script regression-test steps from ordinary library CI. Those tests run
   in this shared repository. Keep the library's own build and test steps.
4. Merge the workflow changes into the configured `main` or `master` branch
   before starting a preparation run. An already running workflow keeps its old
   workflow definition.
5. Use Manager's normal PrepareAndRelease flow for the next intended release.
   Review multiline notes, test warnings and the PR; merge it; review the final
   artifact summary and approve publication. Confirm the package, symbols, tag,
   release assets and Manager announcements afterward.
6. Once the pilot succeeds, remove the unused local script copies and repeat
   the migration for the other libraries. Do not remove library configuration.

## Updating shared automation

Commit and push changes to the shared repository and wait for its Windows and
Linux CI to pass. Replace **all** shared-action SHA references in the templates
and adopting library workflows with that tested commit. Merge the library
workflow update to activate it. Libraries remain on their pinned version until
explicitly updated; changing the shared repository alone does not update them.

For a publishing-code fix after partial publication, update the library's SHA,
then dispatch Publish release with the original failed run ID and package
artifact ID. This uses the original package bytes with the corrected publisher.
Rerunning an old workflow does not pick up a new SHA. See the recovery guidance
in the repository README before retrying.
