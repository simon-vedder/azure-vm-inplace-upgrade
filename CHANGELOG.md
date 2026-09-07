# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [0.3.0-preview] - 2026-09-07

Breaking. The module no longer reads or writes Azure tags. Tags are an orchestration concern and
now live entirely in the runbook, which is the thing that has to survive job boundaries.

### Changed
- `-Target` is mandatory on `Start-InPlaceUpgrade`, `Complete-InPlaceUpgrade`,
  `Invoke-InPlaceUpgrade` and `Test-InPlaceUpgradeReadiness`. It no longer falls back to an
  `UpgradeTarget` tag.
- `Complete-InPlaceUpgrade` takes `-Snapshot`, `-MediaDisk`, `-StartedAt` and `-Engine` instead of
  reading them off the VM. `Start-InPlaceUpgrade` returns all of them, plus a `ResumeCommand` string
  it also prints, so the manual two-step needs no persistence.
- `Start-InPlaceUpgrade` takes `-ReuseSnapshot` instead of finding a previous snapshot in a tag.
- The runbook owns the tag vocabulary: it selects by `UpgradeTarget`, `UpgradeState` and
  `UpgradeRing`, passes the target explicitly, and writes progress back with `Update-AzTag`.
- A second `Start` on a running upgrade is stopped by the existing `SetupRunning` preflight check,
  which observes the guest instead of trusting a tag.

### Fixed
- `Start-InPlaceUpgrade` put a Unix epoch number in the `ResumeCommand` while `-StartedAt` is a
  `[datetime]`. An integer binds as ticks, so a pasted command set the start to year 1 and the next
  Check declared an instant timeout. It now carries a quoted round-trip string.
- The runbook stores `UpgradeStartedAt` as Unix seconds. Azure keeps an ISO string faithfully, but
  `Get-AzVM` returns it re-serialised as `09/07/2026 09:11:41`: no zone, and `MM/dd` that a `dd/MM`
  reader takes for another day. On a lab run that turned 41 minutes of age into 60 days.
  `Get-AzResource` does not do this; `Get-AzVM` does.

### Removed
- `Get-InPlaceUpgradeCandidate`. Tag-based discovery is orchestration; the runbook does it with
  `Get-AzVM` and a tag filter.

## [0.2.0-preview] - 2026-09-05

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
- Tags `UpgradeSnapshot` and `UpgradeMediaDisk` point at the artefacts of the current run;
  `UpgradeEngine` records which engine Start used.
- `src/runbooks/Invoke-InPlaceUpgradeRunbook.ps1`: thin Azure Automation wrapper with Start and
  Check modes, ring filter and a parallelism limit that counts VMs already in progress.
- `deploy/main.bicep`: subscription-scope deployment of Automation Account, identity, custom
  operator role, Log Analytics, module import, runbook and schedules.
- Telemetry: `InPlaceUpgrade_CL` custom table, data collection endpoint and rule, workbook
  *In-place upgrades*; one record per state transition from Start and Complete.
- Release workflow: tag `v*` runs analyzer and tests, publishes to the PowerShell Gallery and
  attaches the module zip and runbook to the GitHub release.
- Image index detection: the media's `install.wim` is listed in the guest and the image matching
  the guest's edition and installation type is passed as `/installfrom` + `/imageindex`.
- Completion rules isolated in a pure function; Task Scheduler status codes (0x4130x) are not
  treated as Setup failures.

### Verified
- 2026-09-05: **FeatureUpdate engine end to end**: `Start -Engine FeatureUpdate` on a 2022
  Marketplace VM, finished by the scheduled Check jobs 186 minutes later with build 26100.33296
  and nine telemetry records. Slower than the media disk by a factor of three to five.
- 2026-09-05: **Windows Server 2025 feature update installed unattended** on a 2022 Marketplace
  VM through the Windows Update Agent (policy opt-in, `DeploymentAction='OptionalInstallation'`
  search, download, install, `Commit(0)`, orchestrator restart): build 26100.33296 after about
  two hours. Basis of the experimental `FeatureUpdate` engine.
- 2026-09-05: **Windows Server 2019 Datacenter → 2025 through the Automation runbook with
  telemetry**: Start job, three scheduled Check jobs, Completed after 43 minutes; six records in
  `InPlaceUpgrade_CL` from NotEligible (pending reboot on the fresh VM) to Completed.
  `targets.json` marks 17763 → 26100 as verified.
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
