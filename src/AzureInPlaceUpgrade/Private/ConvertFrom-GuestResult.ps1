function ConvertFrom-GuestResult {
    <#
    .SYNOPSIS
    Parse a RESULT=...;KEY=value line from guest output

    .DESCRIPTION
    Pure. Finds the last line starting with RESULT= and splits it into key/value pairs. Returns
    $null when there is no such line, so callers treat "no answer" and "unreachable" alike.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Output
    )

    $line = @($Output -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -like 'RESULT=*' }) | Select-Object -Last 1
    if (-not $line) { return $null }

    $values = [ordered]@{}
    foreach ($segment in ($line -split ';')) {
        $index = $segment.IndexOf('=')
        if ($index -lt 1) { continue }
        $values[$segment.Substring(0, $index).Trim()] = $segment.Substring($index + 1).Trim()
    }

    [pscustomobject]@{
        PSTypeName = 'AzureInPlaceUpgrade.GuestResult'
        Result     = [string]$values['RESULT']
        Values     = $values
        Raw        = $line
    }
}
