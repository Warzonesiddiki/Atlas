# AtlasOS Playbook – Project Analysis & Improvement Suggestions

## 1. Project Overview

**Atlas** (AtlasOS) is a Windows 11 modification (a "playbook" for **AME Wizard**) that applies privacy, performance, usability, and security tweaks to a live Windows install (builds 26100 = 24H2 and 26200 = 25H2 are currently supported). The repository is essentially a large collection of declarative YAML files (AME Wizard actions), Windows batch/PowerShell scripts, a few pre‑built binaries, and CAB packages (produced by the companion [sxsc](https://github.com/Atlas-OS/sxsc) tool) which perform component removal.

### Key repository statistics (snapshot)

| Item | Count |
|---|---|
| Tracked files (non‑git) | ~571 |
| YAML playbook files | 196 |
| PowerShell (`.ps1`/`.psm1`) | 34 + 11 modules |
| Batch (`.cmd`) | **199** |
| Registry (`.reg`) | 19 |
| Bundled binaries / zips / CABs | 9 (~2.5 MB total) |
| CI workflows | 2 (`apbx.yaml` build, `labeler.yaml`) |

### Directory map

```
src/
├── playbook/
│   ├── playbook.conf            # AME Wizard manifest (FeaturePages, metadata…)
│   ├── build-playbook.cmd/sh    # Local build wrappers
│   ├── Configuration/           # YAML "tasks" – the declarative core
│   │   ├── atlas/               # Core phases: start, services, components, appx, default, revert
│   │   ├── tweaks/              # privacy/performance/qol/debloat/networking/security/scripts
│   │   ├── tweaks.yml           # Root orchestrator that includes all tweaks
│   │   └── custom.yml           # Root orchestrator (user/Default hive, file copy, phases)
│   ├── Executables/             # Files copied to %windir% during install
│   │   ├── AtlasDesktop/        # End‑user facing folders (1. Software … 9. Troubleshooting)
│   │   ├── AtlasModules/        # Scripts, tools, modules, packages, wallpapers, toolbox
│   │   ├── Themes/              # .theme files
│   │   ├── Images/              # Browser choice images
│   │   └── *.ps1 / *.cmd        # Top‑level scripts (CLEANUP, DEFAULT, APPLYDUHIVE, etc.)
│   └── playbook.png
├── sxsc/                        # Source YAMLs for the CAB component‑removal packages
├── sxsc-disabled/               # Disabled package definitions
├── dependencies/local-build.ps1 # Local builder (git‑ignored – distributed elsewhere)
└── release-zip/                 # Extra artifacts bundled with releases
```

---

## 2. Strengths of the Current Codebase

Before listing improvements, it's worth noting what is already done well:

1. **Declarative structure** – most tweaks are expressed as short YAML units with `title`, `description`, and `actions`, making them easy to audit.
2. **Transparency** – every tweak is plain text; the bundled binaries are documented with SHA‑256 hashes in `AtlasModules/README.md`.
3. **Separation of concerns** – core Atlas logic lives under `Configuration/atlas/` while user‑togglable items live under `tweaks/`; user‑facing scripts are in `AtlasDesktop/`.
4. **Feature‑page driven UX** – `playbook.conf` exposes granular install‑time choices (Defender, mitigations, updates, hibernation, Edge, browser, …).
5. **ARM64 + amd64 parity** exists for the CAB packages and ViVeTool.
6. **Automation** – GitHub Actions builds the APBX (password‑protected zip) on push and regenerates CABs when `sxsc/*.yaml` changes.
7. **EditorConfig and VS Code settings** enforce consistent line endings, indentation, and YAML custom tags.

That said, there is substantial room for improvement. The remainder of this document is organized by category, with the most impactful items listed first in each section.

---

## 3. Testing, Validation & CI

This is the single largest gap.

1. **No automated tests at all.** The CI only runs `yamllint` (relaxed ruleset) and builds the playbook. There are no Pester tests, no mock registry tests, no static analysis of PowerShell, no JSON/YAML schema validation for playbook steps, and no dry‑run of the scripts on a Windows runner.
2. **No verification that every `.cmd`/`.ps1` referenced by a YAML file actually exists.** A typo in a path (e.g. `AtlasDesktop\3. General Configuration\...`) will only surface at install time on a real machine.
3. **yamllint is running on Ubuntu but the YAML files contain Windows‑style backslashes and CRLF‑indifferent content; rules are disabled so it catches almost nothing.** Consider using a stricter ruleset, or replacing `yamllint` with a purpose‑built validator that understands AME Wizard tags (`!writeStatus`, `!registryValue`, `!appx`, …).
4. **No CI matrix for supported builds.** Although `SupportedBuilds` lists 26100 and 26200, there is no automated run (or even scripted inspection) against those build numbers – component names, service names, and registry keys shift between releases and regressions are easy.
5. **No spell‑check / link‑check.** Documentation URLs (Microsoft docs, STIG viewer, tenforums, elevenforum, winaero, admx.help, …) are embedded as comments and as install‑guide links; many are known to rot (TenForums/Winaero URLs change, Microsoft docs redirect to `learn.microsoft.com`, STIG IDs update). A link‑checker in CI would prevent bit‑rot.
6. **`labeler.yaml` uses `actions/labeler@v4`** which is deprecated – v5 is current and the action syntax changed.
7. **CI uses `tj-actions/changed-files@v46.0.1` pinned only to a major**; a lockfile or SHA pin would be more supply‑chain secure.
8. **The auto‑commit bot** (`atlasos-admin`) pushes directly to the same branch on every sxsc change. If the CAB build ever produces a non‑deterministic or corrupt artifact, there is no PR / review gate.
9. **`pip install -r requirements.txt` is run without hash pinning** (`pip install --require-hashes`) – supply‑chain risk for the sxsc build.
10. **No check for binary hash drift.** The README documents SHA‑256 hashes for `multichoice.exe`, `SetTimerResolution.exe`, ViVeTool zips, etc., but nothing in CI re‑computes them and fails the build if they change.
11. **Missing `dependencies/local-build.ps1` in‑repo.** The file is git‑ignored and pulled from somewhere else; contributors cannot build locally without discovering this. It should either be vendored or the README/build script should fetch it with hash verification.
12. **No CI on pull requests from forks.** The workflow triggers on `push`, meaning external PRs get no validation until a maintainer merges them. Add `pull_request`.
13. **The `workflow_dispatch` inputs default to `main`** but the current working branch is not `main` for most contributors – minor footgun.

---

## 4. Code Quality & Consistency

### 4.1 PowerShell / Batch hygiene

14. **Heavy reliance on `.cmd` files (199) instead of PowerShell.** Many are ~10‑line "bootstrap" files that relaunch themselves elevated and then call a single `.ps1` – that pattern can be centralized into one `RunAsAdmin.cmd` helper (you already have `RunAsTI.cmd`) so that adding a new script does not require copy‑pasting 15 lines of elevation boilerplate.
15. **Duplicate "script not found" / elevation boilerplate** appears in almost every desktop‑folder script:
    ```bat
    set "script=%windir%\AtlasModules\Scripts\ScriptWrappers\X.ps1"
    if not exist "%script%" ( ... pause & exit /b 1 )
    powershell -EP Bypass -NoP ^& """$env:script""" %*
    ```
    Extracting this into a single launcher would shrink the tree by hundreds of lines and eliminate inconsistency.
16. **Mixed quote styles and escaping.** Several scripts use `"""triple‑quote"""`, others `\"`, others `^&`, making them hard to read and easy to break. Standardising on PowerShell for all non‑trivial logic would eliminate this class of bug.
17. **No `Set-StrictMode -Version Latest` or `$ErrorActionPreference = 'Stop'` in most `.ps1` files.** Failures can be silently ignored.
18. **The ubiquitous `> nul` / `2>&1`** in batch scripts suppresses useful diagnostics when something breaks.
19. **Many scripts call `pause > null`** (not `> nul`) when run non‑interactively, leaving a stray `null` file behind (e.g. `Run Update Drivers.cmd`).
20. **`Install Open-Shell.cmd` parses JSON with `for /f tokens^=... delims^=^"` and `curl | find`.** This is extremely brittle (GitHub API changes, redirects, rate limits). Replace with `powershell -NoP -C "Invoke-RestMethod ... | Select-Object -ExpandProperty browser_download_url"` – or better, vendor the skin with a hash.
21. **`installToolbox.ps1` downloads an `.exe` from `github.com/.../releases/latest/download/...` and executes it with `/verysilent /install`** without TLS pinning, signature verification, or hash check. Given the project's emphasis on security/transparency this is an obvious gap.
22. **`packageInstall.ps1`** has a `SafeMode` function that flips `Winlogon\Shell` to itself, which is a powerful, under‑documented recovery path – it needs much more defensive error handling and a failsafe so that a failed run cannot leave the user unable to boot to Explorer.

### 4.2 Duplication

23. **Troubleshooting scripts are duplicated verbatim** between `AtlasDesktop/9. Troubleshooting/` and `AtlasModules/Toolbox/Scripts/Troubleshooting/` (e.g. `Fix Errors 2502 and 2503.cmd`). `diff` shows they are identical.
24. **Other duplicated filenames** (`Enable Microsoft Copilot.cmd`, `Repair Windows Components.cmd`, `Set services to defaults.cmd`, `Telemetry Components.cmd`) between the desktop folder and the toolbox; these should be symlinked or referenced from a single source of truth (at build time or via wrapper scripts).
25. **sxsc YAML files (`Atlas-Defender-Remover.yaml` vs `-Arm.yaml`, `Atlas-NoTelemetry.yaml` vs `-Arm.yaml`) are 95 % identical** – only the `target_arch` fields differ. This should be templated (a generator script, a YAML anchor, or a single config with arch lists) so that adding/removing a component cannot be done on one arch and forgotten on the other.
26. **Registry writes are repeated for both `HKLM\SOFTWARE\...` and `HKLM\SOFTWARE\Wow6432Node\...`** in `atlas/revert.yml` (and elsewhere). A YAML helper or PowerShell function would reduce the duplication and the chance of missing a node.

### 4.3 YAML / Playbook structure

27. **`custom.yml` mixes phases, file copies, cleanup, and hive loading in one ~120‑line file.** It is the entry point and is hard to scan – splitting into `00-prepare.yml`, `10-copy.yml`, `20-apply.yml`, `30-cleanup.yml` (like the numbered desktop folders) would improve readability and ordering.
28. **Inconsistent use of `privilege: TrustedInstaller`, `runas: currentUserElevated`, `exeDir: true`, `onUpgrade:` flags across tweaks**. A documented convention (and a validator) would prevent subtle privilege issues.
29. **`!writeStatus` messages repeat wording** (`Configuring services`, `Configuring drivers`, `Removing components` …). Consider making them hierarchical or adding a progress percentage.
30. **Comments reference Windows versions (e.g. "Seems legacy - not in 23H2" in `appx.yml`) but the playbook no longer targets 23H2.** Out‑of‑date comments should be cleaned up; even better, add a `<SupportedBuilds>` guard per task.
31. **The `disable-llmnr.yml` task is commented out** in `tweaks.yml` with the comment "Needed for compatibility" but no issue link – these "temporarily disabled" tweaks should have a tracking issue or a feature flag rather than a comment.

---

## 5. Security & Supply Chain

32. **Bundled binaries are hashed in the README but there is no in‑repo verification step.** A `scripts/verify-hashes.ps1` (run in CI and on first‑launch) would match hashes against the README at build/run time.
33. **ViVeTool ships as a zip** (v0.3.3) but is extracted/used at runtime with no signature check – ViVeTool is closed‑source in practice and runs as TrustedInstaller. Pin the version, publish the Authenticode thumbprint, or (preferably) move to an open, maintained alternative.
34. **`multichoice.exe`, `SetTimerResolution.exe`, `MeasureSleep.exe`** are third‑party binaries; each is pinned but the hashes were last verified 5/24/2024 and 7/14/2024 – institute a recurring review (e.g. every 6 months) and automate update PRs with `dependabot` for GitHub releases.
35. **No SBOM (Software Bill of Materials).** Generating one (GitHub's built‑in SBOM feature plus a CycloneDX export for the bundled binaries) would help users comply with security audits.
36. **`build-playbook.sh` invokes `pwsh`** with `-ExecutionPolicy Bypass` – necessary, but the script should also validate the SHA‑256 of the downloaded local‑build module rather than implicitly trusting whatever is placed in `src/dependencies/`.
37. **The APBX password `malte` is hard‑coded** in the workflow comments. That's a convention from AME Wizard, but it should be pulled from a documented constant, not duplicated across workflow, README, and local‑build commands.
38. **Code‑owner file lists only two individuals** (`@xyueta @radnotred`) – consider adding a security‑response team or `SECURITY_CONTACTS`; current `SECURITY.md` just says "open a GitHub issue," which is not appropriate for embargoed vulnerabilities (no private disclosure channel, no PGP key).
39. **No `dependabot.yml` / `renovate` config.** GitHub Actions versions, pip requirements, bundled binaries, and PowerShell modules are not automatically updated.
40. **Token usage in apbx.yaml uses `${{ secrets.RUNNER_SECRET }}`** – fine for GitHub's internal token, but there is no `permissions:` block at the workflow/job level, so each job inherits the default broad token. Apply least‑privilege permissions (e.g. `contents: read`, `pull-requests: write` only where needed).
41. **The auto‑commit runs `git add -A`** inside `src/playbook/Executables/AtlasModules/Packages` after CAB generation – any stray file added to that directory will be committed. Scoping with explicit paths is safer.

---

## 6. Reliability & Compatibility

42. **Hard‑coded Windows build assumptions.** Many service names, registry paths, and AppX family names change between builds. There is no runtime guard (e.g. `if ((Get-CimInstance Win32_OperatingSystem).BuildNumber -lt 26100) { ... }`) – if AME Wizard's `SupportedBuilds` check is bypassed, the playbook runs blindly.
43. **Removing Edge via both script and AppX provisioning has caused repeated issues** (the comment "AppX uninstallation in the script seems to fail" says it all). A single source of truth with robust detection of Edge variants (Stable, Beta, Dev, Canary, WebView) is needed.
44. **Network‑dependent steps during install**:
    - `Install Open-Shell.cmd` requires WinGet + GitHub access at *runtime* (post‑install, user‑facing) – failures are tolerated but the user sees a degraded experience.
    - Browser install (Brave/LibreWolf/Firefox/Chrome) similarly fetches from the web.
    - `installToolbox.ps1` downloads the toolbox EXE.
    Offer offline/portable bundles, hash‑pinned downloads with resume, and clear error messages when offline.
45. **`curl.exe` is assumed to exist and be the Microsoft‑built one.** On older builds or stripped images this assumption can fail; fall back to `Invoke-WebRequest`.
46. **`winServices.reg` backup path is overwritten on every run** – keep timestamped backups so users can roll back a bad install.
47. **Many `!registryValue` operations do not have a matching revert** (outside `atlas/revert.yml`, which only handles a few known issues). A systematic "undo" for every tweak would make troubleshooting much easier for users.
48. **The revert file only handles issues back to #1283.** There's no versioned revert chain keyed by `UpgradableFrom` (currently 0.4.1) – upgrades from very old versions will leave stale entries.
49. **Error handling in top‑level scripts uses numeric exit codes (`exit 1`, `exit 2`) that are not documented.** `handleExitCodes` in `custom.yml` treats any non‑zero as `halt`, which is good, but the user is given no actionable message.
50. **`taskkill /f /im explorer.exe` is used in places with no UI restoration guarantee** if a later step fails – wrap with try/finally.

---

## 7. Usability & End‑User Experience

51. **"Atlas Desktop" folder uses numbered prefixes (`1. Software`, `2. Drivers`, …)** which is friendly for humans, but terrible for script paths (spaces, dots, nested quotes). A flat internal alias (e.g. environment variables per folder, or junction points created at install time) would make scripts less fragile.
52. **No logging launcher.** When a user double‑clicks a `.cmd`, all output goes to a transient console window. A "Run and log to desktop" wrapper would make bug reports dramatically better.
53. **The Toolbox is marked BETA** but there is no telemetry/feedback path (and there shouldn't be!) – provide a simple "Export diagnostics" button that zips logs + relevant registry hives.
54. **`Read the Install Guide First!.url`** is placed in the release ZIP but users routinely miss it; consider a pre‑install README shown in the APBX wizard description (the CDATA block currently only points to docs.atlasos.net).
55. **Localisation is zero** – everything is English‑only. The playbook framework supports it; strings should be externalised to `.resx`/`.psd1` so translators can contribute without touching logic.
56. **NTP configuration (`config-time.yml`) hardcodes a server pool** – this is great for most users, but should be overridable (e.g. a `time.atlasos.net` or user‑chosen pool) and should respect enterprise GPOs.
57. **No documentation for advanced users inside the playbook itself** (only external URLs). Short `README.md` files in each tweak folder (like `AtlasModules/README.md`) would let users understand what each toggle does without leaving disk.
58. **Accessibility** – high‑contrast themes, dark/light wallpapers are included, but there are no larger‑cursor / narrator / sticky‑keys defaults; consider documenting that Atlas keeps stock accessibility intact.
59. **Uninstall path is incomplete.** Atlas modifies many system components but there is no "uninstall Atlas" script – the official stance is "reinstall Windows," but a rollback script using the winServices.reg backup + component store restore would go a long way.
60. **Post‑install health check.** After reboot, a scheduled task could verify that critical services are still running, Defender state matches user choice, updates are in the expected state, and surface warnings in the Atlas folder.

---

## 8. Documentation

61. **Root `README.md` is marketing‑heavy but lacks a "Hacking on Atlas" section.** Add: how to build locally (where `local-build.ps1` comes from), how to test in a VM, how to add a new tweak, and how sxsc packages are produced.
62. **`src/README.md`** is only 451 bytes. It should contain an architecture diagram / map of the playbook phases.
63. **Contributing guidelines live off‑repo** (`docs.atlasos.net/contributing/...`). A short `CONTRIBUTING.md` in‑repo (even if it just points to the docs) plus a PR template checklist that actually asks "did you test on build 26100? 26200?" would reduce maintainer load. The current PR template is two checkboxes.
64. **Issue templates ask "I am on the latest version"** but don't collect the Windows build number, edition, Atlas version, or whether the install was ISO‑mode vs. live – add those fields so triage is faster.
65. **`CHANGELOG.md` is missing** – users upgrading from 0.4.1 to 0.5.0 have no single place to see what changed; GitHub releases are the only source.
66. **Binary hash table is manually maintained.** Generate it at build time (a PowerShell script walking `Executables/` and emitting markdown) so it never drifts.
67. **Code comments often reference third‑party tutorials (TenForums, Winaero, ElevenForum).** Prefer `learn.microsoft.com` / official STIG / Microsoft Support URLs; note the Windows build to which a comment applies.

---

## 9. Performance & Size of the Playbook

68. **The playbook copies everything under `Executables/` to `%windir%`** – that includes source PS modules, CABs, wallpapers and browser images. Ship only runtime artifacts; keep build/dev artefacts in a separate folder that isn't copied.
69. **CAB packages are named with hard‑coded version (`5.0.0.0`) and 64 KB of "filler" to defeat component version comparisons** – this is clever but opaque; document the mechanism next to the sxsc files.
70. **`CLEANUP.ps1` runs Disk Cleanup synchronously at install time**, adding minutes. It already says it can run in the background – make that the default.
71. **`NGEN.ps1` (native image compilation) is run for every PowerShell install** – consider running it idle‑post‑install via a scheduled task that deletes itself instead of during the playbook.
72. **ViVeTool is shipped twice** (x64 + ARM64 CLR zip, ~800 KB total) – minor, but the correct architecture could be fetched or selected at build time instead of shipping both.

---

## 10. Maintainability & Longevity

73. **Hard‑coded usernames/emails.** The CI uses `atlasos-admin@users.noreply.github.com` and CODEOWNERS lists two personal accounts – use a `security@atlasos.net` / `maintainers@atlasos.net` alias so turnover doesn't break ownership.
74. **`FUNDING.yml` only lists Ko‑fi.** GitHub Sponsors, OpenCollective, or Patreon links would expand funding options.
75. **No issue/PR templates for documentation vs. playbook vs. sxsc** – the labeler tries to infer this from paths, but templates can pre‑populate the labels and reduce triage.
76. **No `SUPPORT.md`** – new users land in Discord/Discussions; a short file in `.github/` would direct them appropriately.
77. **No formal release process documented in‑repo.** There is no checklist for "cutting a release": updating `playbook.conf` version, bumping `UpgradableFrom`, updating the README hash table, signing binaries, announcing, etc.
78. **Stale `src/sxsc-disabled/Atlas-Misc*.yaml`** – either delete it (git remembers) or add a `DISABLED.md` explaining why and when it can return.
79. **Branching policy is implicit.** There's no `main` vs. `develop` branch description, no backport strategy, and no LTS/canary channel communicated to users.
80. **The `.gitignore` is minimal.** Add common Windows/VS artefacts: `Thumbs.db`, `*.lnk`, `*.suo`, `.vs/`, `*.log`, `*.apbx.tmp` (already there), and local VM output folders.

---

## 11. Suggested Prioritisation (Roadmap)

If I were to tackle the above in order of ROI:

**High impact, lowest effort (quick wins)**

1. Pin GitHub Actions with SHAs and add `permissions:` blocks (#39, #40).
2. Add `pull_request:` trigger to the build workflow so PRs are validated (#12).
3. Fix the `pause > null` typo and other trivial batch issues (#19).
4. Add a YAML/path existence validator script run in CI (#2, #3).
5. Generate the binary‑hash README automatically and verify in CI (#10, #66).
6. Expand PR/issue templates (#63, #64) and add a real `CHANGELOG.md` (#65).
7. Remove duplicate Toolbox/Troubleshooting scripts by symlinking (#23, #24).

**Medium effort, high long‑term value**

8. Introduce a common `Elevated.cmd` launcher to eliminate the 15‑line boilerplate in every desktop script (#15, #16).
9. Add a Pester test suite with a fake registry hive and a dry‑run mode for PowerShell modules (#1).
10. Template the sxsc amd64/arm64 YAMLs (#25).
11. Hash‑pin downloads (Toolbox, Open‑Shell skin, browsers) and add signature checks (#21, #34, #44).
12. Add Dependabot/Renovate and an SBOM workflow (#35, #39).
13. Split `custom.yml` into phase files; document `privilege`/`runas` conventions (#27, #28).

**Longer‑term strategic work**

14. Rewrite/replace batch scripts with PowerShell, enforcing strict mode and `$ErrorActionPreference` (#14, #17).
15. Build an offline/bundled installer option for network‑dependent steps (browser, toolbox, Open‑Shell) (#44).
16. Provide an uninstall/rollback pathway (#59) and a post‑install health check (#60).
17. Introduce localisation framework (#55).
18. Create an architecture document (`src/README.md`) and contributor "how to add a tweak" guide (#61, #62).
19. Define documented release/branching process (#77, #79).

---

## 12. Summary

AtlasOS is a well‑organised, transparent Windows tweaking playbook with a strong declarative core. The biggest weaknesses are not in individual tweaks but in the engineering scaffolding around them: **automated testing is essentially absent, there is script/configuration duplication across architectures and folders, bundled binaries and runtime downloads lack rigorous supply‑chain verification, and contributor/release documentation is thin**. Addressing those will make the project far easier to contribute to, safer for end users, and more resilient against Windows build churn – which is the dominant maintenance burden for this kind of project.
