function Invoke-InPlaceUpgrade {
    <#
    .SYNOPSIS
    Start an in-place upgrade and wait for it to finish, in one call

    .DESCRIPTION
    Full mode: Start-InPlaceUpgrade, then Complete-InPlaceUpgrade every -PollIntervalSeconds
    until the VM reaches Completed or Failed or -TimeoutMinutes pass. For local runs, Cloud Shell
    and Hybrid Runbook Workers. Do not use it in an Azure Automation cloud job: those are cancelled
    after three hours (ADR 0003); schedule Start and Complete separately there.

    .PARAMETER VM
    The VM object from Get-AzVM or Get-InPlaceUpgradeCandidate. Accepts pipeline input.

    .PARAMETER ResourceGroupName
    Resource group of the VM when -Name is used instead of -VM.

    .PARAMETER Name
    Name of the VM when -ResourceGroupName is used instead of -VM.

    .PARAMETER Target
    Target key from the matrix, for example WS2025. Defaults to the VM's UpgradeTarget tag.

    .PARAMETER Engine
    Upgrade engine. Only MediaDisk is implemented.

    .PARAMETER MediaDiskResourceGroupName
    Resource group for the media disk. Defaults to the VM's resource group.

    .PARAMETER MediaDiskSkuName
    Storage SKU of the media disk.

    .PARAMETER ProductKey
    Explicit public KMS client setup key for setup.exe /pkey.

    .PARAMETER UseMatrixProductKey
    Pass the matrix's public KMS client setup key for the guest's edition as /pkey.

    .PARAMETER TargetImageIndex
    install.wim image index for setup.exe /installfrom and /imageindex.

    .PARAMETER MinimumFreeSpaceGB
    Free space required on C: by the preflight.

    .PARAMETER Force
    Proceed although the preflight reports NotEligible, and suppress the confirmation prompt.

    .PARAMETER KeepMediaDisk
    Keep the media disk after the final state.

    .PARAMETER TimeoutMinutes
    How long to wait for the upgrade before declaring it Failed.

    .PARAMETER PollIntervalSeconds
    Seconds between two guest checks.

    .PARAMETER LogIngestionEndpoint
    Logs ingestion endpoint for telemetry; see Start-InPlaceUpgrade.

    .PARAMETER DataCollectionRuleId
    Immutable id of the data collection rule; see Start-InPlaceUpgrade.

    .EXAMPLE
    # End to end on one lab VM, five-hour budget, checking every two minutes
    Invoke-InPlaceUpgrade -ResourceGroupName rg-ipu-lab-weu -Name vm-ipu-2022-01 -TimeoutMinutes 300 -Confirm:$false -Verbose

    .INPUTS
    Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine

    .OUTPUTS
    AzureInPlaceUpgrade.StartResult when Start did not start anything, otherwise AzureInPlaceUpgrade.CompleteResult

    .NOTES
    Author:              Simon Vedder (simonvedder.com)
    Version:             0.1.0
    Created:             2026-09-05
    LastModified:        2026-09-05
    RequiredPermissions: The union of Start-InPlaceUpgrade and Complete-InPlaceUpgrade
    Prerequisites:       PowerShell 7.2+, Az.Compute, Az.Resources; an established Azure context; a session that may run for hours

    .LINK
    https://github.com/simon-vedder/azure-vm-inplace-upgrade
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByObject')]
    [OutputType('AzureInPlaceUpgrade.CompleteResult', 'AzureInPlaceUpgrade.StartResult')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
        $VM,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$ResourceGroupName,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter()]
        [string]$Target,

        [Parameter()]
        [ValidateSet('MediaDisk')]
        [string]$Engine = 'MediaDisk',

        [Parameter()]
        [string]$MediaDiskResourceGroupName,

        [Parameter()]
        [ValidateSet('Standard_LRS', 'StandardSSD_LRS', 'Premium_LRS')]
        [string]$MediaDiskSkuName = 'Standard_LRS',

        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9]{5}(-[A-Za-z0-9]{5}){4}$')]
        [string]$ProductKey,

        [Parameter()]
        [switch]$UseMatrixProductKey,

        [Parameter()]
        [ValidateRange(1, 99)]
        [int]$TargetImageIndex,

        [Parameter()]
        [ValidateRange(10, 200)]
        [int]$MinimumFreeSpaceGB = 30,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$KeepMediaDisk,

        [Parameter()]
        [ValidateRange(30, 1440)]
        [int]$TimeoutMinutes = 240,

        [Parameter()]
        [ValidateRange(30, 900)]
        [int]$PollIntervalSeconds = 120,

        [Parameter()]
        [string]$LogIngestionEndpoint,

        [Parameter()]
        [string]$DataCollectionRuleId
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $Name -ErrorAction Stop
        }
        $vmName = [string]$VM.Name
        $rg = [string]$VM.ResourceGroupName

        if ($Force) { $ConfirmPreference = 'None' }
        if (-not $PSCmdlet.ShouldProcess($vmName, "Upgrade in place and wait up to $TimeoutMinutes minutes")) { return }

        $startParams = @{
            Engine             = $Engine
            MediaDiskSkuName   = $MediaDiskSkuName
            MinimumFreeSpaceGB = $MinimumFreeSpaceGB
            Force              = $Force
            KeepMediaDisk      = $KeepMediaDisk
            UseMatrixProductKey = $UseMatrixProductKey
            Confirm            = $false
        }
        if ($Target) { $startParams['Target'] = $Target }
        if ($MediaDiskResourceGroupName) { $startParams['MediaDiskResourceGroupName'] = $MediaDiskResourceGroupName }
        if ($ProductKey) { $startParams['ProductKey'] = $ProductKey }
        if ($TargetImageIndex) { $startParams['TargetImageIndex'] = $TargetImageIndex }
        if ($LogIngestionEndpoint) { $startParams['LogIngestionEndpoint'] = $LogIngestionEndpoint }
        if ($DataCollectionRuleId) { $startParams['DataCollectionRuleId'] = $DataCollectionRuleId }

        $start = Start-InPlaceUpgrade -VM $VM @startParams
        if ($start.Result -ne 'Started') {
            Write-Verbose "[$vmName] Not started: $($start.Result) - $($start.Reason)"
            return $start
        }
        Write-Verbose "[$vmName] Started at $($start.StartedAt.ToString('u')); polling every $PollIntervalSeconds s for up to $TimeoutMinutes min."

        $deadline = (Get-Date).AddMinutes($TimeoutMinutes).AddSeconds($PollIntervalSeconds)
        $check = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds $PollIntervalSeconds
            $fresh = Get-AzVM -ResourceGroupName $rg -Name $vmName -ErrorAction Stop
            $check = Complete-InPlaceUpgrade -VM $fresh -TimeoutMinutes $TimeoutMinutes -KeepMediaDisk:$KeepMediaDisk -Confirm:$false `
                -LogIngestionEndpoint $LogIngestionEndpoint -DataCollectionRuleId $DataCollectionRuleId
            Write-Verbose ("[{0}] {1:HH:mm:ss} {2}: {3}" -f $vmName, (Get-Date), $check.Result, $check.Reason)
            if ($check.Result -in @('Completed', 'Failed', 'Skipped')) { return $check }
        }
        return $check
    }
}
