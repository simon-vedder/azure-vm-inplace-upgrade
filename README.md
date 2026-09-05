# azure-vm-inplace-upgrade

![PowerShell](https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?logo=powershell&logoColor=white)
![Azure Automation](https://img.shields.io/badge/Azure-Automation-0078D4?logo=microsoftazure&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Status](https://img.shields.io/badge/status-pre--release-orange)

**Tag-driven, unattended in-place upgrades of Windows Server on Azure VMs.**
Tag a VM, and the tool runs a preflight, snapshots the OS disk, starts Windows Setup detached
from Run Command, tracks the VM through a state machine across Azure Automation jobs, validates
the build inside the guest and cleans up. Windows Server 2012 R2, 2016, 2019 and 2022 to 2025,
using the upgrade media Microsoft ships as a hidden Marketplace image.

> **Status: pre-release.** Preflight, Start and Complete exist; the first end-to-end lab run is
> in progress. Nothing in the target matrix is lab-verified yet, and the README will not claim
> otherwise until it is. See [Roadmap](#roadmap).

## Read this first

Microsoft's own guidance for in-place upgrades in Azure opens with a caution: afterwards, auto guest
patching, hotpatch, automatic OS image upgrade and Azure Update Manager are *not officially
supported*, and the VM's image reference never changes. Their recommendation is to create a new VM.
This project exists for the machines you cannot rebuild. **[docs/when-not-to-use-this.md](docs/when-not-to-use-this.md)**
lists the cases where you should not use it at all, and **[KNOWN-ISSUES.md](KNOWN-ISSUES.md)**
lists every sharp edge found so far, including the `0xC1900215` product-key failure that makes
`/quiet` upgrades fail where the GUI works.

## Why this exists

- Microsoft documents the Azure in-place upgrade as a **manual, per-VM** procedure: create a media
  disk, attach it, RDP in, run `setup.exe`, watch the boot diagnostics screenshot.
- The Windows Server 2025 **feature update over Windows Update** (WS2019/2022, since spring 2026)
  is, per Microsoft's announcement, an administrator clicking *Download and install*.
- Azure Update Manager has no upgrade classification.
- Windows Server 2016 leaves extended support on **12 January 2027**. That population can only go
  to 2025 through the media disk.

Nothing existed that does this unattended, for many VMs, with a snapshot, a state you can see in
the portal and a validation that does not trust ARM metadata. Now something does.

## How it works

```
        UpgradeState tag on the VM
        ───────────────────────────────────────────────────────────────────────▶
        Pending ──▶ SnapshotCreated ──▶ UpgradeStarted ──▶ Completed | Failed

  Start job (minutes)                      Check job (minutes, every 20-30 min)
  ├─ preflight (read-only)                 ├─ read build + task result in the guest
  ├─ OS disk snapshot                      ├─ Completed when build = target
  ├─ media disk from the hidden image      ├─ Failed on task error or timeout
  ├─ attach, find setup.exe                └─ delete the media disk
  ├─ scheduled task as SYSTEM runs setup
  └─ tag UpgradeStarted + UpgradeStartedAt
```

Two things make the unattended path work at all, and both are decisions recorded in
[docs/decisions](docs/decisions):

- **Setup runs from a scheduled task**, not from Run Command. Run Command is capped at 90 minutes
  and dies with the first reboot ([ADR 0001](docs/decisions/0001-scheduled-task-over-run-command.md)).
- **Start and Check are separate jobs**, because Azure Automation cancels cloud jobs after three
  hours ([ADR 0003](docs/decisions/0003-start-and-check-are-separate-jobs.md)).

Validation reads `CurrentBuildNumber` from the guest registry. ARM keeps reporting the original
image forever; the guest does not lie.

## Quick start

```powershell
Import-Module ./src/AzureInPlaceUpgrade      # Install-Module AzureInPlaceUpgrade once it is on the Gallery
Connect-AzAccount
Set-AzContext -Subscription '<subscription name>'

# What can a Windows Server 2016 guest (build 14393) be upgraded to?
Get-InPlaceUpgradeTarget -SourceBuild 14393 | Select-Object Name, DisplayName

# Read-only preflight on one VM. Runs a short Run Command probe in the guest, changes nothing.
$r = Test-InPlaceUpgradeReadiness -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01 -Target WS2025
$r.Decision                                   # Eligible | NotEligible | AlreadyAtTarget
$r.Checks | Format-Table Name, Result, Detail -AutoSize

# Everything that is tagged and approved, one line per VM
Get-InPlaceUpgradeCandidate | Test-InPlaceUpgradeReadiness |
    Select-Object VMName, SourceName, Target, Engine, Decision, Failures, Warnings

# Start: snapshot, media disk, Setup through a scheduled task. Returns in minutes. Prompts first.
Start-InPlaceUpgrade -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01

# Check: run this every 20-30 minutes until every VM is Completed or Failed
Get-InPlaceUpgradeCandidate -State UpgradeStarted | Complete-InPlaceUpgrade | Select-Object VMName, Result, Reason

# Or, outside Azure Automation, both in one call that waits
Invoke-InPlaceUpgrade -ResourceGroupName rg-ipu-lab-weu -Name vm-ipu-2022-01 -TimeoutMinutes 300 -Confirm:$false -Verbose
```

What Start leaves behind on success: the VM in `UpgradeState=UpgradeStarted`, an incremental OS
disk snapshot named in `UpgradeSnapshot`, the media disk named in `UpgradeMediaDisk`, and
`UpgradeStartedAt`. What Complete does on a final state: sets `Completed` or `Failed`, removes
the media disk and the scheduled task, and leaves the snapshot for you to delete once you trust
the result. On a Setup failure the result carries the tail of `setuperr.log` and the compat scan
blocks, so the HRESULT does not stand alone.

If Setup dies with `0xC1900215` ("PidGenX function failed"), rerun with `-UseMatrixProductKey`:
it passes Microsoft's public KMS client setup key for the guest's edition as `/pkey`, which is
the documented way to make unattended Setup pick the right image. See
[KNOWN-ISSUES.md](KNOWN-ISSUES.md).

The preflight checks, cheapest first: power state, OS type, managed and non-ephemeral OS disk,
security type, guest reachability, source build against the matrix, edition, installation type,
architecture, language, free space, pending reboot, domain controller, cluster service, running
Setup, activation channel, and whether the upgrade media image exists in the VM's region.

## Azure Automation

`src/runbooks/Invoke-InPlaceUpgradeRunbook.ps1` is the thin wrapper: sign in with the managed
identity, discover by tag, apply `-Ring` and `-MaxParallel`, call the module per VM. Two
schedules: `-Mode Start` once per maintenance window, `-Mode Check` every 20 to 30 minutes.
`-MaxParallel` counts the VMs already in `UpgradeStarted`, so a Start job never exceeds it. The
Bicep deployment that creates the account, identity, role, module import and schedules is on
the roadmap.

## Tags

| Tag | Values | Meaning |
|---|---|---|
| `UpgradeTarget` | a matrix key: `WS2025`, `WS2022`, `WS2019` | what is wanted |
| `UpgradeState` | `Pending` → `SnapshotCreated` → `UpgradeStarted` → `Completed` \| `Failed` | where the VM is; **setting `Pending` is the approval** |
| `UpgradeRing` | free text, e.g. `Ring0` | optional; the orchestrator can be told to process one ring |
| `UpgradeStartedAt` | UTC timestamp, written by the tool | timeout base for the Check job |
| `UpgradeSnapshot` | snapshot name, written by the tool | the rollback point of the current run |
| `UpgradeMediaDisk` | `<resource group>/<disk name>`, written by the tool | what Complete cleans up |

No approval tag, no history in tags. History goes to Log Analytics
([ADR 0002](docs/decisions/0002-tags-are-state-logs-are-history.md)).

## Target matrix

Shipped as [`targets.json`](src/AzureInPlaceUpgrade/targets.json), versioned with the module.
A tag value that is not a key here never reaches an Azure image.

| Target | Sources (build) | Engines | Verified in this project |
|---|---|---|---|
| `WS2025` | 2012 R2 (9600), 2016 (14393), 2019 (17763), 2022 (20348) | MediaDisk; FeatureUpdate for 2019/2022 (experimental) | not yet |
| `WS2022` | 2016 (14393), 2019 (17763) | MediaDisk | not yet |
| `WS2019` | 2012 R2 (9600), 2016 (14393) | MediaDisk | not yet |

Same edition, same installation type, `64-bit`, `en-US` only. Standard and Datacenter; Server and
Server Core. Windows Server *Azure Edition* is out of scope. The `verified` flag flips only in a
pull request that names the lab run ([CONTRIBUTING.md](CONTRIBUTING.md)).

**Engines.** `MediaDisk` creates a managed disk from Microsoft's hidden
`MicrosoftWindowsServer/WindowsServerUpgrade/server2025Upgrade` image, attaches it and runs
`setup.exe` from it. `FeatureUpdate` would use the Windows Update feature update for WS2019/2022;
it is listed as experimental until a lab spike shows it can be triggered without a human
([ADR 0006](docs/decisions/0006-two-engines-media-disk-first.md)).

## Permissions

The preflight needs these actions on the VM scope. Reader is not enough (Run Command), Virtual
Machine Contributor is far too much.

```
Microsoft.Compute/virtualMachines/read
Microsoft.Compute/virtualMachines/instanceView/read
Microsoft.Compute/virtualMachines/runCommand/action
Microsoft.Compute/locations/publishers/artifacttypes/offers/skus/versions/read
```

Start and Complete need, in addition:

```
Microsoft.Compute/virtualMachines/write            attach and detach the media disk
Microsoft.Compute/disks/read, write, delete        media disk
Microsoft.Compute/snapshots/read, write            rollback point
Microsoft.Resources/tags/write                     state tags
Microsoft.Resources/subscriptions/resourceGroups/read
```

The exact custom role ships with the Bicep deployment.

## Layout

```
src/AzureInPlaceUpgrade/     the module: one function per file, Public/ and Private/
  targets.json               the target matrix
src/runbooks/                thin Azure Automation wrapper (planned)
deploy/                      Bicep: Automation Account, identity, role, module import, schedules,
                             Log Analytics + workbook, lab VMs (planned)
docs/decisions/              ADRs - why it is built the way it is
docs/when-not-to-use-this.md read before tagging production
tests/                       Pester
```

## Roadmap

1. ✅ Module skeleton, target matrix, `Get-InPlaceUpgradeTarget`, `Get-InPlaceUpgradeCandidate`,
   `Test-InPlaceUpgradeReadiness`, Pester for every rule.
2. ✅ Lab: preflight against a 2022 guest (2016 and 2019 pending).
3. ✅ `Start-InPlaceUpgrade` / `Complete-InPlaceUpgrade` / `Invoke-InPlaceUpgrade` with the
   MediaDisk engine. First 2022 → 2025 lab run in progress.
4. Runbook wrapper, `Start` / `Check` modes.
5. FeatureUpdate spike.
6. Bicep: Automation Account, custom role, module import, schedules. Deploy-to-Azure button.
7. Log Analytics table + workbook.
8. Lab: 2016 → 2025, 2019 → 2025, Server Core.
9. PowerShell Gallery release.

## Contributing and security

[CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) · [CHANGELOG.md](CHANGELOG.md)

## License

MIT. The product keys in the target matrix are Microsoft's public KMS client setup keys; they
activate nothing and are listed by Microsoft for exactly this purpose.
