function Get-VMTagValue {
    <#
    .SYNOPSIS
    Read a tag value from a VM without failing on missing tags

    .DESCRIPTION
    Azure treats tag names case-insensitively; the dictionary on the VM object does not. The lookup
    is therefore case-insensitive and the value is trimmed, because the portal happily stores
    trailing whitespace that then breaks every -eq comparison downstream.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$VM,
        [Parameter(Mandatory)][string]$Name
    )

    $tags = Get-PropertyOrDefault -InputObject $VM -Name 'Tags'
    if (-not $tags -or $tags.Count -eq 0) { return $null }

    $key = @($tags.Keys) | Where-Object { $_ -ieq $Name } | Select-Object -First 1
    if (-not $key) { return $null }

    $value = [string]$tags[$key]
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return $value.Trim()
}
