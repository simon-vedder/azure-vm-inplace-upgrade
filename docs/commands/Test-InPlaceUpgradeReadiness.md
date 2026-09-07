# Test-InPlaceUpgradeReadiness

> Run the read-only preflight for an in-place upgrade of one Azure VM

Collects control-plane facts from ARM (power state, OS disk type, security type), in-guest
facts through a short Run Command probe (build, edition, installation type, language, free
space, pending reboot, domain role, cluster service, activation channel) and the availability
of the hidden upgrade media image in the VM's region, then applies every readiness rule and
returns one object with a Decision (Eligible, NotEligible, AlreadyAtTarget) and the full list
of checks. Nothing is created, attached, tagged or started. Running it on a production VM is
safe; the Run Command probe takes about a minute.

## Syntax

```powershell
Test-InPlaceUpgradeReadiness -VM <Object> -Target <string> [-MinimumFreeSpaceGB <int>] [-SkipMediaCheck] [<CommonParameters>]

Test-InPlaceUpgradeReadiness -ResourceGroupName <string> -Name <string> -Target <string> [-MinimumFreeSpaceGB <int>] [-SkipMediaCheck] [<CommonParameters>]
```

## Requirements and notes

Author:              Simon Vedder (simonvedder.com)
Version:             0.1.0
Created:             2026-09-04
LastModified:        2026-09-04
RequiredPermissions: Microsoft.Compute/virtualMachines/read,
                     Microsoft.Compute/virtualMachines/instanceView/read,
                     Microsoft.Compute/virtualMachines/runCommand/action,
                     Microsoft.Compute/locations/publishers/artifacttypes/offers/skus/versions/read
                     (Reader is not enough because of runCommand/action; Virtual Machine Contributor is far more than needed - use a custom role with these four actions)
Prerequisites:       PowerShell 7.2+, Az.Compute; a healthy Azure Guest Agent in the VM; an established Azure context

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-VM` | Object | yes | yes |  | The VM object from Get-AzVM. Accepts pipeline input. |
| `-ResourceGroupName` | String | yes | no |  | Resource group of the VM when -Name is used instead of -VM. |
| `-Name` | String | yes | no |  | Name of the VM when -ResourceGroupName is used instead of -VM. |
| `-Target` | String | yes | no |  | The target key from the matrix, for example WS2025. Defaults to the VM's UpgradeTarget tag; one of the two must be present. |
| `-MinimumFreeSpaceGB` | Int32 | no | no | 30 | Free space required on C: before an upgrade would be started. |
| `-SkipMediaCheck` | SwitchParameter | no | no |  | Do not look up the upgrade media image in the VM's region. Saves one call when only the guest is of interest; the engine check then reports a warning instead of a pass. |

## Examples

### Example 1

```powershell
# Preflight one VM and show the checks
$r = Test-InPlaceUpgradeReadiness -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01 -Target WS2025
$r.Decision
$r.Checks | Format-Table Name, Result, Detail -AutoSize
```

### Example 2

```powershell
# Preflight everything that is approved, summarised
Get-AzVM -ResourceGroupName rg-apps-prod-weu | Test-InPlaceUpgradeReadiness -Target WS2025 |
    Select-Object VMName, SourceName, Target, Engine, Decision, Failures, Warnings
```

### Example 3

```powershell
# Only the failed checks across a resource group
Get-AzVM -ResourceGroupName rg-apps-prod-weu | Test-InPlaceUpgradeReadiness -Target WS2025 |
    ForEach-Object { $vm = $_.VMName; $_.Checks | Where-Object Result -eq 'Fail' | Select-Object @{ n = 'VM'; e = { $vm } }, Name, Detail }
```

## Output

- AzureInPlaceUpgrade.Readiness

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
