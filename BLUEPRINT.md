# Atlas v1.0 — Blueprint: Work Items & Epic Breakdown

This is the *actionable* companion to `ROADMAP.md`. Every Epic maps to a
trackable milestone; every Item maps to an individual PR / commit. Use this
as the source for GitHub Milestones, Projects, and sprint planning.

Versioning convention:
- **E**pic = `E<nn>` (milestone)
- **W**ork item = `E<nn>-W<nn>` (issue / PR)
- Acronyms: PS = PowerShell, YML = YAML task, CI = CI/CD, DOC = documentation,
  TST = test, UX = user experience.

Epics are ordered so they can land sequentially; Epics marked 🔷 are
parallelizable.

---

## Epic E01 — Repo Relayout & Core Phase Renumbering
**Goal:** produce the new directory structure from §4 of ROADMAP.md without
breaking any existing script; all references are auto‑rewritten.
- E01-W01: Write `tooling/dev/Migrate-RepoLayout.ps1` to move `src/playbook/Configuration/atlas/*.yml` → `playbook/core/NNN-*.yml` with auto‑renamed include references.
- E01-W02: Move `src/playbook/Executables/AtlasModules` → `playbook/assets/modules`, `Executables/AtlasDesktop` → `playbook/assets/desktop`, update copy steps in `root.yml`.
- E01-W03: Move `src/sxsc/` → `packages/`, move scripts → `tooling/ci` + `tooling/dev`, introduce new `tests/`, `docs/tweaks`, `i18n/` scaffolds.
- E01-W04: Rename `custom.yml` → `root.yml`; update `playbook.conf`'s root task.
- E01-W05: Update all hardcoded path strings (199 `.cmd`, 34 `.ps1`, `.vscode/`, `build-playbook.cmd/sh`) via migration script.
- E01-W06: Update `.gitignore`, `.editorconfig`, `.gitattributes`, CODEOWNERS for new paths.
- E01-W07: Add a CI job that fails if old paths are referenced anywhere.
- E01-TST: Integration test that builds an APBX from the new layout and installs it in Windows Sandbox.

---

## Epic E02 — State Engine (Idempotency)
**Goal:** `Set-AtlasState` detects whether a tweak is already applied, so
re‑running the playbook is safe and fast. Fixes issue #1273.
- E02-W01: Design state schema under `HKLM\SOFTWARE\AtlasOS\State\<tweak-id>` with version, profile, applied date, hash of apply script.
- E02-W02: Add `Register-AtlasRollback`, `Test-AtlasTweakApplied`, `Set-AtlasState` to the Atlas module.
- E02-W03: Write `!state:` custom YAML action documentation; provide wrapper for existing tasks via an `apply:` block.
- E02-W04: Convert core phases (`020-services`, `030-components`, `040-appx`) to use `Set-AtlasState`.
- E02-W05: Build idempotency integration test (run apply twice → zero diff in services/registry).
- E02-W06: Add repair mode ("re‑apply even if state says applied" via `/force` flag in Toolbox).

---

## Epic E03 — Revert System & Uninstall
**Goal:** first‑class per‑category rollback; working Uninstall Atlas entry.
- E03-W01: Establish `playbook/revert/<category>/<name>.cmd` convention; add validator check that every tweak in `tweaks/` has a revert.
- E03-W02: Write `Restore Default Services` (expand existing); cover all services Atlas touches (generate list from `020-services.yml`).
- E03-W03: Write `Restore Group Policies.cmd` to remove Atlas‑set Policies keys and record what was removed.
- E03-W04: Write `Restore AppX Provisioning.cmd` (re‑registers inbox AppX; `Get-AppxProvisionedPackage -Online` with inbox AppX manifest).
- E03-W05: Write `Restore Tasks.cmd` to re‑enable scheduled tasks Atlas disabled.
- E03-W06: Write `Uninstall Atlas.cmd` master script that runs reverts, removes Atlas folders/tasks, writes `$env:TEMP\AtlasUninstall.log`, and warns about CAB‑removed components.
- E03-W07: Add Desktop folder `8. Uninstall Atlas` with clear warnings + README.
- E03-TST: Reinstall test (install → uninstall → health check finds no Atlas residue beyond CAB packages).

---

## Epic E04 — Profiles System
**Goal:** replace flat checkbox list with 4 named profiles + advanced tab.
- E04-W01: Define `playbook/profiles/{balanced,performance,privacy,security}.yml` which set FeaturePage default states in a structured data file.
- E04-W02: Rewrite `playbook.conf` FeaturePages section (profile radio page + grouped advanced pages for Privacy/Security/Performance/Interface/Apps/Network/Power).
- E04-W03: Implement profile keyed under `HKLM\SOFTWARE\AtlasOS\Profile` (name, selected options).
- E04-W04: Post‑install profile switcher PowerShell module function `Switch-AtlasProfile`.
- E04-W05: Toolbox UI for profile switching (blocked on E11).
- E04-DOC: Publish the profile matrix in `docs/user/profiles.md`.
- E04-TST: Four automated installs (one per profile), verify registry/service/AppX outcomes.

---

## Epic E05 — AI Feature Category
**Goal:** cover Recall, Click to Do, Cocreator/Generative Fill, Windows AI
Fabric, Copilot, and AI Actions on 24H2/25H2.
- E05-W01: `disable-recall.yml` — GPO + DISM optional‑feature removal, detect step for non‑Copilot+ PCs.
- E05-W02: `disable-click-to-do.yml` + revert.
- E05-W03: `disable-ai-image-features.yml` (Paint/Snipping Cocreator).
- E05-W04: `disable-copilot-app.yml` using April 2026 "Remove Microsoft Copilot App" GPO + AppX removal.
- E05-W05: `disable-windowsaifabric.yml` service disable with detect.
- E05-W06: `disable-ai-actions.yml` (File Explorer Actions menu).
- E05-W07: Desktop toggles under `2. Configuration/AI Features`.
- E05-TST: VMs on 26100 + 26200 confirm feature toggles apply and revert cleanly.

---

## Epic E06 — Gaming / Latency Category
**Goal:** evidence‑based latency/performance tweaks with profile guards and
benchmarks. Drop placebo tweaks.
- E06-W01: Audit existing performance tweaks; mark each Keep/Optional/Drop with benchmark citation.
- E06-W02: Remove defaults that cause micro‑stutter (disable‑paging, blanket `bcdedit /set disabledynamictick yes`) — keep as optional gaming‑only.
- E06-W03: `timer-resolution.yml` using MeasureSleep + SetTimerResolution, with revert.
- E06-W04: `power-plan.yml` (auto‑detect laptop vs. desktop via Win32_ComputerSystem PCSystemType).
- E06-W05: `core-parking.yml`, `ndu-disable.yml`, `hags-toggle.yml` as optional with revert.
- E06-W06: Game Mode forced ON; write documentation explaining why we leave it on.
- E06-W07: `fullscreen-optimizations.yml` that enables "Optimizations for windowed games" (24H2+).
- E06-TST: Benchmark harness integration for each tweak (E10).

---

## Epic E07 — Enterprise / CIS Baseline
**Goal:** opt‑in CIS Level‑1 equivalent, Sysmon option, BitLocker wizard.
- E07-W01: Curated CIS L1 subset (avoid settings that break consumer workflows), stored as LGPO import.
- E07-W02: `cis-baseline.cmd` installer + revert.
- E07-W03: Optional Sysmon 15 install with Olaf Hartong modular config, hash‑pinned download, config updater scheduled task (off by default).
- E07-W04: BitLocker enable wizard (detects TPM, resumes existing state).
- E07-W05: LSA protection (`RunAsPPL`) + HVCI default guidance.
- E07-W06: Defender ASR rules – enable low‑FP block set.
- E07-W07: Silent‑install flags + transform file support (for Intune/Autopilot).
- E07-DOC: Enterprise deployment guide + documented MDM interactions.

---

## Epic E08 — Networking Hardening (Tiered)
- E08-W01: Refactor existing networking tweaks into `stock/recommended/hardened` tiers.
- E08-W02: Re‑enable LLMNR disable behind a policy guard (currently commented out), with revert.
- E08-W03: Optional SMB1 removal + SMB signing hardening.
- E08-W04: Ensure NCSI/NLA stays enabled.
- E08-W05: Document why we don't apply TCP autotuning tweaks.
- E08-W06: Optional telemetry hosts/FW blocklist (Privacy profile only), using a generated list with documentation.

---

## Epic E09 — Shared Atlas Module v1.0
**Goal:** finalize the API surface, reach 100% Pester coverage for public functions.
- E09-W01: Lock public API list (see §6.1 of ROADMAP).
- E09-W02: Write comprehensive help for every public cmdlet.
- E09-W03: Add `Test-AtlasSignature` (Authenticode), `Set-AtlasPolicyValue`, `Register-AtlasRollback`, `Get/Set-AtlasState`.
- E09-W04: PSScriptAnalyzer ruleset + CI job (fail on warnings in `main`).
- E09-W05: Unit tests in `tests/unit/` — 100% coverage of public functions (internal may be lower, tracked separately).
- E09-W06: Localization binding (`Import-LocalizedData` in module, fallback en‑US).

---

## Epic E10 — Testing Infrastructure & Benchmark Harness
- E10-W01: Pester 5 bootstrap + `tests/tweaks/` convention (one test per YAML).
- E10-W02: Windows Sandbox integration runner (`tooling/ci/Run-SandboxTest.ps1`).
- E10-W03: Idempotency test job in CI.
- E10-W04: Upgrade test job (0.5 → current) on release branches.
- E10-W05: Benchmark harness in `tooling/benchmarks/` (boot time via ETW, idle RAM/CPU, timer‑res check, DPC latency via `xperf`).
- E10-W06: Fixed‑hardware runner definition + reproducible setup doc.
- E10-W07: PR bot comment with before/after benchmark deltas on performance changes.

---

## Epic E11 — Toolbox v1 (Graduate from BETA)
- E11-W01: Open source Atlas Toolbox (submodule `Atlas-OS/atlas-toolbox`).
- E11-W02: Profile switcher UI, health status dashboard, toggle categories.
- E11-W03: Live log viewer for Atlas runs.
- E11-W04: Diagnostics export button.
- E11-W05: One‑click update check (manual, no background polling).
- E11-W06: Code signing + hash verification in release pipeline.

---

## Epic E12 — Secure Supply Chain & Release Signing
- E12-W01: Pin all GitHub Actions to SHAs (Dependabot maintains them after).
- E12-W02: SLSA‑3 provenance via `slsa-github-generator`.
- E12-W03: Cosign/GPG signing of APBX + checksums; publish public key.
- E12-W04: SBOM generation in CycloneDX + SPDX formats.
- E12-W05: Vulnerability scanning of bundled binaries (Trivy/Grype) in CI.
- E12-W06: Publish on every release; link hashes + signatures in release notes.
- E12-W07: Update SECURITY.md with security‑researcher hall‑of‑fame and disclosure policy.

---

## Epic E13 — Hardened CI/CD Pipeline
- E13-W01: Separate lint / validate / build‑cab / build‑apbx / sandbox / benchmark / sign / publish jobs.
- E13-W02: Least‑privilege `permissions:` per job; environment approvals for publish.
- E13-W03: Replace auto‑commit bot with auto‑PR for cab/hash regeneration.
- E13-W04: Nightly build against latest Windows cumulative update (detects patch breakage).
- E13-W05: Add self‑hosted ARM64 runner for native ARM64 builds.

---

## Epic E14 — Localization Framework
- E14-W01: Extract every user‑visible string to `i18n/en-US.psd1`.
- E14-W02: `tooling/dev/Build-FeaturePages.ps1` to emit AME FeaturePage XML from localized strings.
- E14-W03: Script analyzer rule that flags raw English strings in scripts.
- E14-W04: CI check that per‑locale PSD1 has same keys as en‑US.
- E14-W05: Docs/translation guide + CONTRIBUTING section inviting translators.

---

## Epic E15 — Desktop Folder Overhaul
- E15-W01: New folder hierarchy per §11.1 of ROADMAP.md (use junctions so old paths don't break).
- E15-W02: Migrate all existing `.cmd` to be thin wrappers around `RunAtlasScript.cmd`.
- E15-W03: Rename "AtlasOS Toolbox" install entry to "Atlas Toolbox" and point at open‑source release.
- E15-W04: Consistent UI patterns (ASCII banner, colored status lines, `/silent` support, `/log <path>` option).
- E15-W05: "Install Software" multi‑select menu using `multichoice.exe` with verified‑download pipeline.

---

## Epic E16 — Documentation (User + Contributor)
- E16-W01: Auto‑generated tweak reference (`tooling/dev/New-TweakReference.ps1`).
- E16-W02: Auto‑generated binary hash README.
- E16-W03: Auto‑generated Atlas module cmdlet docs (PlatyPS).
- E16-W04: Profile guide + performance explainer + security explainer for end users.
- E16-W05: Enterprise deployment guide (silent install, Intune/Autopilot, coexistence).
- E16-W06: Developer docs: coding standards, "add a tweak" walkthrough, PR/release process.
- E16-W07: Link checker + markdownlint in CI.

---

## Epic E17 — Verified Downloads Everywhere
- E17-W01: Harden `Get-AtlasVerifiedFile.ps1` to v1 (atomic write, TLS 1.3, Authenticode support, cache index).
- E17-W02: Add `tooling/ci/Binaries.versions.json` listing every external binary/script with SHA‑256 and source URL.
- E17-W03: Port browser installs (Brave, Firefox, Chrome, LibreWolf), Open‑Shell install, Toolbox install, Sysmon install, multichoice/SetTimerResolution updates to use the helper.
- E17-W04: Validator rule that blocks raw `Invoke-WebRequest`/`Start-Process`/`curl.exe` outside `Get-AtlasVerifiedFile`.
- E17-W05: Dependabot‑style update PRs for upstream releases (tracked via GitHub releases RSS).

---

## Epic E18 — Health Check Completeness
- E18-W01: Expand to all 16 sub‑tests from §6.5 of ROADMAP.md.
- E18-W02: Auto‑fix for safe issues (wrong service start for disabled service, missing registry key) behind a "Fix" prompt.
- E18-W03: Post‑install scheduled task runs health check once (first boot) and surfaces toast if failures.
- E18-W04: JSON report included in diagnostics export.
- E18-W05: Optional Windows Event Log provider `Atlas` for health events.

---

## Epic E19 — Diagnostics & Telemetry‑Redaction
- E19-W01: Add msinfo32 NFO export, driver list, event log snippets.
- E19-W02: Redaction layer that scrubs usernames, hostnames, domain names, IPs, machine GUID.
- E19-W03: One‑click "Upload to GitHub issue" (opens a pre‑filled issue with drag‑and‑drop reminder — no automatic upload).
- E19-W04: Performance snapshot (boot trace summary from benchmark harness if present).

---

## Epic E20 — Known‑Bug Resolution Sweep
Concrete GitHub issues the v1.0 release must close:
- E20-W01: #1509 (25H2 AME msvcp140.dll race) → pre‑flight process kill + retry.
- E20-W02: #1353 (Store crash on OEM images) → ACL detection + repair script.
- E20-W03: #1273 (re‑apply fails) → E02 state engine.
- E20-W04: #1406 (v0.5 micro‑stutter) → E06 performance audit + remove paging disable.
- E20-W05: #1522 (install logs show non‑fatal errors) → E02/E18 so all errors are surfaced/explained.
- E20-W06: Non‑English locale install issues (zh‑CN reports) → E14 i18n + UTF‑8 codepage handling.

---

## Epic E21 — Dev Experience
- E21-W01: `tooling/dev/Setup-DevEnvironment.ps1` installs Pester, PSScriptAnalyzer, yamllint, cspell, VS Code extensions.
- E21-W02: VS Code tasks.json updated for new structure.
- E21-W03: Dev container for Linux/macOS contributors (runs all static checks; no APBX build).
- E21-W04: Pre‑commit hooks (pre‑commit.com) for PS1/YAML/MD formatting.
- E21-W05: `scripts/dev/Build-AtlasPlaybook.ps1` builds APBX + regenerates hashes/SBOM + runs validator.

---

## Epic E22 — Release Process & Governance
- E22-W01: Release checklist (doc from v0.6) enforced by a CI gate `release‑ready` job.
- E22-W02: Branch protection rules documented in `docs/contributing/branching.md`.
- E22-W03: LTS policy for 1.1.x documented.
- E22-W04: Security‑review window (30 days) before v1.0 ships; tracked via GitHub Security Advisory.
- E22-W05: Open public roadmap page on docs.atlasos.net auto‑generated from this file.

---

## Suggested Milestone Schedule

| Milestone | Theme | Est. duration |
|---|---|---|
| v0.7.0 | E01, E02, E09, E21 | 4–6 weeks |
| v0.8.0 | E03, E05, E06, E08, E18 | 6–8 weeks |
| v0.9.0 | E04, E11, E14, E15, E17, E19 | 6–8 weeks |
| v0.9.5 RC | E07, E10, E13, E16, E20 | 4–6 weeks |
| v1.0.0 | E12, E22, public security review, sign‑off | 4 weeks |

Parallel work can collapse this: E12/E13/E14/E16 can run alongside E05/E06/E07.

---

## Definition of Done per Work Item

Every E??-W?? ticket is not "done" until:
1. Code is merged to `main` with at least one approving review from CODEOWNERS.
2. Pester tests exist and pass on 5.1 and 7 for PS changes.
3. YAML includes title, description, citation, `appliesTo`, detect, revert.
4. Validator (`tooling/ci/Validate-AtlasPlaybook.ps1 -Strict`) passes.
5. Documentation is updated (per‑tweak doc + relevant guide).
6. If a user‑visible change: changelog entry under `Unreleased`.
7. If a security‑sensitive change: reviewed by the security CODEOWNER.
