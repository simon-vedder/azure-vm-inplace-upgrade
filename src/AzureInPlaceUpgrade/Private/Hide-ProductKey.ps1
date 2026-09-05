function Hide-ProductKey {
    <#
    .SYNOPSIS
    Mask a /pkey value in text before it reaches logs or output
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    return ($Text -replace '(?i)(/pkey\s+)[A-Z0-9-]+', '$1*****')
}
