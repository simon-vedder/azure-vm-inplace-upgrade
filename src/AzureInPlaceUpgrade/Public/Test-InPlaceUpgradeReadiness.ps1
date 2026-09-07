function Test-InPlaceUpgradeReadiness {
    <#
    .SYNOPSIS
    Run the read-only preflight for an in-place upgrade of one Azure VM

    .DESCRIPTION
    Collects control-plane facts from ARM (power state, OS disk type, security type), in-guest
    facts through a short Run Command probe (build, edition, installation type, language, free
    space, pending reboot, domain role, cluster service, activation channel) and the availability
    of the hidden upgrade media image in the VM's region, then applies every readiness rule and
    returns one object with a Decision (Eligible, NotEligible, AlreadyAtTarget) and the full list
    of checks. Nothing is created, attached, tagged or started. Running it on a production VM is
    safe; the Run Command probe takes about a minute.

    .PARAMETER VM
    The VM object from Get-AzVM. Accepts pipeline input.

    .PARAMETER ResourceGroupName
    Resource group of the VM when -Name is used instead of -VM.

    .PARAMETER Name
    Name of the VM when -ResourceGroupName is used instead of -VM.

    .PARAMETER Target
    The target key from the matrix, for example WS2025. Defaults to the VM's UpgradeTarget tag;
    one of the two must be present.

    .PARAMETER MinimumFreeSpaceGB
    Free space required on C: before an upgrade would be started.

    .PARAMETER SkipMediaCheck
    Do not look up the upgrade media image in the VM's region. Saves one call when only the guest
    is of interest; the engine check then reports a warning instead of a pass.

    .EXAMPLE
    # Preflight one VM and show the checks
    $r = Test-InPlaceUpgradeReadiness -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01 -Target WS2025
    $r.Decision
    $r.Checks | Format-Table Name, Result, Detail -AutoSize

    .EXAMPLE
    # Preflight everything that is approved, summarised
    Get-AzVM -ResourceGroupName rg-apps-prod-weu | Test-InPlaceUpgradeReadiness -Target WS2025 |
        Select-Object VMName, SourceName, Target, Engine, Decision, Failures, Warnings

    .EXAMPLE
    # Only the failed checks across a resource group
    Get-AzVM -ResourceGroupName rg-apps-prod-weu | Test-InPlaceUpgradeReadiness -Target WS2025 |
        ForEach-Object { $vm = $_.VMName; $_.Checks | Where-Object Result -eq 'Fail' | Select-Object @{ n = 'VM'; e = { $vm } }, Name, Detail }

    .INPUTS
    Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine

    .OUTPUTS
    AzureInPlaceUpgrade.Readiness

    .NOTES
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

    .LINK
    https://github.com/simon-vedder/azure-vm-inplace-upgrade
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByObject')]
    [OutputType('AzureInPlaceUpgrade.Readiness')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
        $VM,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$ResourceGroupName,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter()]
        [ValidateRange(10, 200)]
        [int]$MinimumFreeSpaceGB = 30,

        [Parameter()]
        [switch]$SkipMediaCheck
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $Name -ErrorAction Stop
        }

        $targetObject = Get-InPlaceUpgradeTarget -Name $Target

        Write-Verbose "[$($VM.Name)] Reading power state."
        $powerState = Get-VMPowerState -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name
        $armFacts = Get-VMArmFacts -VM $VM -PowerState $powerState

        $guestFacts = $null
        $guestError = $null
        if ($powerState -eq 'running') {
            Write-Verbose "[$($VM.Name)] Probing the guest through Run Command."
            $probe = Get-GuestFacts -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name
            $guestFacts = $probe.Facts
            $guestError = $probe.Error
        }

        $media = $null
        $mediaEngine = Get-PropertyOrDefault -InputObject $targetObject.Engines -Name 'MediaDisk'
        if (-not $SkipMediaCheck -and $mediaEngine) {
            Write-Verbose "[$($VM.Name)] Looking up upgrade media $($mediaEngine.sku) in $($armFacts.Location)."
            $media = Get-MediaImageVersion -Location $armFacts.Location -Publisher $mediaEngine.publisher -Offer $mediaEngine.offer -Sku $mediaEngine.sku
        }

        Resolve-InPlaceUpgradeReadiness -Target $targetObject -ArmFacts $armFacts -GuestFacts $guestFacts `
            -GuestError $guestError -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Media $media
    }
}
