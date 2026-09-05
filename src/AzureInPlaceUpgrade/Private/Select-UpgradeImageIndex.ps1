function Select-UpgradeImageIndex {
    <#
    .SYNOPSIS
    Pick the install.wim image that matches the guest's edition and installation type (pure)

    .DESCRIPTION
    Unattended Setup cannot choose between "Datacenter" and "Datacenter (Desktop Experience)"
    on its own: with two matching images and nobody to answer the GUI prompt it falls back to its
    SkuLib, finds no upgrade edition and aborts with 0xC1900215 (observed 2026-09-05, with and
    without /pkey). Matching the guest's EditionId and InstallationType against the WIM metadata
    is deterministic and media-independent. Exactly one match is required; none or several
    return $null so the caller refuses to guess.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Image,
        [Parameter(Mandatory)][string]$EditionId,
        [Parameter(Mandatory)][string]$InstallationType
    )

    $edition = $EditionId -replace '(Cor|Core)$', ''
    $candidates = @($Image | Where-Object {
            ($_.EditionId -replace '(Cor|Core)$', '') -ieq $edition -and $_.InstallationType -ieq $InstallationType
        })

    if ($candidates.Count -ne 1) { return $null }
    return [int]$candidates[0].Index
}
