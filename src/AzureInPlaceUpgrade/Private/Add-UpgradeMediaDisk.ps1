function Add-UpgradeMediaDisk {
    <#
    .SYNOPSIS
    Attach the media disk to the VM on the lowest free LUN, unless it is attached already
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]$VM,
        [Parameter(Mandatory)]$Disk
    )

    $attached = @($VM.StorageProfile.DataDisks | Where-Object { $_.ManagedDisk -and $_.ManagedDisk.Id -eq $Disk.Id })
    if ($attached.Count -gt 0) {
        Write-Verbose "[$($VM.Name)] Media disk already attached on LUN $($attached[0].Lun)."
        return [int]$attached[0].Lun
    }

    $usedLuns = @($VM.StorageProfile.DataDisks | ForEach-Object { [int]$_.Lun })
    $lun = 0
    while ($usedLuns -contains $lun) { $lun++ }

    Write-Verbose "[$($VM.Name)] Attaching media disk on LUN $lun."
    $null = Add-AzVMDataDisk -VM $VM -Name $Disk.Name -CreateOption Attach -ManagedDiskId $Disk.Id -Lun $lun -ErrorAction Stop
    $null = Update-AzVM -ResourceGroupName $VM.ResourceGroupName -VM $VM -ErrorAction Stop
    return $lun
}
