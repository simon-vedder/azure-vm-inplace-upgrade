function Get-MediaImageVersion {
    <#
    .SYNOPSIS
    Look up the newest version of the hidden upgrade media image in a region

    .DESCRIPTION
    Read-only. The image is not deployable as a VM; it is only ever used as the source of a
    managed data disk. A lookup failure is returned, not thrown, so the preflight can report it as
    one failed check among many instead of aborting.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Location,
        [Parameter(Mandatory)][string]$Publisher,
        [Parameter(Mandatory)][string]$Offer,
        [Parameter(Mandatory)][string]$Sku
    )

    try {
        $images = @(Get-AzVMImage -Location $Location -PublisherName $Publisher -Offer $Offer -Skus $Sku -ErrorAction Stop)
        $versions = @($images | Sort-Object -Descending { [version]$_.Version })
        $latest = if ($versions.Count -gt 0) { [string]$versions[0].Version } else { $null }
        return [pscustomobject]@{ Checked = $true; Version = $latest; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Checked = $true; Version = $null; Error = $_.Exception.Message }
    }
}
