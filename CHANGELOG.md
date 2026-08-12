# Changelog

All notable changes to the Atlas playbook are documented here. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
versions follow the semantic scheme used in `playbook.conf`.

---

## [0.7.0] - In Progress

### Added (post 0.6.0)
- **New repository layout scaffold**: `playbook/`, `packages/`, `tooling/`, `tests/`,
  `i18n/`, `docs/` (coexist with `src/` during transition; `tooling/dev/Migrate-RepoLayout.ps1`
  performs the final cutover).
- **State Engine** (`playbook/assets/modules/Lib/Atlas/StateEngine.psm1`) providing
  `Set-AtlasState`, `Reset-AtlasState`, `Get-AtlasState`, `Test-AtlasTweakApplied`,
  and profile tracking for idempotent tweak apply/revert — fixes the "cannot re-apply"
  class of bugs.
- **AI category** (`playbook/tweaks/ai/`): `disable-recall.yml`, `disable-click-to-do.yml`,
  `disable-ai-image-features.yml`, `disable-copilot-app.yml`, `disable-windowsaifabric.yml`,
  `disable-ai-actions.yml`, plus category aggregator `ai.yml`.
- **Gaming category** (`playbook/tweaks/gaming/`): `timer-resolution.yml`, `power-plan.yml`
  (profile‑driven, laptop auto‑detect), `hags-toggle.yml`, `disable-core-parking.yml`,
  plus category aggregator `gaming.yml`.
- **Profile definitions** (`playbook/profiles/{balanced,performance,privacy,security}.yml`)
  — four named profiles that will drive FeaturePages defaults and post‑install switching.
- First **i18n catalog** (`i18n/en-US.psd1`).
- **Revert tree** (`playbook/revert/ai/gaming/...`) with initial AI revert script.
- Pester unit tests for the state engine (`tests/unit/StateEngine.Tests.ps1`).
- `tooling/dev/Setup-DevEnvironment.ps1` – one‑command dev machine setup.
- `tooling/dev/Build-AtlasPlaybook.ps1` – cross‑platform build wrapper, supports both
  legacy and new layouts.
- `tooling/dev/Migrate-RepoLayout.ps1` – final cutover migration script.
- Updated CI workflow paths to use `tooling/ci/*`, new CODEOWNERS for new trees,
  expanded `.gitignore`.

### Changed
- Validator (`tooling/ci/Validate-AtlasPlaybook.ps1`) now locates the playbook root
  automatically for both legacy (`src/playbook`) and new (`playbook/`) layouts.

---

## [0.6.0] - Unreleased

This is a large maintainability, security and reliability upgrade. It is
**fully backwards compatible** with 0.5.0 – no YAML tweak paths or AtlasDesktop
user entry points are removed.

### Added
- `AtlasModules/Scripts/Lib/Atlas/` – first‑class shared PowerShell module
  (`Atlas.psd1`/`Atlas.psm1`) with:
  - Structured, timestamped logging (`Start-AtlasLog`, `Write-AtlasLog`, `Stop-AtlasLog`)
  - Safe registry helpers (`Test-`, `Get-`, `Set-`, `Remove-AtlasRegistryValueSafe`)
  - Privilege/architecture detection (`Test-AtlasAdmin`, `Test-AtlasTrustedInstaller`,
    `Get-AtlasSystemArchitecture`)
  - Integrity helpers (`Get-AtlasFileHash`, `Compare-AtlasHashTable`)
  - Playbook reference validator (`Test-AtlasReferencedFiles`)
  - Safe command wrapper (`Invoke-AtlasSafe`, `Invoke-AtlasLoggedCommand`)
- `Scripts/Security/Get-AtlasVerifiedFile.ps1` – central hash‑verified HTTPS
  downloader (TLS 1.2/1.3, curl fallback, hash mismatch refuses to keep file).
- `Scripts/Health/Start-AtlasHealthCheck.ps1` – post‑install health check
  verifying supported build, file presence, service state, Defender marker,
  pending reboots, and hash‑manifest integrity.
- `Scripts/Diagnostics/Export-AtlasDiagnostics.ps1` – anonymised diagnostics
  exporter (logs + service states + relevant reg keys + hardware summary)
  zipped to the desktop for bug reports.
- `Scripts/Rollback/Restore-AtlasDefaults.ps1` – restore services from the
  `winServices.reg` backup captured at install.
- `RunAtlasScript.cmd` – single, hardened launcher for user‑facing scripts.
  Existing per‑script `.cmd` files are retained as thin wrappers for
  compatibility but now delegate elevation, logging and error handling here.
- Hash + SBOM tooling under `scripts/ci/`:
  - `Validate-AtlasPlaybook.ps1` – YAML front‑matter, reference, registry‑type,
    tab/typo, and disallowed‑pattern checks.
  - `New-AtlasHashManifest.ps1` – generates `AtlasModules/Other/hashes.sha256`
    (+ JSON) for all shipped binaries/scripts; can also `–Verify`.
  - `New-AtlasSBOM.ps1` – CycloneDX 1.4 SBOM for all shipped binaries.
- `scripts/dev/Build‑AtlasPlaybook.ps1` – cross‑platform local build wrapper
  (calls `local-build.ps1`, then re‑generates manifest + SBOM).
- Dependabot configuration (`.github/dependabot.yml`) keeping GitHub Actions,
  pip, and submodules up to date.
- Added Architecture, Contributing, Security, and Release documentation under
  `docs/`.

### Changed
- GitHub Actions workflow hardened:
  - Least‑privilege `permissions:` blocks at job level.
  - Actions pinned to commit SHAs.
  - `pull_request:` trigger added so fork PRs validate.
  - New `validate` job runs `Validate-AtlasPlaybook.ps1`, hash verification,
    and markdown link check.
  - Auto‑commit now scopes to explicit `AtlasModules/Packages/*.cab` paths.
  - `dependabot` is configured to raise PRs against the workflow.
- `labeler` action upgraded to `actions/labeler@v5` (syntax updated).
- `.gitignore` expanded to cover common Windows/VS artefacts.

### Security
- All future network downloads from Atlas scripts are expected to route
  through `Get-AtlasVerifiedFile.ps1` with a pinned SHA‑256. Untracked
  downloads are flagged by the new validator.
- Hash manifest and SBOM are shipped inside the playbook so end users can
  verify integrity offline.

### Fixed
- Fixed `pause > null` typo (creates a file named `null`) in `Run Update Drivers.cmd`.
  (Existing script will be updated to use `RunAtlasScript.cmd`; typos in new
  scripts are caught by the validator.)

---

## [0.5.0] - 2024

- Windows 11 24H2 (26100) support.
- Added initial 25H2 (26200) support.
- Feature pages for Defender, mitigations, automatic updates, hibernation,
  power saving, core isolation, Edge, and browser selection.
- Atlas Toolbox (beta) install option.
- Restructured `Configuration/tweaks/` into `privacy/`, `performance/`,
  `qol/`, `networking/`, `debloat/`, `security/`, `scripts/`, `misc/`.
- sxsc packages: Atlas‑NoDefender, Atlas‑NoTelemetry (amd64 + arm64).
- ViVeTool v0.3.3 shipped (x64 + ARM64).

---

## [0.4.1] - 2023

- Previous stable release for Windows 10 / early Windows 11.
- See the release page on GitHub for details.

### Added (post-0.7 in same release)
- **Atlas module v0.7** (`playbook/assets/modules/Lib/Atlas/Extended.psm1`) adding:
  service start/backup/restore helpers, AppX helpers, policy writers with
  automatic backup, firewall rule helpers, Authenticode signature verification,
  platform detection (laptop/VM/build), and desktop UI helpers. State engine
  is now nested-loaded via NestedModules.
- **Verified downloader v1** (`playbook/assets/modules/Security/Get-AtlasVerifiedFile.ps1`)
  — HTTPS-only, TLS 1.2/1.3, atomic writes, SHA-256 and Authenticode thumbprint
  verification, persistent local cache.
- **Rollback / uninstall tooling** (E03):
  - `Restore-Policies.cmd` — restores policy values from the PolicyBackup tree.
  - `Restore-AppX.cmd` — re-registers AppX packages and re-provisions inbox apps.
  - `Uninstall-Atlas.ps1` — master uninstall script (runs reverts, restores
    services, removes Atlas folders/scheduled tasks/state keys).
- **Benchmark harness** (`tooling/benchmarks/Run-AtlasBenchmark.ps1`) — collects
  boot time, idle CPU/RAM, timer resolution, DPC/interrupt %, and running
  services. Supports baseline comparison (delta reporting).
- **Release signing tool** (`tooling/release/Sign-Artifact.ps1`) — Authenticode
  signing for scripts/binaries, GPG detached signatures for archives, generates
  SHA256SUMS/SHA512SUMS.
- **Dual SBOM generation** (`tooling/ci/New-AtlasSBOM.ps1`) now emits CycloneDX
  1.4 JSON, SPDX 2.3 JSON, SHA256SUMS and SHA512SUMS.
- **Windows Sandbox integration runner** (`tooling/ci/Run-SandboxTest.ps1`)
  for in-sandbox APBX install smoke testing.
- **Enterprise category scaffold** (`playbook/tweaks/enterprise/`):
  - `lsa-protection.yml` — RunAsPPL/RunAsPPLBoot.
  - `disable-smb1.yml` — removes SMB 1.0.
  - README documenting CIS/MS Baseline alignment.
- Pester tests (`tests/unit/AtlasModule.Tests.ps1`) covering the module surface,
  hashing, Compare-AtlasHashTable, platform helpers, and state engine.
- Fixed `pause > null` typo (creates file named `null`) in `Run Update Drivers.cmd`.

### Added (continuing v0.7)
- **Enterprise security baseline** (`playbook/tweaks/enterprise/`):
  - `asr-rules.yml` — low-false-positive Defender ASR rules in block/audit split.
  - `bitlocker-wizard.yml` — post-install BitLocker enable prompt (one-shot scheduled task).
  - `sysmon-install.yml` — Hash-pinned Sysmon install with Olaf Hartong config and weekly update task.
  - `lsa-protection.yml` — RunAsPPL/RunAsPPLBoot.
  - `no-lmhash.yml` — disable LM hash storage.
  - `disable-smb1.yml` moved to `networking/` (SMBv1 removed for all profiles).
  - `block-llmnr-nbt-ns.yml` — disable LLMNR and NetBIOS-over-TCP/IP (hardened tier).
- **Verified installer library** (`playbook/assets/modules/Scripts/Installers/`):
  - `versions.json` — pinned URLs + hashes for toolbox, browsers (brave/firefox/librewolf/chrome), Sysmon, Open-Shell, Process Explorer.
  - `install-toolbox.ps1` — Toolbox install via Get-AtlasVerifiedFile with signature check.
  - `Browser-Install.ps1` — generic browser installer with silent arg maps for each vendor.
- **Revert scripts** (`playbook/revert/`):
  - `ai/ai-all.cmd`, `gaming/gaming-all.cmd`, `enterprise/enterprise-all.cmd` — category-wide revert.
- **Networking hardening**:
  - `networking/disable-smb1.yml` (moved, default-on).
  - `networking/block-llmnr-nbt-ns.yml` (security/privacy profiles).
- **Release tooling** (`tooling/release/`):
  - `Sign-Artifact.ps1` — Authenticode + GPG signing with checksum generation.
  - `Bump-Versions.ps1` — refreshes pinned hashes for installers.
- **CI hardening**:
  - Added `aquasecurity/trivy-action` for filesystem vulnerability scanning on HIGH/CRITICAL.
  - SBOMs (CycloneDX + SPDX) and SHA256/SHA512 checksums uploaded with every release artifact.
  - Dual-layout validator support (legacy `src/` and new `playbook/`).
- **Tests** (`tests/unit/Extended.Tests.ps1`) — platform/build helpers, registry helpers, and logging functions.
- **Benchmark harness** (`tooling/benchmarks/Run-AtlasBenchmark.ps1`) expanded with delta reporting and baseline comparison.
- **Sandbox integration runner** (`tooling/ci/Run-SandboxTest.ps1`) for automated install tests.

### v0.6.0 wiring / fixes (in-progress)
- **FeaturePages v2** (`src/playbook/playbook.conf`):
  - New profile selector radio page (`profile-balanced` / `profile-performance` / `profile-privacy` / `profile-security`) added as the first page; profile value persisted to `HKLM\SOFTWARE\AtlasOS\Profile\Current` by `atlas\set-profile.yml`.
  - New checkboxes: `disable-ai`, `disable-copilot`, `gaming-performance`, `disable-smb1`, `harden-networking`, `enable-asr`, `lsa-protection`, `bitlocker-prompt`, `install-sysmon`.
  - Version bump to 0.6.0 in conf; description updated.
- **Root playbook (`custom.yml`)** now runs:
  - `atlas\preflight.yml` early — kills known VC++ runtime lockers to fix 25H2 install failures (issue #1509), validates build and warns on pending reboot.
  - `atlas\set-profile.yml` right after init-libraries to record the user's profile selection.
  - `atlas\repair-store.yml` after AppX processing — resets WindowsApps ACLs and re-registers Microsoft.Store + dependency packages to repair OEM Store-break (issue #1353).
  - Post-install health check now uses `-PassThru` and fires a toast notification via `Health\Show-AtlasToast.ps1` (silently degrades if WinRT isn't ready).
- **Tweaks root (`tweaks.yml`)** now wires in the new categories:
  - `tweaks\ai\ai.yml` after the privacy/telemetry section (gated by `disable-ai`; copilot app removal also exposed via standalone `disable-copilot`).
  - `tweaks\gaming\gaming.yml` in the performance section (gated by `gaming-performance`).
  - `tweaks\networking\disable-smb1.yml` (gated by `disable-smb1`) and `tweaks\networking\block-llmnr-nbt-ns.yml` (gated by `harden-networking`) under Networking.
  - `tweaks\enterprise\enterprise.yml` in the Security section; this aggregate fans out to LSA/ASR/Sysmon/BitLocker/SMB/LLMNR steps gated by the individual hardening checkboxes.
- **Power plan** (`tweaks/gaming/power-plan.yml`) reads the active profile from the registry and switches Balanced/High-Performance accordingly; laptops stay Balanced unless the user explicitly chose Performance.
- **Paging file**: `tweaks\performance\system\disable-paging.yml` remains commented out (was never default); the fix for #1406 micro-stutters is that pagefile-executive disabling is NOT applied in any default profile, and power-plan/paging tweaks are now profile-scoped rather than blanket-on.
- **Validator** (`tooling/ci/Validate-AtlasPlaybook.ps1`) strengthened:
  - New tweaks under `tweaks/{ai,gaming,enterprise,networking,security}/` must declare `appliesTo:` build-range and `sources:` citations; missing entries emit WARN (ERR under -Strict).
  - Disallowed-pattern list expanded to flag `curl.exe`, `iwr`, and any `Invoke-WebRequest`/`Start-Process` on EXE outside `Get-AtlasVerifiedFile` wrappers.
  - Referenced-file scan now covers `path:` entries in `!task:` includes (not just inline quoted strings).
- New files:
  - `Configuration/atlas/preflight.yml` — #1509 VC-runtime locker kill + build gate + reboot warning.
  - `Configuration/atlas/set-profile.yml` — persists FeaturePages profile radio to registry.
  - `Configuration/atlas/repair-store.yml` — OEM Store ACL repair (#1353).
  - `Health/Show-AtlasToast.ps1` — post-install WinRT toast wrapper, silent if unavailable.
- All new tweak YAMLs carry `appliesTo:` + `sources:` front-matter (validator-clean).
- Line endings re-normalised with the binary-safe Python normalizer (PS* → CRLF, YAML/MD/JSON → LF, binaries untouched).
