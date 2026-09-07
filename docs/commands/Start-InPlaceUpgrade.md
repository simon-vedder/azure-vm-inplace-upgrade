# Start-InPlaceUpgrade

> Snapshot one Azure VM, attach the upgrade media and start Windows Setup unattended

The Start half of the state machine (ADR 0003). Runs the preflight, creates an incremental
snapshot of the OS disk as the rollback point, builds a managed disk from Microsoft's hidden
upgrade image, attaches it, locates setup.exe inside the guest and starts it through a
scheduled task running as SYSTEM (ADR 0001). Returns within minutes; the upgrade itself takes
30 to 120 minutes and several reboots and is finished by Complete-InPlaceUpgrade.

Start does not wait. Use it when something else has to survive the gap - an Azure Automation
job is cancelled after three hours, so the runbook starts in one job and checks in later ones.
At a console, where nothing cancels you, Invoke-InPlaceUpgrade does Start, the waiting and
Complete in a single call.

Writes nothing to the VM's metadata. Everything Complete-InPlaceUpgrade needs comes back in
the result object - Snapshot, Engine, MediaDisk, StartedAt and a ready-to-run ResumeCommand -
so the caller decides where that state lives. The runbook keeps it in tags; a script may keep
it in a variable. On failure the media disk is removed unless -KeepMediaDisk is set, and the
snapshot always stays.

Idempotent, and it asks the guest rather than a tag: a VM already on the target build is
skipped, a Setup that is already running is not started again, an existing media disk is
reused, an attached disk is not attached twice, and a snapshot from an earlier attempt is
reused when the caller passes -ReuseSnapshot. The install.wim image is always passed
explicitly (/installfrom, /imageindex), detected from the media's WIM metadata, because
unattended Setup cannot choose between the Core and Desktop Experience images itself.

This changes the VM. ConfirmImpact is High, so it prompts unless -Confirm:$false or -Force is
given; -WhatIf runs the preflight and stops before the snapshot.

## Syntax

```powershell
Start-InPlaceUpgrade -VM <Object> -Target <string> [-ReuseSnapshot <string>] [-Engine <string>] [-MediaDiskResourceGroupName <string>] [-MediaDiskSkuName <string>] [-ProductKey <string>] [-UseMatrixProductKey] [-TargetImageIndex <int>] [-MinimumFreeSpaceGB <int>] [-Force] [-KeepMediaDisk] [-LogIngestionEndpoint <string>] [-DataCollectionRuleId <string>] [-WhatIf] [-Confirm] [<CommonParameters>]

Start-InPlaceUpgrade -ResourceGroupName <string> -Name <string> -Target <string> [-ReuseSnapshot <string>] [-Engine <string>] [-MediaDiskResourceGroupName <string>] [-MediaDiskSkuName <string>] [-ProductKey <string>] [-UseMatrixProductKey] [-TargetImageIndex <int>] [-MinimumFreeSpaceGB <int>] [-Force] [-KeepMediaDisk] [-LogIngestionEndpoint <string>] [-DataCollectionRuleId <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Requirements and notes

Author:              Simon Vedder (simonvedder.com)
Version:             0.1.0
Created:             2026-09-05
LastModified:        2026-09-05
RequiredPermissions: Microsoft.Compute/virtualMachines/read, write, instanceView/read, runCommand/action;
                     Microsoft.Compute/disks/read, write, delete; Microsoft.Compute/snapshots/read, write;
                     Microsoft.Compute/locations/publishers/artifacttypes/offers/skus/versions/read;
                     Microsoft.Resources/subscriptions/resourceGroups/read
                     (the Bicep deployment ships a custom role with these actions plus
                     Microsoft.Resources/tags/write, which the runbook - not this function - needs)
Prerequisites:       PowerShell 7.2+, Az.Compute, Az.Resources; a healthy Azure Guest Agent in the VM; an established Azure context

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-VM` | Object | yes | yes |  | The VM object from Get-AzVM. Accepts pipeline input. |
| `-ResourceGroupName` | String | yes | no |  | Resource group of the VM when -Name is used instead of -VM. |
| `-Name` | String | yes | no |  | Name of the VM when -ResourceGroupName is used instead of -VM. |
| `-Target` | String | yes | no |  | Required. Target key from the matrix, for example WS2025; Get-InPlaceUpgradeTarget lists them. The module never reads it from a tag - the caller states the target. |
| `-ReuseSnapshot` | String | no | no |  | Name of a snapshot from a previous attempt. Start used to find this in a tag; the caller passes it now, so the module never reads resource metadata. |
| `-Engine` | String | no | no | MediaDisk | MediaDisk (default): Microsoft's upgrade media as a managed disk, no network needed, every documented source version. FeatureUpdate (experimental): the Windows Server 2025 feature update through the Windows Update Agent, WS2019/WS2022 only, needs Windows Update reachability; no media disk is created (ADR 0006). |
| `-MediaDiskResourceGroupName` | String | no | no |  | Resource group for the media disk. Defaults to the VM's resource group. |
| `-MediaDiskSkuName` | String | no | no | Standard_LRS | Storage SKU of the media disk. Standard_LRS is plenty; Setup reads it once. |
| `-ProductKey` | String | no | no |  | Explicit key for setup.exe /pkey. Use a public KMS client setup key (GVLK) only; the value ends up in the scheduled task definition, visible to every local administrator. |
| `-UseMatrixProductKey` | SwitchParameter | no | no |  | Pass the matrix's public KMS client setup key for the guest's edition as /pkey. Rarely needed: the 0xC1900215 failure is caused by image selection, not by the key (see KNOWN-ISSUES), and is solved by the explicit image index below. Kept for guests whose own key does not validate. |
| `-TargetImageIndex` | Int32 | no | no | 0 | Override the install.wim image index for setup.exe /installfrom and /imageindex. By default the index is detected from the WIM metadata by matching the guest's edition and installation type; an override is refused when the index does not exist on the media. |
| `-MinimumFreeSpaceGB` | Int32 | no | no | 30 | Free space required on C: by the preflight. |
| `-Force` | SwitchParameter | no | no |  | Proceed although the preflight reports NotEligible, and suppress the confirmation prompt. AlreadyAtTarget is never overridden. |
| `-KeepMediaDisk` | SwitchParameter | no | no |  | Keep the media disk when Start fails. Useful when debugging a Setup that dies immediately. |
| `-LogIngestionEndpoint` | String | no | no |  | Logs ingestion endpoint of a data collection endpoint (https://...ingest.monitor.azure.com). Together with -DataCollectionRuleId, every state transition is written to the InPlaceUpgrade_CL table. Empty means no telemetry. |
| `-DataCollectionRuleId` | String | no | no |  | Immutable id (dcr-...) of the data collection rule that routes Custom-InPlaceUpgrade_CL. |

Supports `-WhatIf` and `-Confirm`.

## Examples

### Example 1

```powershell
# Upgrade one VM by name (prompts before the snapshot). No tags needed.
Start-InPlaceUpgrade -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01 -Target WS2025
```

### Example 2

```powershell
# A fleet: the caller selects the VMs however it likes and passes the target per machine
Get-AzVM -ResourceGroupName rg-apps-prod-weu | Where-Object { $_.Tags.UpgradeState -eq 'Pending' } |
    ForEach-Object { Start-InPlaceUpgrade -VM $_ -Target $_.Tags.UpgradeTarget -UseMatrixProductKey -Confirm:$false }
```

### Example 3

```powershell
# Preflight and plan only
Start-InPlaceUpgrade -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01 -Target WS2025 -WhatIf
```

## Output

- AzureInPlaceUpgrade.StartResult

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
