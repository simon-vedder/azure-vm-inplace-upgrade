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

    # Update-AzVM PUTs the whole object, tags included. A VM object fetched before the tag writes
    # earlier in Start would silently revert them (observed live), so read a fresh copy first.
    $fresh = Get-AzVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -ErrorAction Stop

    $attached = @($fresh.StorageProfile.DataDisks | Where-Object { $_.ManagedDisk -and $_.ManagedDisk.Id -eq $Disk.Id })
    if ($attached.Count -gt 0) {
        Write-Verbose "[$($fresh.Name)] Media disk already attached on LUN $($attached[0].Lun)."
        return [int]$attached[0].Lun
    }

    $usedLuns = @($fresh.StorageProfile.DataDisks | ForEach-Object { [int]$_.Lun })
    $lun = 0
    while ($usedLuns -contains $lun) { $lun++ }

    Write-Verbose "[$($fresh.Name)] Attaching media disk on LUN $lun."
    $null = Add-AzVMDataDisk -VM $fresh -Name $Disk.Name -CreateOption Attach -ManagedDiskId $Disk.Id -Lun $lun -ErrorAction Stop
    $null = Update-AzVM -ResourceGroupName $fresh.ResourceGroupName -VM $fresh -ErrorAction Stop
    return $lun
}
