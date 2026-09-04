function Test-Member {
    <#
    .SYNOPSIS
    Check whether an object exposes a property or a dictionary contains a key

    .DESCRIPTION
    Set-StrictMode throws on access to a missing property. Every optional member of an Az object
    (Zones, SecurityProfile, DiffDiskSettings, Tags) is read through this helper instead.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $false }
    if ($InputObject -is [System.Collections.IDictionary]) { return [bool]$InputObject.Contains($Name) }
    return $null -ne $InputObject.PSObject.Properties[$Name]
}
