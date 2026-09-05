function ConvertFrom-TagTimestamp {
    <#
    .SYNOPSIS
    Parse a tag timestamp back into a UTC datetime, or $null

    .DESCRIPTION
    Accepts the epoch format the module writes, ISO 8601, and the invariant "MM/dd/yyyy HH:mm:ss"
    form that an Az round trip produces from an ISO value, so tags written by older versions
    still work. Anything else yields $null.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )

    $text = $Value.Trim()
    if (-not $text) { return $null }

    if ($text -match '^\d{9,11}$') {
        return [DateTimeOffset]::FromUnixTimeSeconds([long]$text).UtcDateTime
    }

    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($text, [cultureinfo]::InvariantCulture, $styles, [ref]$parsed)) { return $parsed }
    return $null
}
