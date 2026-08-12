# Architecture

This document explains how the Atlas playbook is organised so new contributors
can find their way around quickly.

## Repo layout

```
Atlas/
├── src/
│   ├── playbook/              # The AME Wizard playbook
│   │   ├── playbook.conf      # AME Wizard manifest (XML)
│   │   ├── Configuration/     # Declarative YAML tasks that AME Wizard runs
│   │   │   ├── atlas/         # Core install phases
│   │   │   └── tweaks/        # Category-organised user tweaks
│   │   ├── Executables/       # Files copied to %windir% during install
│   │   │   ├── AtlasDesktop/  # End-user folder (8 numbered categories + URLs)
│   │   │   ├── AtlasModules/  # Scripts, tools, binaries, packages
│   │   │   └── Themes/, Images/
│   │   └── build-playbook.{cmd,sh}
│   ├── sxsc/                  # sxsc configs -> .cab component-removal pkgs
│   ├── sxsc-disabled/         # Disabled package stubs
│   ├── dependencies/          # Build helpers (local-build.ps1 git-ignored)
│   └── release-zip/           # Extra artifacts for GitHub releases
├── scripts/
│   ├── ci/                    # CI-time validators & generators
│   │   ├── Validate-AtlasPlaybook.ps1
│   │   ├── New-AtlasHashManifest.ps1
│   │   └── New-AtlasSBOM.ps1
│   └── dev/                   # Local developer tools (see below)
├── docs/                      # Contributor documentation
└── .github/                   # Templates, CI, policies
```

## Execution order

AME Wizard processes `playbook.conf` (which defines FeaturePages / OOBE / ISO
options), then executes the root playbook file. That root is
`Configuration/custom.yml` and it runs tasks in this order:

1. Load the default user hive (`HKU\AME_UserHive_Default`).
2. Stop folder‑locking processes and remove any previous `AtlasDesktop` /
   `AtlasModules` installation.
3. Copy `Executables\AtlasModules` and `Executables\AtlasDesktop` into `%windir%`.
4. Apply DISABLENOTIFS.cmd to suppress pop-ups during deployment.
5. Run **atlas core**: `start.yml` → `services.yml` → `components.yml` →
   `appx.yml` → `default.yml` → `revert.yml`.
6. Run all **tweaks** via `tweaks.yml` (which includes categories in order).
7. Apply hives to the default user via APPLYDUHIVE.ps1.
8. Clean up registry paths, unload hives, set PowerShell execution policy.

## YAML tasks

Every YAML file under `Configuration/` is an AME Wizard *task*. Each task may
contain actions like `!writeStatus`, `!powerShell`, `!cmd`, `!registryValue`,
`!service`, `!appx`, `!task` (include another YAML), etc. The custom YAML tags
are declared in `.vscode/settings.json` so the RedHat YAML extension can
validate them.

Requirements for new tasks:

- Start with `title:` and `description:` front-matter (the validator enforces
  this).
- Use 2-space indentation and UTF-8 LF per `.editorconfig`.
- Refer to files with backslash paths relative to the playbook root or to
  `exeDir: true` paths relative to the YAML file.

## PowerShell library

Shared code lives under `AtlasModules/Scripts/Lib/Atlas/` and is auto‑added to
`PSModulePath` by `AtlasModules/initPowerShell.ps1`. Import with:

```powershell
Import-Module "$env:windir\AtlasModules\Scripts\Lib\Atlas\Atlas.psd1" -Force
```

The module provides structured logging, safe registry helpers, admin / TI
detection, verified downloads, hash verification, and validation helpers.
Every new script should use it instead of copy‑pasting boilerplate.

## Build pipeline

- Local: `scripts/dev/Build-AtlasPlaybook.ps1` runs `local-build.ps1` then
  regenerates the hash manifest and SBOM.
- CI: `.github/workflows/apbx.yaml` runs on every push/PR:
  1. Static validation (yamllint + Atlas validator + markdown link check).
  2. sxsc CAB build (on changes to `src/sxsc/*.yaml`).
  3. Hash manifest + SBOM regeneration.
  4. APBX build and artifact upload.
