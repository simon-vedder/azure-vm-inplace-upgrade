function Get-PropertyOrDefault {
    <#
    .SYNOPSIS
    Read a property that may be missing or null and fall back to a default
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][AllowNull()]$Default = $null
    )

    if (-not (Test-Member -InputObject $InputObject -Name $Name)) { return $Default }
    $value = if ($InputObject -is [System.Collections.IDictionary]) { $InputObject[$Name] } else { $InputObject.$Name }
    if ($null -eq $value) { return $Default }
    return $value
}
