<#
.SYNOPSIS
Orchestrate tag-driven in-place upgrades of Azure VMs from an Azure Automation runbook

.DESCRIPTION
Thin wrapper around the AzureInPlaceUpgrade module (ADR 0004): signs in with the Automation
Account's managed identity, discovers VMs by tag, applies the ring and parallelism limits and
calls the module once per VM. Two modes, scheduled separately because cloud jobs are cancelled
after three hours (ADR 0003):

  Start  picks VMs in UpgradeState=Pending and starts as many as fit under -MaxParallel, counting
         the ones already in UpgradeStarted. Schedule once per maintenance window.
  Check  evaluates every VM in UpgradeState=UpgradeStarted and moves it to Completed or Failed.
         Schedule every 20 to 30 minutes.

All optional flags are [bool] instead of [switch] because the Automation "Start runbook" dialog
cannot populate switch parameters. -DryRun maps to -WhatIf on the module: the preflight runs, no
snapshot, disk, Setup or tag is touched. Requires the AzureInPlaceUpgrade module and Az.Accounts,
Az.Compute, Az.Resources in the Automation Account's PowerShell 7.2+ runtime environment.

.PARAMETER SubscriptionId
The subscription to operate on. One per job.

.PARAMETER Mode
Start or Check.

.PARAMETER ResourceGroupName
Restrict discovery to one resource group.

.PARAMETER Target
Only process VMs whose UpgradeTarget tag equals this value.

.PARAMETER Ring
Only process VMs whose UpgradeRing tag equals this value.

.PARAMETER MaxParallel
Upper bound of VMs in UpgradeStarted at the same time. Start mode starts only enough VMs to reach
it; Check mode ignores it.

.PARAMETER TimeoutMinutes
Check mode: how old UpgradeStartedAt may be before a VM that has not reached the target build is
declared Failed.

.PARAMETER Engine
Start mode: MediaDisk (default) or FeatureUpdate (experimental, Windows Update based, WS2019/2022 only).

.PARAMETER UseMatrixProductKey
Start mode: pass the matrix's public KMS client setup key as setup.exe /pkey (fix for 0xC1900215).

.PARAMETER DryRun
Preflight only, change nothing.

.PARAMETER ManagedIdentityClientId
Client ID of a user-assigned managed identity. Leave empty for the system-assigned identity.

.PARAMETER LogIngestionEndpoint
Logs ingestion endpoint of the data collection endpoint. Empty falls back to the Automation
variable InPlaceUpgrade-LogIngestionEndpoint that main.bicep maintains; no variable disables telemetry.

.PARAMETER DataCollectionRuleId
Immutable id of the data collection rule deployed with main.bicep.

.EXAMPLE
# Schedule 1, once per maintenance window: start up to three Ring0 upgrades
.\Invoke-InPlaceUpgradeRunbook.ps1 -SubscriptionId '<subscription id>' -Mode Start -Ring Ring0 -MaxParallel 3

.EXAMPLE
# Schedule 2, every 20 minutes: finish what is running
.\Invoke-InPlaceUpgradeRunbook.ps1 -SubscriptionId '<subscription id>' -Mode Check

.INPUTS
None

.OUTPUTS
AzureInPlaceUpgrade.StartResult or AzureInPlaceUpgrade.CompleteResult, one per VM, plus a summary string

.NOTES
Author:              Simon Vedder (simonvedder.com)
Version:             0.1.0
Created:             2026-09-05
LastModified:        2026-09-05
RequiredPermissions: Managed identity with the custom role from deploy/main.bicep on the target scope:
                     Microsoft.Compute/virtualMachines/read, write, instanceView/read, runCommand/action;
                     Microsoft.Compute/disks/read, write, delete; Microsoft.Compute/snapshots/read, write;
                     Microsoft.Compute/locations/publishers/artifacttypes/offers/skus/versions/read;
                     Microsoft.Resources/tags/write; Microsoft.Resources/subscriptions/resourceGroups/read
Prerequisites:       Azure Automation PowerShell 7.2+ runtime; modules AzureInPlaceUpgrade, Az.Accounts, Az.Compute, Az.Resources

.LINK
https://github.com/simon-vedder/azure-vm-inplace-upgrade
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,

    [Parameter()]
    [ValidateSet('Start', 'Check')]
    [string]$Mode = 'Check',

    [Parameter()]
    [string]$ResourceGroupName,

    [Parameter()]
    [string]$Target,

    [Parameter()]
    [string]$Ring,

    [Parameter()]
    [ValidateRange(1, 50)]
    [int]$MaxParallel = 3,

    [Parameter()]
    [ValidateRange(30, 1440)]
    [int]$TimeoutMinutes = 240,

    [Parameter()]
    [ValidateSet('MediaDisk', 'FeatureUpdate')]
    [string]$Engine = 'MediaDisk',

    [Parameter()]
    [bool]$UseMatrixProductKey = $false,

    [Parameter()]
    [bool]$DryRun = $false,

    [Parameter()]
    [string]$ManagedIdentityClientId,

    [Parameter()]
    [string]$LogIngestionEndpoint,

    [Parameter()]
    [string]$DataCollectionRuleId
)

$ErrorActionPreference = 'Stop'

Import-Module Az.Accounts -ErrorAction Stop
Import-Module AzureInPlaceUpgrade -ErrorAction Stop

# Telemetry target: explicit parameters win, otherwise the Automation variables deploy/main.bicep
# maintains. Get-AutomationVariable only exists inside the sandbox; local runs pass parameters.
if (-not $LogIngestionEndpoint -and (Get-Command Get-AutomationVariable -ErrorAction SilentlyContinue)) {
    $LogIngestionEndpoint = [string](Get-AutomationVariable -Name 'InPlaceUpgrade-LogIngestionEndpoint' -ErrorAction SilentlyContinue)
    $DataCollectionRuleId = [string](Get-AutomationVariable -Name 'InPlaceUpgrade-DataCollectionRuleId' -ErrorAction SilentlyContinue)
}

$connect = @{ Identity = $true; ErrorAction = 'Stop' }
if ($ManagedIdentityClientId) { $connect['AccountId'] = $ManagedIdentityClientId.Trim() }
$null = Connect-AzAccount @connect
$context = Set-AzContext -SubscriptionId $SubscriptionId.Trim() -ErrorAction Stop
Write-Output "Subscription: $($context.Subscription.Name) | Mode: $Mode | Scope: $(if ($ResourceGroupName) { $ResourceGroupName } else { 'subscription' }) | Target: $(if ($Target) { $Target } else { 'any' }) | Ring: $(if ($Ring) { $Ring } else { 'any' }) | DryRun: $DryRun | Telemetry: $(if ($LogIngestionEndpoint -and $DataCollectionRuleId) { 'on' } else { 'off' })"

$scope = @{}
if ($ResourceGroupName) { $scope['ResourceGroupName'] = $ResourceGroupName.Trim() }
if ($Target) { $scope['Target'] = $Target.Trim() }
if ($Ring) { $scope['Ring'] = $Ring.Trim() }

$summary = @{}
function Add-Summary { param([string]$Key) if ($summary.ContainsKey($Key)) { $summary[$Key]++ } else { $summary[$Key] = 1 } }

if ($Mode -eq 'Start') {
    $running = @(Get-InPlaceUpgradeCandidate @scope -State 'UpgradeStarted')
    $slots = $MaxParallel - $running.Count
    Write-Output "In progress: $($running.Count) | MaxParallel: $MaxParallel | Slots: $([math]::Max($slots, 0))"

    if ($slots -le 0) {
        Write-Output 'Nothing started: the parallelism limit is reached. Run Check to free slots.'
    }
    else {
        $pending = @(Get-InPlaceUpgradeCandidate @scope -State 'Pending' | Sort-Object Name | Select-Object -First $slots)
        Write-Output "Pending and selected: $(if ($pending.Count) { ($pending.Name -join ', ') } else { 'none' })"
        foreach ($vm in $pending) {
            $result = Start-InPlaceUpgrade -VM $vm -Engine $Engine -UseMatrixProductKey:$UseMatrixProductKey -Confirm:$false -WhatIf:$DryRun `
                -LogIngestionEndpoint $LogIngestionEndpoint -DataCollectionRuleId $DataCollectionRuleId
            Write-Output "[$($vm.Name)] $($result.Result): $($result.Reason)"
            Add-Summary $result.Result
            $result
        }
    }
}
else {
    $started = @(Get-InPlaceUpgradeCandidate @scope -State 'UpgradeStarted')
    Write-Output "Evaluating: $(if ($started.Count) { ($started.Name -join ', ') } else { 'none' })"
    foreach ($vm in $started) {
        $result = Complete-InPlaceUpgrade -VM $vm -TimeoutMinutes $TimeoutMinutes -Confirm:$false -WhatIf:$DryRun `
            -LogIngestionEndpoint $LogIngestionEndpoint -DataCollectionRuleId $DataCollectionRuleId
        Write-Output "[$($vm.Name)] $($result.Result): $($result.Reason)"
        if ($result.LogExcerpt) { Write-Output $result.LogExcerpt }
        Add-Summary $result.Result
        $result
    }
}

Write-Output ("Summary: " + $(if ($summary.Count) { ($summary.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ' } else { 'nothing to do' }))
