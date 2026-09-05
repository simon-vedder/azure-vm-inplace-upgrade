function Get-GuestWimImage {
    <#
    .SYNOPSIS
    List the images in the upgrade media's install.wim, as seen from inside the guest
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$SetupPath
    )

    $result = Invoke-GuestScript -ResourceGroupName $ResourceGroupName -VMName $VMName -ScriptText (Get-GuestScript -Name WimImages) -Parameter @{ SetupPath = $SetupPath }
    if (-not $result.Success) {
        return [pscustomobject]@{ WimPath = $null; Images = @(); Error = "Could not list the media images: $($result.Error)" }
    }
    return ConvertFrom-GuestWimImage -Output $result.Output
}
