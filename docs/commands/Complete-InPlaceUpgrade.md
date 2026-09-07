# Complete-InPlaceUpgrade

> Evaluate a VM in state UpgradeStarted and move it to Completed or Failed

The Check half of the state machine (ADR 0003). Reads the build number, Setup processes and
the scheduled task result from the guest and decides: Completed when the guest reports the
target build, InProgress while Setup runs or the guest is rebooting, Failed when the task
ended with an error, the VM was stopped, or UpgradeStartedAt is older than -TimeoutMinutes.
On a final state the media disk is detached and deleted and the scheduled task removed; the
snapshot is kept as the rollback point. Only VMs in UpgradeStarted are evaluated; every other
state is skipped. Safe to run every few minutes.

## Syntax

```powershell
Complete-InPlaceUpgrade -VM <Object> -Target <string> [-Snapshot <string>] [-MediaDisk <string>] [-Engine <string>] [-StartedAt <datetime>] [-TimeoutMinutes <int>] [-KeepMediaDisk] [-LogIngestionEndpoint <string>] [-DataCollectionRuleId <string>] [-WhatIf] [-Confirm] [<CommonParameters>]

Complete-InPlaceUpgrade -ResourceGroupName <string> -Name <string> -Target <string> [-Snapshot <string>] [-MediaDisk <string>] [-Engine <string>] [-StartedAt <datetime>] [-TimeoutMinutes <int>] [-KeepMediaDisk] [-LogIngestionEndpoint <string>] [-DataCollectionRuleId <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Requirements and notes

Author:              Simon Vedder (simonvedder.com)
Version:             0.1.0
Created:             2026-09-05
LastModified:        2026-09-05
RequiredPermissions: Microsoft.Compute/virtualMachines/read, write, instanceView/read, runCommand/action;
                     Microsoft.Compute/disks/read, delete
Prerequisites:       PowerShell 7.2+, Az.Compute, Az.Resources; an established Azure context

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-VM` | Object | yes | yes |  | The VM object from Get-AzVM. Accepts pipeline input. |
| `-ResourceGroupName` | String | yes | no |  | Resource group of the VM when -Name is used instead of -VM. |
| `-Name` | String | yes | no |  | Name of the VM when -ResourceGroupName is used instead of -VM. |
| `-Target` | String | yes | no |  | What Start left behind. Pass the values, or splat the whole StartResult with -StartResult. |
| `-Snapshot` | String | no | no |  | Name of the OS disk snapshot Start-InPlaceUpgrade took before the upgrade. Carried into the telemetry record and into the result so a rollback target is never guessed. Comes from the StartResult; pass it yourself only when you are completing a run you started by other means. |
| `-MediaDisk` | String | no | no |  | Name of the managed disk holding the upgrade media that Start attached. Used to detach and delete it once the upgrade succeeded, unless -KeepMediaDisk is set. Also from the StartResult. |
| `-Engine` | String | no | no | MediaDisk | Which engine Start used: MediaDisk (Microsoft's upgrade media as a managed disk, the proven path) or FeatureUpdate (Windows Update). It decides how the completion is judged and what cleanup is needed. Defaults to MediaDisk. |
| `-StartedAt` | DateTime | no | no |  | When the upgrade was started, as recorded by Start-InPlaceUpgrade. -TimeoutMinutes is measured from it. Without it the timeout cannot be applied and the command warns and keeps waiting, so pass it for any unattended run. |
| `-TimeoutMinutes` | Int32 | no | no | 240 | How old UpgradeStartedAt may be before a VM that has not reached the target build is declared Failed. |
| `-KeepMediaDisk` | SwitchParameter | no | no |  | Keep the media disk after a final state. Costs money; useful when debugging. |
| `-LogIngestionEndpoint` | String | no | no |  | Logs ingestion endpoint of a data collection endpoint. With -DataCollectionRuleId, every evaluation (InProgress, Completed, Failed) is written to the InPlaceUpgrade_CL table. |
| `-DataCollectionRuleId` | String | no | no |  | Immutable id (dcr-...) of the data collection rule that routes Custom-InPlaceUpgrade_CL. |

Supports `-WhatIf` and `-Confirm`.

## Examples

### Example 1

```powershell
# Evaluate every VM that Start left in UpgradeStarted
Complete-InPlaceUpgrade -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01 -Target WS2025 |
    Select-Object VMName, Result, Reason
```

### Example 2

```powershell
# One VM, keep the media disk for inspection
Complete-InPlaceUpgrade -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01 -KeepMediaDisk
```

## Output

- AzureInPlaceUpgrade.CompleteResult

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
