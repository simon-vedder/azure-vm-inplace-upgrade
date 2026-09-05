function New-VMOSSnapshot {
    <#
    .SYNOPSIS
    Create an incremental snapshot of the VM's OS disk as the rollback point

    .DESCRIPTION
    Incremental snapshots bill only the used blocks and can be turned into a full managed disk
    for an OS disk swap, which is all a rollback needs. The snapshot is tagged with the source VM
    and target so it can be found and cleaned up later; it is never deleted by this module.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; the public caller gates with ShouldProcess before invoking it.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$VM,
        [Parameter(Mandatory)][string]$Target
    )

    $name = '{0}-pre{1}-{2}' -f $VM.Name, $Target.ToLowerInvariant(), (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
    $osDiskId = $VM.StorageProfile.OsDisk.ManagedDisk.Id

    $config = New-AzSnapshotConfig -SourceUri $osDiskId -Location $VM.Location -CreateOption Copy -Incremental `
        -Tag @{ UpgradeSourceVM = $VM.Name; UpgradeTarget = $Target } -ErrorAction Stop

    return New-AzSnapshot -ResourceGroupName $VM.ResourceGroupName -SnapshotName $name -Snapshot $config -ErrorAction Stop
}
