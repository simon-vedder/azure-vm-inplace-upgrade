# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Added
- Module skeleton `AzureInPlaceUpgrade` (PowerShell 7.2+).
- Versioned target matrix (`targets.json`): WS2025 from 2012 R2 / 2016 / 2019 / 2022, WS2022 from
  2016 / 2019, WS2019 from 2012 R2 / 2016. Every path carries `verified: false` until it has run in
  the project lab.
- `Get-InPlaceUpgradeTarget` — resolve a target and its allowed sources from the matrix.
- `Get-InPlaceUpgradeCandidate` — discover VMs by `UpgradeTarget` / `UpgradeState` / `UpgradeRing` tags.
- `Test-InPlaceUpgradeReadiness` — read-only preflight: ARM facts, in-guest facts via Run Command,
  media image availability, structured pass/warn/fail checks and an eligibility decision.
- Pester tests for the matrix, target resolution, tag filtering, guest output parsing and every
  readiness rule.
- `deploy/lab.bicep`: one tagged source VM without public IP for lab verification.

### Verified
- 2026-09-05: `Test-InPlaceUpgradeReadiness` end to end against a fresh Windows Server 2022
  Datacenter (2022-datacenter-g2) VM in westeurope: 19 checks, 65 seconds, media image
  `server2025Upgrade` 26100.33296.260809 found. Found and fixed: single-VM discovery returned a
  scalar (if-statement unrolling) and threw under strict mode.
