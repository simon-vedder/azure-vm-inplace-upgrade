function Get-InPlaceUpgradeCandidate {
    <#
    .SYNOPSIS
    Discover Azure VMs that are tagged for an in-place upgrade

    .DESCRIPTION
    Lists the VMs in the current Azure context (optionally narrowed to a resource group or a single
    VM) and returns those whose tags select them: an UpgradeTarget tag is required, and the
    UpgradeState, UpgradeTarget and UpgradeRing filters must match when given. The default state
    filter is Pending, which is the state a human sets to approve an upgrade; the orchestrator
    passes UpgradeStarted for its Check mode. Tag comparison is case-insensitive and ignores
    surrounding whitespace. Read-only.

    .PARAMETER ResourceGroupName
    Restrict discovery to one resource group.

    .PARAMETER Name
    Restrict discovery to one VM. Requires -ResourceGroupName. The fast way to pilot on a single
    machine.

    .PARAMETER Target
    Only return VMs whose UpgradeTarget tag equals this value.

    .PARAMETER State
    Only return VMs whose UpgradeState tag equals this value. Pass an empty string to accept any
    state.

    .PARAMETER Ring
    Only return VMs whose UpgradeRing tag equals this value.

    .PARAMETER IgnoreTags
    Return the VM regardless of its tags. Only allowed together with -Name, so that a typo can
    never select a whole subscription.

    .EXAMPLE
    # Everything approved for an upgrade in the current subscription
    Get-InPlaceUpgradeCandidate | Select-Object Name, ResourceGroupName, @{ n = 'Target'; e = { $_.Tags['UpgradeTarget'] } }

    .EXAMPLE
    # Ring0 VMs in one resource group, then run the preflight on each
    Get-InPlaceUpgradeCandidate -ResourceGroupName rg-apps-prod-weu -Ring Ring0 | Test-InPlaceUpgradeReadiness

    .EXAMPLE
    # One untagged pilot VM
    Get-InPlaceUpgradeCandidate -ResourceGroupName rg-ipu-lab-weu -Name vm-ipu-2022-01 -IgnoreTags

    .INPUTS
    None

    .OUTPUTS
    Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine

    .NOTES
    Author:              Simon Vedder (simonvedder.com)
    Version:             0.1.0
    Created:             2026-09-04
    LastModified:        2026-09-04
    RequiredPermissions: Microsoft.Compute/virtualMachines/read on the scope (the built-in Reader role covers it)
    Prerequisites:       PowerShell 7.2+, Az.Compute; an established Azure context (Connect-AzAccount)

    .LINK
    https://github.com/simon-vedder/azure-vm-inplace-upgrade
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine')]
    param(
        [Parameter()]
        [string]$ResourceGroupName,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Target,

        [Parameter()]
        [AllowEmptyString()]
        [string]$State = 'Pending',

        [Parameter()]
        [string]$Ring,

        [Parameter()]
        [switch]$IgnoreTags
    )

    if ($IgnoreTags -and -not $Name) {
        throw '-IgnoreTags is only allowed together with -Name, so that it can never select every VM in scope.'
    }
    if ($Name -and -not $ResourceGroupName) {
        throw '-Name requires -ResourceGroupName.'
    }

    # The outer @() is not decoration: output of an if statement is enumerated on assignment, so
    # a single VM would arrive as a scalar and '.Count' below would throw under strict mode.
    $vms = @(
        if ($Name) {
            Get-AzVM -ResourceGroupName $ResourceGroupName -Name $Name -ErrorAction Stop
        }
        elseif ($ResourceGroupName) {
            Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        }
        else {
            Get-AzVM -ErrorAction Stop
        }
    )
    Write-Verbose "Discovered $($vms.Count) VM(s) in scope."

    foreach ($vm in $vms) {
        if ($IgnoreTags) {
            Write-Verbose "[$($vm.Name)] Tag filter bypassed (-IgnoreTags)."
            $vm
            continue
        }
        if (Test-CandidateTag -VM $vm -Target $Target -State $State -Ring $Ring) {
            Write-Verbose "[$($vm.Name)] Matches the upgrade tag selector."
            $vm
        }
    }
}
