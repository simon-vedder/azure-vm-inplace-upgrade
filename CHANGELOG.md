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
