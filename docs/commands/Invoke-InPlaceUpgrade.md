# Invoke-InPlaceUpgrade

> Start an in-place upgrade and wait for it to finish, in one call

Full mode: Start-InPlaceUpgrade, then Complete-InPlaceUpgrade every -PollIntervalSeconds
until the VM reaches Completed or Failed or -TimeoutMinutes pass. For local runs, Cloud Shell
and Hybrid Runbook Workers. Do not use it in an Azure Automation cloud job: those are cancelled
after three hours (ADR 0003); schedule Start and Complete separately there.

## Syntax

```powershell
Invoke-InPlaceUpgrade -VM <Object> -Target <string> [-Engine <string>] [-MediaDiskResourceGroupName <string>] [-MediaDiskSkuName <string>] [-ProductKey <string>] [-UseMatrixProductKey] [-TargetImageIndex <int>] [-MinimumFreeSpaceGB <int>] [-Force] [-KeepMediaDisk] [-TimeoutMinutes <int>] [-PollIntervalSeconds <int>] [-LogIngestionEndpoint <string>] [-DataCollectionRuleId <string>] [-WhatIf] [-Confirm] [<CommonParameters>]

Invoke-InPlaceUpgrade -ResourceGroupName <string> -Name <string> -Target <string> [-Engine <string>] [-MediaDiskResourceGroupName <string>] [-MediaDiskSkuName <string>] [-ProductKey <string>] [-UseMatrixProductKey] [-TargetImageIndex <int>] [-MinimumFreeSpaceGB <int>] [-Force] [-KeepMediaDisk] [-TimeoutMinutes <int>] [-PollIntervalSeconds <int>] [-LogIngestionEndpoint <string>] [-DataCollectionRuleId <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Requirements and notes

Author:              Simon Vedder (simonvedder.com)
Version:             0.1.0
Created:             2026-09-05
LastModified:        2026-09-05
RequiredPermissions: The union of Start-InPlaceUpgrade and Complete-InPlaceUpgrade
Prerequisites:       PowerShell 7.2+, Az.Compute, Az.Resources; an established Azure context; a session that may run for hours

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-VM` | Object | yes | yes |  | The VM object from Get-AzVM. Accepts pipeline input. |
| `-ResourceGroupName` | String | yes | no |  | Resource group of the VM when -Name is used instead of -VM. |
| `-Name` | String | yes | no |  | Name of the VM when -ResourceGroupName is used instead of -VM. |
| `-Target` | String | yes | no |  | Target key from the matrix, for example WS2025. Defaults to the VM's UpgradeTarget tag. |
| `-Engine` | String | no | no | MediaDisk | MediaDisk (default) or FeatureUpdate (experimental, WS2019/WS2022 only); see Start-InPlaceUpgrade. |
| `-MediaDiskResourceGroupName` | String | no | no |  | Resource group for the media disk. Defaults to the VM's resource group. |
| `-MediaDiskSkuName` | String | no | no | Standard_LRS | Storage SKU of the media disk. |
| `-ProductKey` | String | no | no |  | Explicit public KMS client setup key for setup.exe /pkey. |
| `-UseMatrixProductKey` | SwitchParameter | no | no |  | Pass the matrix's public KMS client setup key for the guest's edition as /pkey. |
| `-TargetImageIndex` | Int32 | no | no | 0 | install.wim image index for setup.exe /installfrom and /imageindex. |
| `-MinimumFreeSpaceGB` | Int32 | no | no | 30 | Free space required on C: by the preflight. |
| `-Force` | SwitchParameter | no | no |  | Proceed although the preflight reports NotEligible, and suppress the confirmation prompt. |
| `-KeepMediaDisk` | SwitchParameter | no | no |  | Keep the media disk after the final state. |
| `-TimeoutMinutes` | Int32 | no | no | 240 | How long to wait for the upgrade before declaring it Failed. |
| `-PollIntervalSeconds` | Int32 | no | no | 120 | Seconds between two guest checks. |
| `-LogIngestionEndpoint` | String | no | no |  | Logs ingestion endpoint for telemetry; see Start-InPlaceUpgrade. |
| `-DataCollectionRuleId` | String | no | no |  | Immutable id of the data collection rule; see Start-InPlaceUpgrade. |

Supports `-WhatIf` and `-Confirm`.

## Examples

### Example 1

```powershell
# End to end on one lab VM, five-hour budget, checking every two minutes
Invoke-InPlaceUpgrade -ResourceGroupName rg-ipu-lab-weu -Name vm-ipu-2022-01 -Target WS2025 -TimeoutMinutes 300 -Confirm:$false -Verbose
```

## Output

- AzureInPlaceUpgrade.StartResult when Start did not start anything, otherwise AzureInPlaceUpgrade.CompleteResult

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
