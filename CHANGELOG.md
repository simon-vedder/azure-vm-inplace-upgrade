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
- `Start-InPlaceUpgrade` — preflight, incremental OS disk snapshot, media disk from the hidden
  upgrade image, attach, locate `setup.exe`, start Setup through a SYSTEM scheduled task, tags.
- `Complete-InPlaceUpgrade` — evaluates `UpgradeStarted` VMs to Completed / Failed / InProgress,
  fetches the Panther log excerpt on failure, removes the media disk and the scheduled task.
- `Invoke-InPlaceUpgrade` — Start plus polling Complete, for local runs and Hybrid Workers.
- Tags `UpgradeSnapshot` and `UpgradeMediaDisk` point at the artefacts of the current run.
- `src/runbooks/Invoke-InPlaceUpgradeRunbook.ps1`: thin Azure Automation wrapper with Start and
  Check modes, ring filter and a parallelism limit that counts VMs already in progress.
- `deploy/main.bicep`: subscription-scope deployment of Automation Account, identity, custom
  operator role, Log Analytics, pinned module imports, runbook and schedules.
- Image index detection: the media's `install.wim` is listed in the guest and the image matching
  the guest's edition and installation type is passed as `/installfrom` + `/imageindex`.
- Completion rules isolated in a pure function; Task Scheduler status codes (0x4130x) are not
  treated as Setup failures.

### Verified
- 2026-09-05: **Azure Automation path end to end.** `deploy/main.bicep` deployed at subscription
  scope (custom role, assignment on the VM resource group, Automation Account with the module
  imported from a package URI, PowerShell 7.2 runbook, schedules). A `Start` job launched the
  upgrade of a tagged `Ring0` VM in four minutes; scheduled `Check` jobs every 15 minutes moved
  it to `Completed` 43 minutes later. Found and fixed: importing a newer Az.Accounts next to the
  runtime's global Az bundle breaks every job; the deployment imports only this module.
- 2026-09-05: **Windows Server 2022 Datacenter Core → 2025 Core** (23 min, image index 3 picked
  automatically) and **Windows Server 2016 Datacenter → 2025** (42 min, index 4), run in
  parallel on two lab VMs. `targets.json` marks 14393 → 26100 as verified.
- 2026-09-05: **Windows Server 2022 Datacenter → 2025 end to end** on a `2022-datacenter-g2`
  Marketplace VM with `Invoke-InPlaceUpgrade`: 37 minutes from Setup start to build 26100,
  snapshot reused from the previous attempt, media disk deleted, scheduled task removed. Two
  earlier attempts failed with `0xC1900215` (without and with `/pkey`) and produced the
  image-index detection. `targets.json` marks 20348 → 26100 as verified.
- 2026-09-05: `Test-InPlaceUpgradeReadiness` end to end against a fresh Windows Server 2022
  Datacenter (2022-datacenter-g2) VM in westeurope: 19 checks, 65 seconds, media image
  `server2025Upgrade` 26100.33296.260809 found. Found and fixed: single-VM discovery returned a
  scalar (if-statement unrolling) and threw under strict mode.
