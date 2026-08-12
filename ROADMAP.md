# Atlas v1.0 — Zero‑Compromise Roadmap & Blueprint

> **Mission.** Make Atlas the most transparent, most performant, most secure,
> most thoroughly‑tested Windows modification in existence — while remaining
> fully open, auditable, backwards‑compatible where it matters, and honest
> about trade‑offs.
>
> **Rule.** Zero compromises on auditability, integrity, stability, or
> correctness. No placebo tweaks. No telemetry of our own. No bundled binaries
> without pinned hashes. No claim we cannot prove with a benchmark or a test.
>
> **Audience.** Power users, gamers, privacy‑conscious individuals, OEMs,
> boutique system builders, and managed‑IT/enterprise deployments that need a
> hardened Windows baseline.
>
> **Target versions.** Windows 11 24H2 (26100) and 25H2 (26200) for v1.0, with
> forward‑compatible design so future builds (26Hx) require only delta updates.

This document is the single source of truth for what Atlas is becoming. It is
deliberately concrete — every section names the artifacts to create, the tests
to add, and the acceptance criteria. Companion documents:

- `ANALYSIS.md` – gap analysis of the current repo (starting point)
- `CHANGELOG.md` – shipped work (v0.5.0 / v0.6.0 / future)
- `docs/architecture/README.md` – living architecture description
- `docs/security/README.md` – security policy

---

## 0. Brainstorm & Research Summary (evidence base)

Concrete findings that shaped this blueprint:

**OS feature churn (24H2 → 25H2).** Microsoft has layered in a new class of AI
components that previous Atlas releases don't fully cover:

- **Windows Recall** (Copilot+ PCs) — screenshot/snapshot capture (`Recall`
  optional feature, `AllowRecallEnablement`, `DisableAIDataAnalysis` under
  `Policies\Microsoft\Windows\WindowsAI`).
- **Click to Do** — on‑canvas AI actions for text/images
  (`DisableClickToDo`).
- **Image Creator / Cocreator / Generative Fill** — Paint/Snipping Tool/Photos
  AI features (`DisableImageCreator`, `DisableCocreator`, `DisableGenerativeFill`,
  `DisableAIDataAnalysis`).
- **Windows AI Fabric Service** — new background service with NPU/CPU/battery
  impact.
- **Copilot app** (AppX `Microsoft.Copilot*`) — re‑engineered repeatedly across
  builds; legacy `TurnOffWindowsCopilot` policy is deprecated in favor of the
  April 2026 "Remove Microsoft Copilot App" GPO.
- **MSEdgeRedirect requirement** — Widgets/web search hardcoded to Edge; we need
  a reversible solution (documented choice, not forced).

**Competitive landscape (mid‑2026).**

| Tool | Strengths | Weaknesses Atlas must beat |
|---|---|---|
| [Win11Debloat](https://github.com/Raphire/Win11Debloat) | Custom mode, huge feature set, active | Scattershot, no install‑time wizard, no per‑choice docs, no integrity checks |
| [Chris Titus WinUtil](https://github.com/ChrisTitusTech/winutil) | WPF GUI, winget installs | `irm|iex` distribution by default, no CI‑gated guarantees, mixes unrelated features |
| [NTLite](https://www.ntlite.com) | Pre‑install image editing, 25H2 AI component removal | Paid, closed‑source, image‑only (not post‑install) |
| [Sophia Script/SophiApp](https://github.com/Sophia-Community) | PowerShell‑native, well‑documented | Less opinionated, fewer privacy defaults |
| [O&O ShutUp10++](https://www.oo-software.com/en/shutup10) | Safe, per‑toggle explanations | No automation/orchestration, GUI only |
| [privacy.sexy](https://privacy.sexy) | Extensible tweak compiler | Code‑gen output; no cohesive "product" |
| [meetrevision/playbook](https://github.com/meetrevision/playbook) | AME Wizard based like Atlas | Different design goals, smaller scope |
| Current Atlas v0.5 | Transparent AME playbook, good baseline | No tests, duplicated boilerplate, no hash verification, weak CI, no diagnostics |

**Hardening standards we must at least *reference*, not blindly apply:**
- CIS Microsoft Windows 11 Enterprise Benchmark v3 (280 L1, 365 L2 settings).
- Microsoft Security Baseline for Windows 11 24H2.
- DISA STIG (Win11 STIG is delayed but Win10 v1r5 + client guidance apply).
- MITRE ATT&CK mitigations relevant to consumer endpoints.
- Sysmon with Olaf Hartong modular config / SwiftOnSecurity baseline.

**Real bug reports (Atlas repo, past 12 months) that drive feature work:**
- 25H2 install fails with `msvcp140.dll` in use → race in AME extraction
  (mitigation: pre‑flight process kill, retry loop).
- Microsoft Store crashes on OEM images after playbook → need to detect OEM
  `WindowsApps` ACL changes and warn/repair.
- Performance regression vs. v0.4.0 (micro‑stutter) → need a benchmark harness
  so we stop shipping performance regressions.
- Defender toggle pages disappeared → need to detect when AME requirement
  `DefenderToggled` isn't met and provide richer error UX.
- No uninstall / re‑apply path → one must exist in v1.0.

**Gaming/latency research that's actually backed by measurements:**
- HAGS (Hardware‑Accelerated GPU Scheduling) saves 2–5 ms on supported HW but
  can cause issues on older drivers → make it a *choice* not a default.
- VBS / Memory Integrity costs 5–15% FPS / 5–15 ms input lag → off by default
  in "performance" profile, on in "secure" profile.
- Timer resolution / dynamic tick / platform tick affect DPC latency; blanket
  `bcdedit /set useplatformtick yes` is NOT universally correct → profile‑based.
- Core parking, power plan, and NDIS interrupt moderation matter for
  competitive gaming but break laptops badly → auto‑detect form factor.
- RTSS/reflex/native in‑game FPS caps dominate driver/control‑panel tweaks →
  document instead of pretending to control.

---

## 1. Product Vision & Design Principles (the "zero compromises")

1. **Auditability by default.** Every setting change is a plain‑text YAML entry
   or a short, well‑commented script. Every bundled binary is in `hashes.sha256`
   and in the SBOM. Every network download goes through a single hash‑verifying
   function.
2. **No placebo.** Every tweak must cite a primary source (MS docs, STIG, CIS,
   measured benchmark). Tweaks with disputed effects ship as *optional*, with
   UI text that explains the controversy.
3. **Profiles, not monoliths.** Four install‑time profiles (documented below),
   plus post‑install toggles that can move between profiles without
   reinstalling.
4. **Idempotency.** Running the playbook twice yields the same result as
   running it once. Re‑running after a Windows cumulative update is supported
   and tested.
5. **Rollback is real.** Every category writes a per‑category revert script.
   A single "Restore Windows defaults" script can undo service/registry policy
   changes; an "Uninstall Atlas" flow restores services, re‑enables AppX
   provisioning, and removes the Atlas folders (components removed via CAB
   packages cannot be restored without reinstall media — we are honest about
   this).
6. **Deterministic.** The same `playbook.conf` + feature options + OS build
   must produce the same system state. No random GUIDs, no timestamps in
   configs that cause diff churn, no network calls at install time except
   explicitly user‑opt‑in items (browser install, toolbox).
7. **Tested.** Every tweak is covered by at least one Pester test that asserts
   the expected registry/service state is reached. CI runs install‑dry‑run
   validation on every PR.
8. **Measured.** A benchmark harness (latency, FPS, idle RAM/CPU, DPC, boot
   time) runs against each release candidate and publishes results.
9. **Localizable.** All user‑visible strings live in `.psd1`/`.resx`; English
   is primary but translators don't need to touch code.
10. **Enterprise ready.** GPO/Intune/Autopilot‑friendly. Supports silent
    install, configuration profiles via a transform file, and writing logs to a
    network share. Does not fight MDM.
11. **No telemetry. Ever.** Not opt‑in, not anonymous‑ish. The diagnostics
    export is a manual user action and never phones home.
12. **Secure supply chain.** Pin all GitHub Actions by SHA, generate SBOM and
    SLSA‑level‑2 provenance, sign releases, offer a PGP signature and signed
    checksums.

---

## 2. Release Plan & Versioning

**Versioning.** Semantic Versioning applied to the playbook:
`MAJOR.MINOR.PATCH` (e.g., `1.0.0`, `1.1.0`, `1.0.1`).
- MAJOR = breaking change to configuration layout or supported Windows
  version / requires fresh install.
- MINOR = new feature / new tweak / new category, backwards‑compatible with
  existing `AtlasModules` layout.
- PATCH = bug fix, hash refresh, registry correction.

**Tracks.**
- `main` is always releasable (green CI, all tests pass, signed artifacts).
- `feature/*` branches for PRs; protected, require CI + 1 review.
- `release/vX.Y.Z` branches cut for RC builds; patched off main when needed.
- Long‑term support: the `.1` minor release of each major (e.g., 1.1) becomes
  the LTS until the next major + 3 months.

**Release cadence.**
- **Nightlies:** built on every push to main, for testers.
- **RC:** cut when all targeted issues are closed, soak‑tested for 7 days.
- **Stable:** RC with no open regressions. Signed, SBOM, SHASUMS, SHASUMS.asc.

**Supported Windows builds per v1.0**

| Build | Codename | Supported |
|---|---|---|
| 26100.x | Windows 11 24H2 | ✅ primary target |
| 26200.x | Windows 11 25H2 | ✅ primary target |
| 26Hx+ (future) | TBD | ✆ design target; will add when MS releases |

Windows 10 is explicitly out of scope for v1.0; an optional porting layer
(community‑maintained) is allowed if it doesn't burden the core.

---

## 3. Profiles (the UX centerpiece)

The current `playbook.conf` feature pages are a flat list of checkboxes. In
v1.0 we replace that with **named profiles** *plus* advanced customization.
Profiles are written to `HKLM\SOFTWARE\AtlasOS\Profile` and drive default
checkbox states on the advanced page.

| Profile | Description | Defaults |
|---|---|---|
| **Balanced (recommended)** | Privacy on, security on, QoL on, performance = stock + low‑risk tweaks. Laptops welcome. | Defender ON, mitigations default, auto‑updates ON, hibernation default, power‑saving on laptops, Edge optional, VBS default (on), Core Isolation default |
| **Performance** | Gamer / workstation bias. Security trade‑offs clearly labeled. | Defender optional, mitigations off (user must acknowledge), auto‑updates notify‑only, hibernation OFF, power‑saving OFF, HAGS choice, VBS off (warn), Core Isolation off (warn), Timer resolution 0.5ms, power plan "High Performance" or "Ultimate" |
| **Privacy‑Hardened** | Maximize data minimization even at cost of Store/OneDrive/Edge. | Defender optional, mitigations default, auto‑updates off (warn), AI/Recall/Copilot removed, telemetry endpoints blocked via FW + hosts + services, no Edge, no widgets, no Store optional |
| **Security‑Focused** | Enterprise‑aligned. Defender, SmartScreen, BitLocker, LSA protection, Credential Guard (opt), Sysmon install option, attack surface reduction rules. | Defender ON, mitigations ON, auto‑updates forced, BitLocker prompt, SmartScreen ON, VBS on, HVCI on, no telemetry removal that breaks Defender for Endpoint |

A fifth state, **Custom**, exposes individual checkboxes after the profile is
chosen (same UX as today, but organized into tabs/groups). The advanced page
groups toggles into: Privacy, Security, Performance, Interface, Apps, Network,
Power.

Profiles are implemented as *named YAML presets* under
`Configuration/profiles/*.yml` which set default checkbox options; users can
flip anything on the advanced page before install. Post‑install, the
**Atlas Toolbox/Desktop folder** can swap profiles non‑destructively (it
re‑runs idempotent playbooks for changed categories).

---

## 4. Repository Architecture (re‑layout)

```
Atlas/
├── playbook/                      # The AME playbook (renamed from src/playbook)
│   ├── playbook.conf              # AME manifest
│   ├── core/                      # Former Configuration/atlas/ — ordered phases
│   │   ├── 000-start.yml
│   │   ├── 010-init-modules.yml
│   │   ├── 020-services.yml
│   │   ├── 030-components.yml
│   │   ├── 040-appx.yml
│   │   ├── 050-defaults.yml
│   │   ├── 060-revert.yml
│   │   ├── 070-apply-tweaks.yml
│   │   ├── 080-cleanup.yml
│   │   ├── 090-health.yml
│   │   └── 999-finalize.yml
│   ├── profiles/                  # New — named profiles
│   │   ├── balanced.yml
│   │   ├── performance.yml
│   │   ├── privacy.yml
│   │   └── security.yml
│   ├── tweaks/                    # Category tweaks (retained; restructured)
│   │   ├── privacy/
│   │   ├── security/
│   │   ├── performance/
│   │   ├── networking/
│   │   ├── qol/
│   │   ├── debloat/
│   │   ├── ai/                    # New: Recall/ClickToDo/Copilot/Paint Cocreator
│   │   ├── gaming/                # New: latency-oriented, optional
│   │   ├── enterprise/            # New: CIS/STIG-aligned, opt-in
│   │   └── scripts/
│   ├── revert/                    # New — per-tweak revert scripts
│   ├── assets/
│   │   ├── desktop/               # Former Executables/AtlasDesktop
│   │   ├── modules/               # Former Executables/AtlasModules
│   │   │   ├── lib/Atlas/         # Shared PowerShell module
│   │   │   ├── health/
│   │   │   ├── diagnostics/
│   │   │   ├── rollback/
│   │   │   ├── security/
│   │   │   ├── packages/
│   │   │   ├── tools/
│   │   │   ├── scripts/
│   │   │   ├── themes/
│   │   │   └── wallpapers/
│   │   ├── themes/
│   │   └── images/
│   └── root.yml                   # Former custom.yml — just an ordered include list
├── packages/                      # Former src/sxsc — CAB package definitions
│   ├── defender-remover/
│   ├── no-telemetry/
│   └── misc/
├── tooling/                       # Former scripts/ + build helpers
│   ├── ci/
│   ├── dev/
│   ├── benchmarks/
│   └── release/
├── tests/                         # New — Pester + integration test suites
│   ├── unit/                      # Pure PowerShell function tests
│   ├── tweaks/                    # Per-tweak assertions (registry/service state)
│   ├── integration/               # VM-based tests (Hyper-V / QEMU)
│   └── fixtures/
├── docs/
│   ├── architecture/
│   ├── contributing/
│   ├── security/
│   ├── release/
│   ├── tweaks/                    # Auto-generated tweak reference
│   └── user/                      # End-user docs (syncs to docs.atlasos.net)
├── i18n/                          # New — localization strings
│   ├── en-US.psd1
│   └── …
├── .github/
└── (root files)
```

**Why re‑layout?**
- Numeric prefixes on core phases enforce order without relying on a hand‑coded
  include list.
- `revert/` makes rollback a first‑class feature instead of an afterthought.
- `tweaks/ai/` and `tweaks/gaming/` give explicit homes for new feature areas
  that were previously spread across privacy/qol/performance.
- `tweaks/enterprise/` gives CIS/STIG/ASR a controlled opt‑in path, so we never
  accidentally ship domain‑breaking settings to consumers.
- `tests/` at the root makes "code lives next to tests" obvious.

Migration is automated by a `tooling/dev/Migrate-RepoLayout.ps1` script that
moves files and fixes include paths in existing YAMLs, so no hand‑editing of
200 files is required.

---

## 5. Core System Re‑architecture

### 5.1 Idempotent state engine
Today, `custom.yml` calls phases linearly but doesn't check if the desired
state is already achieved (risking re‑apply failures and Microsoft Store
breakage on OEM images). Replace with a state engine:

- Each tweak YAML can declare `appliesTo:` (build ranges), `detect:` (script
  that returns `$true` if the tweak is already applied), and `revert:` (path to
  a revert script).
- A core function `Set-AtlasState -Category <name> -Desired <Enabled|Disabled>`
  runs detect first and only invokes the apply script if needed.
- The AME wizard checkbox option values flow to `Set-AtlasState`; re‑applying
  the playbook is safe because the engine becomes idempotent.

### 5.2 Telemetry blocking = layered defense
A single "disable telemetry" checkbox will block telemetry at four layers,
documented explicitly so users know what is being done:
1. **Group Policy / Registry** — documented policy keys, same as today.
2. **Services** — disable `DiagTrack`, `dmwappushservice`, etc., with backups.
3. **Scheduled Tasks** — disable telemetry tasks; enumeration is generated from
   a manifest (not hardcoded), allowing delta updates for new builds.
4. **Hosts / Windows Firewall block rules** (optional, off by default because
   it breaks Windows Update and Defender signature updates; exposed in the
   Privacy‑Hardened profile only).

For Microsoft Edge telemetry, use the existing Chromium policy keys via
`HKLM\SOFTWARE\Policies\Microsoft\Edge\...` instead of force‑uninstalling Edge,
and keep Edge removal as an explicit option.

### 5.3 AI feature control (new category `tweaks/ai/`)
Per research in §0:
- `disable-recall.yml` — removes the optional feature via DISM + GPO, works on
  non‑Copilot+ PCs (no‑op safely).
- `disable-click-to-do.yml` — GPO for `DisableClickToDo`.
- `disable-ai-image-features.yml` — GPOs for Cocreator/GenerativeFill/Image
  Creator.
- `disable-copilot-app.yml` — AppX removal + the new 2026 "Remove Microsoft
  Copilot App" GPO + hides taskbar button; revert script re‑provisions.
- `disable-windowsaifabric.yml` — stops and disables `WindowsAIFabric` service
  only if it exists, with a detect step.
- `disable-ai-actions.yml` — disables new Actions menu in File Explorer
  (25H2+).

### 5.4 Gaming / latency (new category `tweaks/gaming/`)
- Latency tweaks are split into **profiles** (no one‑size‑fits‑all):
  - `timer-resolution.yml` — 0.5ms via MeasureSleep + SetTimerResolution, with
    revert script that restores defaults.
  - `power-plan.yml` — switches between Balanced / High / Ultimate based on
    laptop vs. desktop auto‑detect.
  - `disable-core-parking.yml` — off idle timeouts, with profile guard.
  - `hags-toggle.yml` — optional, not forced.
  - `fullscreen-optimizations.yml` — "Optimizations for windowed games" is
    enabled (new 24H2/25H2 feature) as it reduces latency in practice.
  - `game-mode.yml` — leaves Game Mode ON (research shows it helps
    responsiveness in 24H2+).
  - `disable-ndu.yml` — Network Data Usage driver; optional due to rare
    compatibility issues.
  - `dpc-latency.yml` — documents recommended steps (driver updates, HPET
    off/on is NOT recommended as blanket; document per-platform).
- All gaming tweaks ship with a **benchmark assertion** in `tests/tweaks/`
  (e.g., verifies that timer resolution is reported ≤ 1.0 ms after the tweak).

### 5.5 Security baseline (new category `tweaks/security/enterprise/`)
Optional, only applied in Security‑Focused profile or when user opts in:
- Import Microsoft Security Baseline LGPO pack for 24H2/25H2.
- CIS Level‑1‑equivalent subset (curated list — won't enable settings that
  brick consumer workflows).
- Optional Sysmon install with Olaf Hartong modular config (user opt‑in,
  downloads via `Get-AtlasVerifiedFile` with pinned hash).
- Optional BitLocker enable wizard (only on capable hardware, resumes from
  existing state).
- LSA protection (`RunAsPPL=1`), no new WinEvent logs disabled.
- Defender ASR rules (enable block mode for the low‑false‑positive set).
- All guarded by `detect:` so re‑runs don't break domain GPO.

### 5.6 Networking
- Add a **tiered approach**:
  1. Stock (good) – keep DNS/LLMNR/NCSI as they are, no risk.
  2. Recommended – disable LLMNR via policy (currently commented out), disable
    SMB1 (already?), restrict anonymous enumeration per STIG.
  3. Hardened – optional hosts/FW rules for telemetry endpoints (privacy
    profile), DNS‑over‑HTTPS configuration guide, disable NetBIOS over TCP/IP.
- Do NOT disable NCSI/NLA (breaks corporate VPNs / captive portals).
- Do NOT change default TCP autotuning (disproven as a latency tweak).

### 5.7 Performance, without placebo
Drop tweaks that have been debunked (keeping revert scripts for anyone who
wants them as *explicitly‑labeled optional*):
- ~~Disable prefetch/superfetch~~ → keep Superfetch (SysMain) on.
- ~~Disable paging file~~ → do NOT disable by default (crashes apps and causes
  MicroStutter — likely root cause of the v0.4→v0.5 stutter reports).
- ~~bcdedit tweaks~~ (disabledynamictick, useplatformtick) → make them optional
  gaming tweaks, not defaults.
- Keep: NTFS last‑access, 8dot3, Hibernation choice, background apps, FTH.
- New: explicitly **measure** each tweak's effect via the benchmark harness
  (§7.2) and drop any that don't show ≥2% improvement in a relevant metric
  without regressing others.

### 5.8 Revert & Uninstall (first‑class)
- Every tweak gains a sibling revert script under `playbook/revert/<category>/<name>.cmd`.
- `AtlasDesktop/9. Troubleshooting/Rollback/Restore Windows Services.cmd`
  already exists (v0.6). Add:
  - `Restore Group Policies.cmd` – removes `Policies\Microsoft\Windows\...` keys
    that Atlas set.
  - `Restore AppX Provisioning.cmd` – re‑provisions all inbox apps.
  - `Restore Default Services.cmd` – expands current service restore to cover
    all services Atlas touched.
  - `Uninstall Atlas.cmd` – runs all reverts, removes Atlas folders, removes
    scheduled tasks, logs to `$env:TEMP\AtlasUninstall.log`. A final reboot
    prompt reminds user that CAB‑removed components may require repair install.
- All reverts idempotent; detect state before acting.

---

## 6. PowerShell Module & Coding Standards

### 6.1 Atlas module (`assets/modules/lib/Atlas/`) v1.0
Grow the v0.6 module into the single public API for all scripts. Public
functions (all Pester‑tested):

- **Logging** – `Start-AtlasLog`, `Write-AtlasLog` (DEBUG/INFO/WARN/ERROR/SUCCESS
  with color), `Stop-AtlasLog`, `New-AtlasProgressWriter`, `Write-AtlasHeader`.
- **State** – `Get-AtlasState`, `Set-AtlasState`, `Test-AtlasTweakApplied`,
  `Register-AtlasRollback` (registers a revert script for a category).
- **Privilege** – `Test-AtlasAdmin`, `Test-AtlasTrustedInstaller`,
  `Ensure-AtlasAdmin` (re‑launches elevated), `Get-AtlasSystemArchitecture`.
- **Registry** – `Get/Set/Remove-AtlasRegistryValueSafe`,
  `Set-AtlasPolicyValue` (writes into `Policies\...` with tracking key),
  `Test-AtlasRegistryPath`.
- **Services** – `Set-AtlasServiceStart`, `Test-AtlasServiceExists`,
  `Backup-AtlasServices`, `Restore-AtlasServices`.
- **Packages / AppX** – `Remove-AtlasAppx`, `Repair-AtlasAppx`,
  `Get-AtlasAppxProvisioned`, `Remove-AtlasWindowsPackage` (for CAB‑based).
- **Network** – `Add-AtlasFirewallRule`, `Block-AtlasHostsEntry`,
  `Test-AtlasEndpoint`.
- **Integrity** – `Get-AtlasFileHash`, `Compare-AtlasHashTable`,
  `Get-AtlasVerifiedFile` (§5.9), `Test-AtlasSignature`.
- **Health** – `Invoke-AtlasHealthCheck` (all sub‑tests in §6.4).
- **Diagnostics** – `Export-AtlasDiagnostics` (zip).
- **Platform** – `Test-AtlasIsLaptop`, `Test-AtlasIsVM`,
  `Get-AtlasWindowsBuild`, `Get-AtlasBuildRangeSatisfied`.
- **UI** (desktop scripts only) – `Show-AtlasMessageBox`,
  `Show-AtlasChoiceMenu`, `Write-AtlasMenuHeader`.

### 6.2 Coding standards (enforced by tooling)
- **`Set-StrictMode -Version Latest`** and `$ErrorActionPreference = 'Stop'` at
  the top of every script (validator enforces).
- Named param blocks with `[CmdletBinding()]`, no positional surprises.
- No `Invoke-Expression`. No `iex`. No `irm | iex`.
- All strings in user‑facing scripts come from `i18n/*.psd1` via
  `Import-LocalizedData`.
- Every public function has help (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`,
  `.PARAMETER`, `.NOTES`) — validator enforces help coverage.
- No inline COM/Shell.Application calls; use the shared API.
- PSScriptAnalyzer with custom ruleset runs in CI; warnings = hard failure on
  `main`.
- Functions < 80 lines when reasonable; single responsibility.
- `-Verbose` works across the entire script chain for debugging.

### 6.3 Single launcher (`RunAtlasScript.cmd`)
Fully replace duplicated boilerplate in every AtlasDesktop script with
delegation to `RunAtlasScript.cmd <target.ps1> [args...]`. The v0.6 launcher is
already in place; finish the migration across all 199 `.cmd` files in batches
by category.

### 6.4 Hash‑verified downloads (`Get-AtlasVerifiedFile`)
Single canonical function for every network call:
- Enforces **HTTPS only** (https:// URLs).
- Enforces **TLS 1.2 minimum**, offers TLS 1.3 when available.
- Takes a `-ExpectedHash <sha256>` parameter — mandatory for install‑time
  downloads; for user‑initiated fetches (browser install) the hash can be
  "latest" but then we verify the Authenticode signature and pin the
  publisher.
- Performs atomic write (write to `.download` temp, rename on success) so
  failures never leave corrupted executables on disk.
- Optional `-SignatureThumbprint` Authenticode verification.
- Cached in `$env:LOCALAPPDATA\Atlas\Cache` with hash index.

All installers (Brave, Firefox, Chrome, LibreWolf, Open‑Shell, Toolbox,
Sysmon, multichoice binary updates, SetTimerResolution updates) must be ported
to this helper.

### 6.5 Health check (`Invoke-AtlasHealthCheck`)
Expand the v0.6 health check into 15+ named sub‑tests covering:

1. Supported build range.
2. Core files present.
3. Hash manifest matches.
4. Critical service states match profile.
5. Defender state matches the profile choice (not "missing").
6. Windows Update service state matches profile.
7. No pending reboot.
8. Atlas state keys present in HKLM\SOFTWARE\AtlasOS.
9. Power plan matches profile.
10. AppX provisioning baseline (no unexpected Store corruption).
11. Scheduled tasks state.
12. Network – basic connectivity and DNS.
13. Event log for recent Winlogon/Setup errors.
14. VBS/HVCI state matches profile.
15. Free disk space ≥ 5 GB (below that Windows Update fails).
16. Core Isolation / Memory Integrity state matches profile.

Outputs: console (colored), JSON file, and (optionally) a toast notification
with a "fix automatically" button for safe issues.

### 6.6 Diagnostics (`Export-AtlasDiagnostics`)
Extend the v0.6 exporter to include:
- Output of `Invoke-AtlasHealthCheck -Passthru`.
- List of installed drivers + versions.
- `msinfo32 /nfo` export (stripped of user name).
- Running services + scheduled tasks states.
- Event log snippets for Application/System/Setup last 7 days.
- Network adapter + firewall profile info.
- User profile folder sizes (no file listings).
- Atlas state key dump.
- A redaction layer (`tooling/dev/Redact-Diagnostics.ps1`) that scrubs usernames
  / hostnames / domain names when sharing.

---

## 7. Testing & Quality Engineering

### 7.1 Unit tests
Pester 5 suite in `tests/unit/`:
- Covers every public function of the Atlas module.
- Tests run on every PR (both Windows PowerShell 5.1 and PowerShell 7).
- Mocked registry (via `TestRegistry:` PSDrive) and service layer so tests run
  on Linux in CI for basic coverage.

### 7.2 Tweak validation tests
`tests/tweaks/` contains one `*.Tests.ps1` per tweak YAML that:
- Applies the tweak in a throwaway Windows Sandbox / Hyper‑V VM (see
  integration tests) or uses a mocked registry if safe.
- Asserts the *expected* state change (service start, registry value, AppX
  removal).
- Runs the corresponding revert script and asserts state is back to baseline.
- Tracks **which builds** it has been validated against (`[SupportsBuild(26100,26200)]`).

The validator script (`tooling/ci/Validate-AtlasPlaybook.ps1`) will enforce
that every tweak has a matching test file before merge to `main`.

### 7.3 Integration tests
- **Windows Sandbox mode.** For each PR, CI spins up a Windows Sandbox, runs
  the APBX in silent mode, and asserts:
  - Playbook returns exit code 0.
  - Health check passes.
  - A canary script (launch notepad, open settings, launch store once —
    guarded by timeouts) doesn't crash.
- **Hyper‑V / QEMU matrix.** For release candidates, run end‑to‑end installs on
  26100 and 26200 on both amd64 and ARM64.
- **Idempotency test.** Run the playbook twice in a row; second run produces
  zero errors, zero hash mismatches, zero service changes.
- **Upgrade test.** Install 0.5.0 → run 1.0.0 upgrade → health check passes.

### 7.4 Benchmark harness
`tooling/benchmarks/` contains a reproducible benchmark script:
- Boot time (from start to responsive desktop, Event Trace).
- Idle RAM / CPU after 5 min idle.
- DPC latency via `latencymon`‑style measurement (open source alternative).
- Timer resolution actually achieved.
- Frame‑time in a built‑in latency test (empty window present + GPU present
  test; not full 3D games — that's best left to user runs).
- Build and run **in CI** (software rasterizer) for regression detection, and
  on a fixed hardware rig for release‑candidate numbers that we publish.
- Every PR that touches performance‑relevant code must report before/after
  numbers; regressions over 2% block merge.

### 7.5 Static analysis
- `PSScriptAnalyzer` with custom severity ruleset; runs on every PS1 change.
- The YAML validator (already built in v0.6) expanded to check:
  - Every YAML has a matching revert entry.
  - Every referenced file exists.
  - Every download uses `Get-AtlasVerifiedFile`.
  - No `Invoke-Expression`, no `iex`, no `Start-Process` without verification.
  - Every tweak has `title:`, `description:`, a citation URL in comments, and
    a `appliesTo:` build range.
  - No hardcoded user names / no embedded passwords other than "malte".
- `yamllint` stricter ruleset (fail on trailing spaces, consistent
  indentation).
- `markdownlint` for docs.
- Spell checker (`cspell`) across repo with YAML/PS1/CMD word list.
- Link checker runs weekly on docs and tweak comments.

---

## 8. CI/CD Pipeline (hardened)

Build on top of the v0.6 workflow; final pipeline for v1.0:

**Triggers:** every PR, every push to `main`, every release/* tag, weekly
scheduled for dependency bumps.

**Jobs (all with pinned SHAs, least‑privilege permissions):**

1. **lint** (Ubuntu) – yamllint, markdownlint, cspell, linkchecker, Pester
   unit tests for the non‑Windows‑specific module code.
2. **validate‑ps** (Windows) – PSScriptAnalyzer over all PS files, Atlas
   validator, hashes/SBOM regen check (build fails if manifest doesn't match).
3. **build‑cab** (Windows) – sxsc packages built per config, regenerated
   cab files committed only if changed (scoped paths, bot PR not direct push).
4. **build‑apbx** (Windows) – builds the APBX for 26100 and 26200 (if we
   support multiple builds in future).
5. **integration‑sandbox** (Windows 11 latest in GitHub Actions or a self‑hosted
   runner with Hyper‑V/Nested virt): install APBX in Windows Sandbox, run
   health check, upload logs as artifacts.
6. **benchmark** (self‑hosted fixed hardware, release candidates) – run
   benchmark harness, post results as a PR comment & attach JSON artifact.
7. **sbom‑sign** – generate CycloneDX + SPDX SBOM, sign artifact + checksums
   with cosign / GPG, upload to release.
8. **publish** – on `release/v*` tag: upload signed APBX, hashes, SBOM,
   checksums to GitHub Release; trigger docs.atlasos.net update; post Discord
   announcement draft.

**Branch protection rules (must be enforced in GitHub):**
- `main` requires 1+ approving review, all conversations resolved, all CI
  jobs green, signed commits.
- CODEOWNERS file expanded so `tweaks/security/enterprise/` requires
  security‑reviewer approval.
- No direct pushes to `main` except the release bot on tagged commits.

**Secrets & supply chain:**
- All GitHub Actions pinned by SHA; Dependabot rotates SHAs weekly.
- Release signing key stored in HSM‑backed GitHub Environment secrets.
- SLSA‑3 provenance generated via `slsa-github-generator` for APBX artifacts.
- No `secrets.GITHUB_TOKEN` write access except on the publish job.

---

## 9. Localization (i18n)

- `i18n/<lang>-<REGION>.psd1` holds every user‑visible string (AtlasDesktop
  scripts, Toolbox UI, installer FeaturePage descriptions, health‑check
  output).
- English is the source of truth; CI checks that non‑English files have all
  the same keys (fails the build if a key is missing).
- Scripts access strings via `$LocalizedData.<Key>` (PowerShell native
  `Import-LocalizedData`).
- AME Wizard FeaturePage text is populated from a build‑time generator
  (`tooling/dev/Build-FeaturePages.ps1`) that reads the PSData files and
  writes the localized XML blocks into `playbook.conf`.
- Initial translation targets: en‑US, zh‑CN, es‑ES, de‑DE, pt‑BR, ru‑RU,
  fr‑FR, ja‑JP. Invite community translators once the key‑set is stable.

---

## 10. Documentation

### 10.1 Contributor docs
- `docs/contributing/` expands the v0.6 guide to include:
  - Adding a tweak (with YAML/revert/test example).
  - Coding standards + PR checklist.
  - Release process in detail (signing, publishing).
  - Security disclosure process.
- Architecture doc updates as code evolves (kept in sync by a CI check
  requiring doc updates for changes to `core/`).

### 10.2 User docs (synced to docs.atlasos.net)
- **Per‑tweak reference.** Generated from each YAML's `title:`, `description:`,
  and a new `documentation:` field, plus whether the tweak is default‑on in
  each profile. Auto‑published to docs.atlasos.net/tweaks/.
- **Profile guide** – explains exactly what each profile changes, with plain
  English and risk notes.
- **Security explainer** – what Atlas does/doesn't claim, with hash
  verification instructions.
- **Performance explainer** – what we measured, what numbers to expect on
  what hardware, what is placebo and why we don't ship it.
- **Troubleshooting** – top 10 known issues (Store, Defender toggle, 25H2
  msvcp140 race) with fix scripts.
- **Enterprise deployment guide** – silent install, transforms, Autopilot/Intune
  integration, recommended policies to manage with MDM instead.

### 10.3 Auto‑generated documentation
- `tooling/dev/New-TweakReference.ps1` walks every YAML and emits markdown.
- `tooling/dev/New-BinaryReport.ps1` regenerates the README hash table from
  `hashes.sha256` so it never drifts.
- `tooling/dev/New-APISurface.ps1` documents every public cmdlet in the Atlas
  module.

---

## 11. Desktop Folder & Toolbox UX

### 11.1 Reorganize AtlasDesktop
Replace the 9 numbered folders with a cleaner hierarchy (the numbers remain as
folder‑name prefixes for muscle‑memory, but add more grouping):

```
AtlasDesktop/
├── 1. Get Started (Install Software, Documentation, Run Health Check)
├── 2. Configuration
│   ├── Profiles (Balanced / Performance / Privacy / Security switcher)
│   ├── General
│   ├── Appearance
│   ├── Power & Sleep
│   ├── AI Features
│   ├── Windows Update
│   └── Network
├── 3. Security
│   ├── Defender
│   ├── Mitigations
│   ├── Core Isolation
│   ├── BitLocker (new)
│   └── Security Baseline (CIS option)
├── 4. Performance
│   ├── Power Plan
│   ├── Timer Resolution
│   ├── Gaming Tweaks
│   ├── HAGS
│   ├── Services
│   └── Startup
├── 5. Privacy
│   ├── Telemetry
│   ├── App Permissions
│   ├── Edge / Browser
│   └── Activity History
├── 6. Maintenance
│   ├── Component Cleanup
│   ├── DISM/SFC Repair
│   ├── System Restore
│   └── Drivers
├── 7. Troubleshooting
│   ├── Diagnostics Export
│   ├── Rollback (category restore)
│   ├── Safe Mode
│   └── Repair Windows
└── 8. Uninstall Atlas (clear warnings about CAB‑removed components)
```

### 11.2 Install Software experience
- Bundle a curated set of installers as **winget IDs with pinned versions +
  hashes** (downloaded via `Get-AtlasVerifiedFile` where feasible; otherwise
  verify Authenticode signature).
- Category browsers (Browsers, Media, Development, Gaming, Utilities) with
  multi‑select checkbox UI using the existing `multichoice.exe`.
- Restore the "install another browser" flow from `playbook.conf`, but route
  through the same verified‑download helper.

### 11.3 Atlas Toolbox (graduate out of BETA)
- Rebuilt in WPF / WinUI3, installed via verified download.
- Shows current *profile*, *health status*, *update status*, *one‑click toggle*
  for common categories.
- Exposes all script functionality via the shared Atlas module (no duplicate
  logic).
- **Also open‑source** (Atlas-OS/atlas-toolbox already exists, bring its
  sources into a submodule with signed releases).

---

## 12. Local Dev Experience

- One‑command setup: `tooling/dev/Setup-DevEnvironment.ps1` installs Pester,
  PSScriptAnalyzer, yamllint, cspell, and configures VS Code.
- VS Code tasks: "Build Playbook (Debug)", "Run Validator", "Run Unit Tests",
  "Run Benchmarks", "Regenerate Hashes/SBOM".
- Dev container (`devcontainer.json`) for non‑Windows contributors (mounts
  repo, runs linter/tests against PS 7; no APBX build but all static checks
  work).
- Pre‑commit hooks via [pre-commit.com] for PS1/YAML/MD formatting.
- `CONTRIBUTING.md` points new contributors at `good first issue` labels and a
  short walkthrough PR.

---

## 13. Rollout Phases (executable roadmap)

Phase work should land in vertical slices — each phase produces a shippable
state.

### Phase 0 — Foundation (complete: v0.6.0) — ✅ Done
- Atlas shared module (logging, registry, hashes, health).
- CI validator, hash manifest, SBOM, dependabot, hardened workflow.
- Diagnostics export, health check, service rollback, RunAtlasScript.cmd.
- Architecture / security / release / contributing docs.
- Changelog, richer issue/PR templates.

### Phase 1 — Repo re‑layout & idempotency engine (v0.7)
- Move directories per §4 (`tooling/dev/Migrate-RepoLayout.ps1`).
- Numbered core phases, new `root.yml`.
- `Set-AtlasState`/`detect:`/`revert:` framework.
- Generate revert skeletons for every tweak; finish reverts for core +
  services + privacy.
- Pester scaffold + module unit tests for all public functions.
- Enforce "every tweak must have a test" in validator; add empty test skeletons.
- All 199 `.cmd` files migrated to `RunAtlasScript.cmd`.

**Exit criterion:** can re‑apply the playbook twice in a row on a clean VM
without errors; validator green on every file; all module functions have
tests.

### Phase 2 — AI, Gaming, Enterprise categories (v0.8)
- Implement `tweaks/ai/` for Recall/ClickToDo/Copilot/AIFabric (all builds
  26100–26200).
- Implement `tweaks/gaming/` with profile guards + benchmark hooks.
- Implement `tweaks/security/enterprise/` L1 baseline (opt‑in only).
- Drop known‑placebo performance tweaks, keep them as explicitly‑labeled
  optional, document why.
- Add uninstall flow (`AtlasDesktop/8. Uninstall Atlas/...`).
- Expand health check to all 16 sub‑tests.

**Exit criterion:** v0.8.0‑RC installs cleanly on 24H2 and 25H2 (amd64 &
ARM64), passes integration sandbox, and the four profiles all produce the
claimed configurations.

### Phase 3 — Profiles, Toolbox UI, i18n (v0.9)
- Implement `profiles/*.yml` and FeaturePage overhaul (profile radio page +
  categorized advanced page).
- Add English string catalog, Toolbox v1 with profile switcher + health UI.
- Wire localization for en‑US + 2 volunteer languages.
- Benchmark harness running on fixed hardware; publish results per RC.
- Convert install‑time browser/toolbox/software installs to
  `Get-AtlasVerifiedFile`.

**Exit criterion:** users can switch profiles post‑install via Toolbox; the
four profiles match their documented behavior; first signed pre‑release.

### Phase 4 — Enterprise, Hardening, Signing (v1.0)
- Signing + SLSA provenance + SBOM on release artifacts.
- CIS L1 baseline finalized with documentation for false positives /
  exceptions.
- Enterprise deployment guide (Autopilot transforms, silent install flags,
  documented Group Policy/MDM interactions).
- Finalize Benchmark publication + per‑tweak "evidence" citations.
- Audit all remaining network calls; zero downloads without pinned hashes.
- Security review by external contributor; open 30‑day community review
  window.

**Exit criterion:** v1.0.0 signed release. Public announcement.

### Post‑v1.0 ideas (v1.x pipeline, no commitment)
- Windows 10 backport (community‑owned).
- Windows 26Hx support as Microsoft ships.
- WDAC policy generation for Atlas installs (optional).
- `atlas-setup` as a standalone WPF setup that can run *without* AME Wizard
  for advanced users (AME remains the primary supported path).
- Auto‑update via signed updater that also runs health checks.
- GUI for custom profile authoring (build your own profile from toggles,
  export a YAML).

---

## 14. Decisions Log (hard calls, documented)

- **Do not ship a custom ISO.** Remains a playbook for AME Wizard; legal
  compliance is non‑negotiable, and AME Wizard already handles the ISO path
  via `<SupportsISO>true</SupportsISO>`.
- **Do not disable paging by default.** Historical cause of micro‑stutter;
  remains an advanced option.
- **Do not blanket‑block telemetry via hosts/FW rules by default.** Breaks
  Defender signatures and WU; gated to Privacy‑Hardened profile.
- **Edge removal is optional, not default.** Too many Windows surfaces assume
  Edge; provide Edge hardening via Chromium policies as the default, removal
  as opt‑in.
- **No updater phoning home automatically.** Health checks and updates are
  manual or user‑initiated.
- **No telemetry, period.** The diagnostics exporter produces a zip; there is
  no opt‑in anonymous data stream.
- **Open Toolbox.** Atlas Toolbox source is developed in the open, in a
  submodule of this org; releases signed and hash‑verified.
- **We cite, we don't claim.** Every default‑on tweak carries a citation (MS
  docs / CIS / STIG / benchmark result). Tweaks without evidence are either
  marked optional or removed.

---

## 15. Definition of Done for v1.0

The release will ship when **all** of the following are true:

- [ ] All four profiles (Balanced, Performance, Privacy, Security) install
      cleanly on 26100 and 26200, amd64 + ARM64, in the Sandbox integration
      test.
- [ ] Every tweak has title, description, citation, `appliesTo`, detect
      script, revert script, and Pester test.
- [ ] Health check passes after install for all four profiles.
- [ ] Hash manifest covers every shipped binary/script; SBOM is published;
      artifacts are signed with SLSA‑3 provenance.
- [ ] CI passes (lint, validate, build, unit tests, integration sandbox) on
      every PR; branch protection enforced.
- [ ] Benchmark harness shows no regression vs. v0.5.0 on the fixed test
      rig for boot time, idle RAM/CPU, DPC latency, and a CS2 frame‑time
      smoke test.
- [ ] Idempotency test: re‑applying the playbook twice produces 0 errors and
      0 drift.
- [ ] Upgrade test: 0.5.0 → 1.0 upgrade succeeds; health check passes.
- [ ] Uninstall flow works and restores services + policies to Windows
      defaults (with clear documentation about CAB‑removed components).
- [ ] Documentation website is updated with per‑tweak reference, profile
      guide, security explainer, enterprise guide, troubleshooting.
- [ ] i18n framework is in place with at least en‑US complete and three
      community translations open for PRs.
- [ ] Open security‑review window of 30 days has passed with no Critical or
      High issues unresolved.

---

*This document is the single source of truth. If code and this roadmap
disagree, update one or the other in the same PR — leaving them in conflict
is not acceptable. Treat the roadmap as code; it lives in the repo, gets PRs,
is reviewed, and ships with every release.*
