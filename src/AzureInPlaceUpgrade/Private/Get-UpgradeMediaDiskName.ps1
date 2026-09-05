function Get-UpgradeMediaDiskName {
    <#
    .SYNOPSIS
    Derive the media disk name for a VM and target
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$Target
    )

    return ('{0}-upgrademedia-{1}' -f $VMName, $Target.ToLowerInvariant())
}
