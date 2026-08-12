# Contributing to Atlas

Thanks for considering a contribution to Atlas. This document covers the
*technical* side of contributing; the non‑technical guidelines (code of conduct,
etc.) are at https://docs.atlasos.net/contributing/contribution-guidelines/.

## Prerequisites

- Windows 11 (build 26100 or 26200) or a Linux/macOS workstation for YAML-only
  changes.
- PowerShell 5.1 (Windows) or PowerShell 7+ for cross‑platform work.
- Git.
- Optionally, AME Wizard and a VM to test the built playbook — *never test on
  your main machine.*

## Local build

> ⚠️ `src/dependencies/local-build.ps1` is git‑ignored because it is distributed
> with AME Wizard / the build tooling. Fetch it from the official source and
> place it in `src/dependencies/` before building locally, or rely on CI.

```powershell
# From a PowerShell prompt at the repo root
./scripts/dev/Build-AtlasPlaybook.ps1
```

This wraps `local-build.ps1` with the recommended flags, then regenerates the
hash manifest and SBOM. On Linux/macOS you can use `pwsh` to run the CI
validators directly:

```bash
pwsh ./scripts/ci/Validate-AtlasPlaybook.ps1 -PlaybookRoot ./src/playbook -Strict
```

## Validating your changes

Before opening a PR, run:

1. `scripts/ci/Validate-AtlasPlaybook.ps1 -PlaybookRoot ./src/playbook -Strict`
2. `yamllint src/` (same flags as CI).
3. Build the playbook locally and install in a VM.
4. After install, run `AtlasModules\Scripts\Health\Start-AtlasHealthCheck.ps1`
   from an elevated PowerShell to confirm invariants hold.

## Adding a new tweak

1. Create `src/playbook/Configuration/tweaks/<category>/<slug>.yml`.
2. Start with:
   ```yaml
   ---
   title: Short human title
   description: One-sentence explanation of what this does and why.
   actions:
     - !writeStatus: {status: 'Applying <slug>'}
     # ... your actions ...
   ```
3. Reference any script files relative to the playbook root, using
   `exeDir: true` where appropriate.
4. Add a matching toggle in `AtlasDesktop/` if users should be able to revert
   it post‑install. Use `RunAtlasScript.cmd` rather than re‑implementing
   elevation.
5. If your tweak downloads anything, route the download through
   `Get-AtlasVerifiedFile.ps1` and pin the SHA‑256. The validator will flag
   raw `Invoke-WebRequest`/`Start-Process` calls.
6. Add an entry to the appropriate AtlasDesktop documentation URL file.
7. Test in a VM.

## Commit messages

Use conventional‑commit style:

```
feat(tweaks): add disable-WiFi-Direct toggle
fix(services): don't disable Print Spooler on upgrade
chore(ci): pin tj-actions/changed-files to sha
docs(architecture): clarify execution order
```

## Pull requests

- Fill in the PR template completely.
- Reference any issue you are closing (`Closes #1234`).
- Keep PRs focused — one logical change per PR.
- CI must be green before a maintainer will review.

## Reporting issues

Use the GitHub issue templates. Please attach an export from
`Export-AtlasDiagnostics.ps1` (found in the Atlas folder → 8. Additional Tools →
Troubleshooting) when reporting bugs.
