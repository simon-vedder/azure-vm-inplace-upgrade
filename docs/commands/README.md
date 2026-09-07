# AzureInPlaceUpgrade command reference

Unattended in-place Windows Server upgrades for Azure VMs, one by name or a tagged fleet from a runbook: preflight, OS disk snapshot, detached Windows Setup, state tracking across Azure Automation jobs and in-guest validation.

## Requirements

| | |
|---|---|
| Module version | 0.3.1-preview |
| PowerShell | 7.2+ (Core) |
| Required modules | `Az.Accounts` 2.15.0+, `Az.Compute` 7.1.1+, `Az.Resources` 6.13.0+ |
| Install | `Install-Module AzureInPlaceUpgrade -AllowPrerelease` |

Per-command permissions are on each page under **Requirements and notes**.

## Commands

| Command | What it does |
|---|---|
| [Complete-InPlaceUpgrade](Complete-InPlaceUpgrade.md) | Check a VM whose upgrade was started and report Completed, InProgress or Failed |
| [Get-InPlaceUpgradeTarget](Get-InPlaceUpgradeTarget.md) | Resolve an upgrade target and its supported source versions from the target matrix |
| [Invoke-InPlaceUpgrade](Invoke-InPlaceUpgrade.md) | Start an in-place upgrade and wait for it to finish, in one call |
| [Start-InPlaceUpgrade](Start-InPlaceUpgrade.md) | Snapshot one Azure VM, attach the upgrade media and start Windows Setup unattended |
| [Test-InPlaceUpgradeReadiness](Test-InPlaceUpgradeReadiness.md) | Run the read-only preflight for an in-place upgrade of one Azure VM |

---

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not these files.*
