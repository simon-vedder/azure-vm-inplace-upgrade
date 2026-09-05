function Complete-InPlaceUpgrade {
    <#
    .SYNOPSIS
    Evaluate a VM in state UpgradeStarted and move it to Completed or Failed

    .DESCRIPTION
    The Check half of the state machine (ADR 0003). Reads the build number, Setup processes and
    the scheduled task result from the guest and decides: Completed when the guest reports the
    target build, InProgress while Setup runs or the guest is rebooting, Failed when the task
    ended with an error, the VM was stopped, or UpgradeStartedAt is older than -TimeoutMinutes.
    On a final state the media disk is detached and deleted and the scheduled task removed; the
    snapshot is kept as the rollback point. Only VMs in UpgradeStarted are evaluated; every other
    state is skipped. Safe to run every few minutes.

    .PARAMETER VM
    The VM object from Get-AzVM or Get-InPlaceUpgradeCandidate -State UpgradeStarted. Accepts
    pipeline input.

    .PARAMETER ResourceGroupName
    Resource group of the VM when -Name is used instead of -VM.

    .PARAMETER Name
    Name of the VM when -ResourceGroupName is used instead of -VM.

    .PARAMETER TimeoutMinutes
    How old UpgradeStartedAt may be before a VM that has not reached the target build is declared
    Failed.

    .PARAMETER KeepMediaDisk
    Keep the media disk after a final state. Costs money; useful when debugging.

    .EXAMPLE
    # Evaluate every VM that Start left in UpgradeStarted
    Get-InPlaceUpgradeCandidate -State UpgradeStarted | Complete-InPlaceUpgrade |
        Select-Object VMName, Result, Reason

    .EXAMPLE
    # One VM, keep the media disk for inspection
    Complete-InPlaceUpgrade -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01 -KeepMediaDisk

    .INPUTS
    Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine

    .OUTPUTS
    AzureInPlaceUpgrade.CompleteResult

    .NOTES
    Author:              Simon Vedder (simonvedder.com)
    Version:             0.1.0
    Created:             2026-09-05
    LastModified:        2026-09-05
    RequiredPermissions: Microsoft.Compute/virtualMachines/read, write, instanceView/read, runCommand/action;
                         Microsoft.Compute/disks/read, delete; Microsoft.Resources/tags/write
    Prerequisites:       PowerShell 7.2+, Az.Compute, Az.Resources; an established Azure context

    .LINK
    https://github.com/simon-vedder/azure-vm-inplace-upgrade
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByObject')]
    [OutputType('AzureInPlaceUpgrade.CompleteResult')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
        $VM,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$ResourceGroupName,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter()]
        [ValidateRange(30, 10080)]
        [int]$TimeoutMinutes = 240,

        [Parameter()]
        [switch]$KeepMediaDisk
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $Name -ErrorAction Stop
        }
        $vmName = [string]$VM.Name
        $rg = [string]$VM.ResourceGroupName

        $state = Get-VMTagValue -VM $VM -Name $script:Tag.State
        $targetName = Get-VMTagValue -VM $VM -Name $script:Tag.Target
        $snapshotName = Get-VMTagValue -VM $VM -Name $script:Tag.Snapshot
        $status = $null
        $decision = $null
        $logExcerpt = $null
        $mediaRemoved = $null

        function ConvertTo-CompleteResult {
            param([string]$Result, [string]$Reason)
            [pscustomobject]@{
                PSTypeName        = 'AzureInPlaceUpgrade.CompleteResult'
                VMName            = $vmName
                ResourceGroupName = $rg
                Target            = $targetName
                Result            = $Result
                Reason            = $Reason
                Build             = if ($status) { $status.Build } else { $null }
                ProductName       = if ($status) { $status.ProductName } else { $null }
                TaskState         = if ($status) { $status.TaskState } else { $null }
                TaskResult        = if ($status -and $null -ne $status.TaskResult) { '0x{0:X8}' -f [uint32]$status.TaskResult } else { $null }
                AgeMinutes        = if ($decision) { $decision.AgeMinutes } else { $null }
                Snapshot          = $snapshotName
                MediaDiskRemoved  = $mediaRemoved
                LogExcerpt        = $logExcerpt
            }
        }

        if ($state -ine $script:State.UpgradeStarted) {
            $shown = if ($state) { $state } else { '<none>' }
            return ConvertTo-CompleteResult 'Skipped' "VM is in state '$shown'; only $($script:State.UpgradeStarted) is evaluated."
        }
        if (-not $targetName) { throw "VM '$vmName' is in $($script:State.UpgradeStarted) but has no '$($script:Tag.Target)' tag." }
        $targetObject = Get-InPlaceUpgradeTarget -Name $targetName

        $startedAt = $null
        $startedAtRaw = Get-VMTagValue -VM $VM -Name $script:Tag.StartedAt
        if ($startedAtRaw) {
            $startedAt = ConvertFrom-TagTimestamp -Value $startedAtRaw
            if ($null -eq $startedAt) { Write-Warning "[$vmName] $($script:Tag.StartedAt)='$startedAtRaw' is not a timestamp; the timeout cannot be applied." }
        }

        $powerState = Get-VMPowerState -ResourceGroupName $rg -VMName $vmName
        if ($powerState -eq 'running') {
            Write-Verbose "[$vmName] Reading upgrade status from the guest."
            $status = Get-GuestUpgradeStatus -ResourceGroupName $rg -VMName $vmName
        }

        $decision = Resolve-UpgradeCompletion -Target $targetObject -PowerState $powerState -Status $status -StartedAt $startedAt -TimeoutMinutes $TimeoutMinutes
        Write-Verbose "[$vmName] $($decision.Result): $($decision.Reason)"

        $tagState = $script:Tag.State
        $tagStartedAt = $script:Tag.StartedAt

        $mediaRef = Get-VMTagValue -VM $VM -Name $script:Tag.MediaDisk
        $mediaDiskRg = $rg
        $mediaDiskName = Get-UpgradeMediaDiskName -VMName $vmName -Target $targetObject.Name
        if ($mediaRef -and $mediaRef.Contains('/')) {
            $mediaDiskRg = $mediaRef.Substring(0, $mediaRef.IndexOf('/'))
            $mediaDiskName = $mediaRef.Substring($mediaRef.IndexOf('/') + 1)
        }

        switch ($decision.Result) {
            'Completed' {
                if ($PSCmdlet.ShouldProcess($vmName, "Mark upgrade Completed ($($decision.Reason)) and remove the media disk")) {
                    Set-UpgradeTag -ResourceId $VM.Id -Tag @{ $tagState = $script:State.Completed }
                    if (-not (Remove-GuestUpgradeTask -ResourceGroupName $rg -VMName $vmName)) { Write-Verbose "[$vmName] Scheduled task could not be removed; harmless." }
                    if (-not $KeepMediaDisk) {
                        $cleanup = Remove-UpgradeMediaDisk -ResourceGroupName $rg -VMName $vmName -DiskResourceGroupName $mediaDiskRg -DiskName $mediaDiskName
                        $mediaRemoved = $cleanup.Removed
                        if (-not $cleanup.Removed) { Write-Warning "[$vmName] Media disk cleanup failed: $($cleanup.Error)" }
                    }
                }
            }
            'Failed' {
                if ($decision.TaskFailed -and $status) {
                    Write-Verbose "[$vmName] Fetching the Setup log excerpt."
                    $logExcerpt = Get-GuestSetupLogTail -ResourceGroupName $rg -VMName $vmName
                }
                if ($PSCmdlet.ShouldProcess($vmName, "Mark upgrade Failed ($($decision.Reason)) and remove the media disk")) {
                    Set-UpgradeTag -ResourceId $VM.Id -Tag @{ $tagState = $script:State.Failed }
                    if (-not $KeepMediaDisk) {
                        $cleanup = Remove-UpgradeMediaDisk -ResourceGroupName $rg -VMName $vmName -DiskResourceGroupName $mediaDiskRg -DiskName $mediaDiskName
                        $mediaRemoved = $cleanup.Removed
                        if (-not $cleanup.Removed) { Write-Warning "[$vmName] Media disk cleanup failed: $($cleanup.Error)" }
                    }
                }
            }
            default {
                # Without a timestamp the age can never be judged; stamp it now so the next run can.
                if (-not $startedAtRaw -and $PSCmdlet.ShouldProcess($vmName, "Stamp $tagStartedAt")) {
                    Set-UpgradeTag -ResourceId $VM.Id -Tag @{ $tagStartedAt = (ConvertTo-TagTimestamp -Value (Get-Date)) }
                }
            }
        }

        return ConvertTo-CompleteResult $decision.Result $decision.Reason
    }
}
