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
    The VM object from Get-AzVM. Accepts
    pipeline input.

    .PARAMETER ResourceGroupName
    Resource group of the VM when -Name is used instead of -VM.

    .PARAMETER Name
    Name of the VM when -ResourceGroupName is used instead of -VM.

    .PARAMETER Snapshot
    Name of the OS disk snapshot Start-InPlaceUpgrade took before the upgrade. Carried into the
    telemetry record and into the result so a rollback target is never guessed. Comes from the
    StartResult; pass it yourself only when you are completing a run you started by other means.

    .PARAMETER MediaDisk
    Name of the managed disk holding the upgrade media that Start attached. Used to detach and
    delete it once the upgrade succeeded, unless -KeepMediaDisk is set. Also from the StartResult.

    .PARAMETER Engine
    Which engine Start used: MediaDisk (Microsoft's upgrade media as a managed disk, the proven
    path) or FeatureUpdate (Windows Update). It decides how the completion is judged and what
    cleanup is needed. Defaults to MediaDisk.

    .PARAMETER StartedAt
    When the upgrade was started, as recorded by Start-InPlaceUpgrade. -TimeoutMinutes is measured
    from it. Without it the timeout cannot be applied and the command warns and keeps waiting, so
    pass it for any unattended run.

    .PARAMETER TimeoutMinutes
    How old UpgradeStartedAt may be before a VM that has not reached the target build is declared
    Failed.

    .PARAMETER KeepMediaDisk
    Keep the media disk after a final state. Costs money; useful when debugging.

    .PARAMETER LogIngestionEndpoint
    Logs ingestion endpoint of a data collection endpoint. With -DataCollectionRuleId, every
    evaluation (InProgress, Completed, Failed) is written to the InPlaceUpgrade_CL table.

    .PARAMETER DataCollectionRuleId
    Immutable id (dcr-...) of the data collection rule that routes Custom-InPlaceUpgrade_CL.

    .EXAMPLE
    # Evaluate every VM that Start left in UpgradeStarted
    Complete-InPlaceUpgrade -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01 -Target WS2025 |
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
                         Microsoft.Compute/disks/read, delete
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

        # What Start left behind. Pass the values, or splat the whole StartResult with -StartResult.
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [Parameter(Mandatory, ParameterSetName = 'ByObject')]
        [string]$Target,

        [Parameter()]
        [string]$Snapshot,

        [Parameter()]
        [string]$MediaDisk,

        [Parameter()]
        [ValidateSet('MediaDisk', 'FeatureUpdate')]
        [string]$Engine = 'MediaDisk',

        [Parameter()]
        [datetime]$StartedAt,

        [Parameter()]
        [ValidateRange(30, 10080)]
        [int]$TimeoutMinutes = 240,

        [Parameter()]
        [switch]$KeepMediaDisk,

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

        $targetName = $Target
        $snapshotName = $Snapshot
        $engineTag = $Engine
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

        $targetObject = Get-InPlaceUpgradeTarget -Name $targetName

        $startedAt = if ($PSBoundParameters.ContainsKey('StartedAt')) { $StartedAt } else { $null }
        if (-not $startedAt) { Write-Warning "[$vmName] No -StartedAt was given; the timeout cannot be applied." }

        $powerState = Get-VMPowerState -ResourceGroupName $rg -VMName $vmName
        if ($powerState -eq 'running') {
            Write-Verbose "[$vmName] Reading upgrade status from the guest."
            $status = Get-GuestUpgradeStatus -ResourceGroupName $rg -VMName $vmName
        }

        $decision = Resolve-UpgradeCompletion -Target $targetObject -PowerState $powerState -Status $status -StartedAt $startedAt -TimeoutMinutes $TimeoutMinutes
        Write-Verbose "[$vmName] $($decision.Result): $($decision.Reason)"

        $mediaRef = $MediaDisk
        $mediaDiskRg = $rg
        $mediaDiskName = Get-UpgradeMediaDiskName -VMName $vmName -Target $targetObject.Name
        if ($mediaRef -and $mediaRef.Contains('/')) {
            $mediaDiskRg = $mediaRef.Substring(0, $mediaRef.IndexOf('/'))
            $mediaDiskName = $mediaRef.Substring($mediaRef.IndexOf('/') + 1)
        }

        switch ($decision.Result) {
            'Completed' {
                if ($PSCmdlet.ShouldProcess($vmName, "Mark upgrade Completed ($($decision.Reason)) and remove the media disk")) {
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
                    if (-not $KeepMediaDisk) {
                        $cleanup = Remove-UpgradeMediaDisk -ResourceGroupName $rg -VMName $vmName -DiskResourceGroupName $mediaDiskRg -DiskName $mediaDiskName
                        $mediaRemoved = $cleanup.Removed
                        if (-not $cleanup.Removed) { Write-Warning "[$vmName] Media disk cleanup failed: $($cleanup.Error)" }
                    }
                }
            }
            default { }
        }

        $recordState = switch ($decision.Result) { 'Completed' { $script:State.Completed } 'Failed' { $script:State.Failed } default { $script:State.UpgradeStarted } }
        $record = ConvertTo-UpgradeRecord -VMName $vmName -ResourceGroupName $rg -State $recordState -Result $decision.Result -Reason $decision.Reason `
            -Target $targetObject.Name -Engine $(if ($engineTag) { $engineTag } elseif ($mediaRef) { 'MediaDisk' } else { 'FeatureUpdate' }) -TargetBuild $targetObject.TargetBuild `
            -SourceBuild $(if ($status) { $status.Build } else { $null }) -DurationMinutes $decision.AgeMinutes `
            -TaskResult $(if ($status -and $null -ne $status.TaskResult) { '0x{0:X8}' -f [uint32]$status.TaskResult } else { '' }) `
            -Snapshot $(if ($snapshotName) { $snapshotName } else { '' }) -MediaDisk $(if ($mediaRef) { $mediaRef } else { '' }) -Mode 'Check' `
            -LogExcerpt $(if ($logExcerpt) { $logExcerpt } else { '' })
        $null = Write-UpgradeRecord -Record $record -LogIngestionEndpoint $LogIngestionEndpoint -DataCollectionRuleId $DataCollectionRuleId

        return ConvertTo-CompleteResult $decision.Result $decision.Reason
    }
}
