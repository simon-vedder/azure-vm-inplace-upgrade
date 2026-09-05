function Remove-UpgradeMediaDisk {
    <#
    .SYNOPSIS
    Detach and delete the media disk once the VM reached a final state

    .DESCRIPTION
    The disk is billed while it exists. Failures are reported through the return value and never
    change the upgrade result of the VM.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; the public caller gates with ShouldProcess before invoking it.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$DiskResourceGroupName,
        [Parameter(Mandatory)][string]$DiskName
    )

    try {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
        $attached = @($vm.StorageProfile.DataDisks | Where-Object { $_.Name -eq $DiskName })
        if ($attached.Count -gt 0) {
            Write-Verbose "[$VMName] Detaching media disk '$DiskName'."
            $null = Remove-AzVMDataDisk -VM $vm -Name $DiskName -ErrorAction Stop
            $null = Update-AzVM -ResourceGroupName $ResourceGroupName -VM $vm -ErrorAction Stop
        }

        $disk = Get-AzDisk -ResourceGroupName $DiskResourceGroupName -DiskName $DiskName -ErrorAction SilentlyContinue
        if ($disk) {
            $null = Remove-AzDisk -ResourceGroupName $DiskResourceGroupName -DiskName $DiskName -Force -ErrorAction Stop
            Write-Verbose "[$VMName] Media disk '$DiskName' deleted."
        }
        return [pscustomobject]@{ Removed = $true; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Removed = $false; Error = $_.Exception.Message }
    }
}
