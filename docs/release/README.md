# Release Process

This checklist is used by maintainers when cutting a new Atlas release.

## Before cutting

1. Pull latest `main` and create a release branch (`release/vX.Y.Z`).
2. Bump `<Version>` in `src/playbook/playbook.conf`.
3. Update `<UpgradableFrom>` if users on older versions can upgrade in place.
4. Update the version in:
   - `src/playbook/Executables/AtlasModules/Scripts/Lib/Atlas/Atlas.psd1`
   - `CHANGELOG.md` (write the release entry, move "Unreleased" items under the
     new version header).
5. Regenerate hashes and SBOM:
   ```powershell
   ./scripts/ci/New-AtlasHashManifest.ps1
   ./scripts/ci/New-AtlasSBOM.ps1
   ```
6. Run the validator:
   ```powershell
   ./scripts/ci/Validate-AtlasPlaybook.ps1 -PlaybookRoot ./src/playbook -Strict
   ```
7. Install the built APBX in a clean VM (26100 and 26200, amd64 and ARM64 when
   possible). Run `Start-AtlasHealthCheck.ps1` and resolve any failures.
8. Smoke‑test the key post‑install toggles (Defender, updates, mitigations,
   hibernation, Edge removal, browser install).

## Tagging

1. Open a PR from `release/vX.Y.Z` to `main`, wait for CI to go green, get a
   review, merge.
2. Tag the merge commit:
   ```
   git tag vX.Y.Z
   git push --tags
   ```
3. Draft a GitHub release named `Atlas vX.Y.Z` with:
   - Summary of the release (copy from CHANGELOG).
   - Link to docs.atlasos.net installation page.
   - Attached release ZIP (built by CI on the tagged commit).
   - SBOM and hash files attached for extra verification.
4. Announce on Discord / website / docs as appropriate.

## Hotfixes

For critical fixes (security or break‑the‑install bugs), cut a `vX.Y.Z+1`
release directly off the tag with only the fix cherry‑picked in. Increment the
patch version and follow the same checklist.
