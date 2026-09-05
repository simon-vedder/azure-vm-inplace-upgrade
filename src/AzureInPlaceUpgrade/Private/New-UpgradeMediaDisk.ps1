function New-UpgradeMediaDisk {
    <#
    .SYNOPSIS
    Create, or reuse, the managed disk that carries the upgrade media for one VM

    .DESCRIPTION
    Builds a managed disk from LUN 0 of the newest version of the hidden upgrade image, in the
    VM's region and zone. One disk per VM: a managed disk attaches to one VM at a time. An existing
    disk with the expected name is reused, which keeps a rerun cheap and idempotent.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; the public caller gates with ShouldProcess before invoking it.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$VM,
        [Parameter(Mandatory)][string]$DiskName,
        [Parameter(Mandatory)][string]$DiskResourceGroupName,
        [Parameter(Mandatory)]$MediaEngine,
        [Parameter()][string]$SkuName = 'Standard_LRS'
    )

    $existing = Get-AzDisk -ResourceGroupName $DiskResourceGroupName -DiskName $DiskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Verbose "[$($VM.Name)] Reusing existing upgrade media disk '$DiskName'."
        return $existing
    }

    $lookup = Get-MediaImageVersion -Location $VM.Location -Publisher $MediaEngine.publisher -Offer $MediaEngine.offer -Sku $MediaEngine.sku
    if ($lookup.Error) { throw "Could not look up the upgrade image: $($lookup.Error)" }
    if (-not $lookup.Version) { throw "Upgrade image '$($MediaEngine.sku)' is not available in region '$($VM.Location)'." }

    $image = Get-AzVMImage -Location $VM.Location -PublisherName $MediaEngine.publisher -Offer $MediaEngine.offer `
        -Skus $MediaEngine.sku -Version $lookup.Version -ErrorAction Stop
    Write-Verbose "[$($VM.Name)] Upgrade image version $($image.Version)."

    $zone = (Get-VMArmFacts -VM $VM).Zone
    $diskConfig = if ($zone) {
        New-AzDiskConfig -SkuName $SkuName -CreateOption FromImage -Location $VM.Location -Zone $zone -Tag @{ UpgradeSourceVM = $VM.Name }
    }
    else {
        New-AzDiskConfig -SkuName $SkuName -CreateOption FromImage -Location $VM.Location -Tag @{ UpgradeSourceVM = $VM.Name }
    }
    $null = Set-AzDiskImageReference -Disk $diskConfig -Id $image.Id -Lun 0 -ErrorAction Stop

    Write-Verbose "[$($VM.Name)] Creating upgrade media disk '$DiskName' in '$DiskResourceGroupName'."
    return New-AzDisk -ResourceGroupName $DiskResourceGroupName -DiskName $DiskName -Disk $diskConfig -ErrorAction Stop
}
