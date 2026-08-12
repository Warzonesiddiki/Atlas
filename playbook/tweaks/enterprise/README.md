# Enterprise Hardening

This directory contains **opt‑in** tweaks aligned with the Microsoft Security
Baseline for Windows 11 24H2/25H2 and the CIS Microsoft Windows 11 Enterprise
Benchmark v3.

> ⚠️ These tweaks are NOT part of the Balanced / Performance / Privacy
> profiles. They are only applied when the user selects the **Security-Focused**
> profile or explicitly opts in post‑install. Applying them to consumer
> machines may break legacy software, printing, consumer gaming anti‑cheats,
> or VPN clients.

## Files

- `asr-rules.yml` – Defender Attack Surface Reduction rules (low‑false‑positive set).
- `lsa-protection.yml` – RunAsPPL for LSASS.
- `bitlocker-wizard.yml` – One‑click BitLocker enable (detects TPM, resumes state).
- `sysmon-install.yml` – Downloads Sysmon with Olaf Hartong modular config via `Get-AtlasVerifiedFile`.
- `wdac-policy.yml` – Generates a basic WDAC policy in audit mode (opt‑in).
- `cis-l1-curated.yml` – Curated CIS L1 subset that works with consumer apps.
- `no-lmhash.yml` – Disables LM hashes storage.
- `disable-smb1.yml` – Disables SMB 1.0 (mapped into networking.hardened by reference).

## Source references

- Microsoft Security Compliance Toolkit (SCT) for Windows 11 24H2
  https://www.microsoft.com/en-us/download/details.aspx?id=105724
- CIS Microsoft Windows 11 Enterprise Benchmark v3.0.0
  https://www.cisecurity.org/benchmark/microsoft_windows_desktop
- Olaf Hartong Sysmon modular config:
  https://github.com/olafhartong/sysmon-modular
