# Research Notes & Evidence Base

This file captures the sources and findings that shaped `ROADMAP.md` and
`BLUEPRINT.md`. When we cite "research shows …" in a commit message or tweak
comment, we are pointing here.

## Sources consulted

### OS / AI feature churn (24H2 / 25H2)
- WindowsLatest, *"How I disabled 13 AI features in Windows 11 safely"* (Feb 2026).
  Documents: Recall removal (`DISM /Disable-Feature /FeatureName:Recall`),
  `AllowRecallEnablement`, `DisableAIDataAnalysis`, Click to Do policy,
  Copilot GPOs, Image Creator/Cocreator/Generative Fill policies.
- winslop.io *"How to debloat Windows 10 & 11"* — registry for AI policies.
- gHacks / windowsnews.ai, *"NTLite 2026 Adds Pre-Install Removal of Copilot and
  Recall in Windows 11 25H2"* (May 2026).
- GizmodoTech, *"Disable AI Telemetry Windows 11 (2026 Guide)"* — Windows AI
  Fabric Service note, Copilot legacy vs April 2026 GPO.

Implication: AI components are now split across Group Policy, AppX, Services,
and Optional Features; we must cover all four layers.

### Competitive tools
- Win11Debloat (Raphire): https://github.com/Raphire/Win11Debloat – custom-mode
  interactive selection is the UX to beat; we have AME Wizard but need clearer
  per‑toggle explanations.
- Chris Titus WinUtil: https://github.com/ChrisTitusTech/winutil – strength is
  winget software installs; we can match via the install‑software menu with
  verified downloads. Weakness: `irm|iex` by default; Atlas will not do this.
- NTLite: pre‑install image editing — out of scope for Atlas (we stay a
  playbook, not an ISO rebuiler).
- Sophia Script/SophiApp: https://github.com/Sophia-Community – strong
  documentation style; mirror this for per‑tweak docs.
- O&O ShutUp10++: per‑toggle explanations are gold‑standard; our per‑tweak
  reference docs need to match this quality.
- privacy.sexy: code‑gen approach; useful as a reference for tweak corpus,
  not a product model for us.
- meetrevision/playbook: another AME‑Wizard playbook; similar structure,
  smaller scope.

### Security baselines
- CIS Microsoft Windows 11 Enterprise Benchmark v3 (L1 ≈ 280 settings, L2 ≈ 365).
- Microsoft Security Baseline for Windows 11 24H2 (via SCT).
- DISA STIGs (Win10 v1r5 applies; Win11 STIG delayed — build on top of CIS).
- cybersecurityelite.com 2026 hardening checklist — LAPS, Credential Guard,
  Sysmon (Olaf Hartong modular config), ASR rules.
- decryptiondigest.com — pilot‑OU deployment guidance for baselines.

Implication: ship CIS L1 as an *opt‑in* profile; never force enterprise GPOs
on consumer installs; document every exception.

### Gaming / latency
- ultimatemove.eu Windows gaming optimization (2026).
- noobs2pro.com input-lag tweaks.
- SageTweaks 2026 input-lag guide (HAGS 2–5 ms, VBS 5–15%, Ultimate Performance
  3–8 ms, polling rate).
- mr-nika/Latency-Arc-Windows-Tweaks — high‑res timer, DPC, core parking
  parameters (note: some claims here are over‑stated; treat as hypothesis
  only and benchmark).
- WindowsLatest/Reddit discussions of performance regressions after Atlas
  0.5.0 (issue #1406) — paging‑file disable and blanket bcdedit flags are
  suspects.

Implication: ship gaming tweaks, but only those we can measure; disable
paging-file and global bcdedit from default; provide profile guards for
laptops.

### Engineering best practices
- Buildkite *"Monorepo CI best practices"* (2023): selective builds,
  trunk‑based development, dependency bots.
- Aviator *"Monorepo: Hands-On Guide"* (2026): code ownership, dependency
  management, backward compatibility.
- devblogs.microsoft.com ISE *"Monorepo Independent Release Cycles"*:
  release-please / changesets per package.
- Medium, *"Ultimate Guide to Monorepo 2026"*.

Implication: restructure repo to modular phases with selective CI; use
changeset-style release automation; enforce CODEOWNERS.

### Atlas-specific bugs (github.com/Atlas-OS/Atlas)
- #1509 – 25H2 install fails (msvcp140.dll race in AME extraction).
- #1522 – errors during installation logs (non‑fatal).
- #1353 – Microsoft Store broken on OEM images post‑install.
- #1406 – performance regression vs 0.4.0 (micro‑stutter).
- #1273 – cannot re‑apply the playbook.

Implication: idempotency, better logging, OEM‑ACL detection, benchmark harness.

## Research methodology notes
- Web searches performed 2026‑08‑12.
- Claims from third‑party tweak sites (tenforums, winaero, youtube guides)
  are treated as **hypotheses**, not facts. Each such tweak must be validated
  by the benchmark harness in `tooling/benchmarks/` before shipping as a
  default.
- Primary sources (Microsoft docs, CIS Benchmark PDFs, STIGs) are preferred
  and cited directly in tweak YAML comments.
- Gamer/YouTuber "optimization" scripts are not taken at face value — many
  include placebo or outright harmful settings (e.g., disabling Superfetch,
  forcing `bcdedit /set useplatformtick no` on all hardware).

## Open research questions (follow‑ups)
1. What is the measured DPC impact of Timer Resolution 0.5ms on modern Intel
   13+/AMD Ryzen 7000+ platforms with modern APIC timers?
2. Which ASR rules in the 24H2/25H2 Defender baseline still cause false
   positives in consumer software?
3. What minimal set of scheduled tasks can be safely disabled on 25H2 without
   breaking Windows Update or Store updates?
4. Is it viable to ship an experimental `atlas-setup.exe` that doesn't
   require AME Wizard, while keeping AME as the primary supported path?
5. How does Recall's disk/index footprint compare to Windows Search indexing?
   (Quantify benefit of disabling on non‑Copilot+ PCs.)

Each of these should have a dedicated research ticket (label `research`)
before being turned into a tweak.
