function ConvertTo-TagTimestamp {
    <#
    .SYNOPSIS
    Format a point in time for storage in a tag

    .DESCRIPTION
    Unix epoch seconds, UTC, digits only. Not ISO 8601 on purpose: the Az cmdlets round-trip tag
    values through a JSON deserializer that recognises ISO date strings and rewrites them in the
    process culture ("09/05/2026 08:25:45"), which was observed live on Update-AzVM. Digits survive
    every round trip.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][datetime]$Value
    )

    return ([DateTimeOffset]$Value.ToUniversalTime()).ToUnixTimeSeconds().ToString([cultureinfo]::InvariantCulture)
}
