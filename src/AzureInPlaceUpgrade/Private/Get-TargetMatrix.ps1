function Get-TargetMatrix {
    <#
    .SYNOPSIS
    Load and cache the target matrix shipped with the module

    .DESCRIPTION
    The matrix (targets.json) is the only place that maps a tag value such as WS2025 to source
    builds, editions, media images and product keys. A tag value that is not a key in this file
    never reaches an Azure image, which is the whole point of having the file.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([switch]$Force)

    if ($script:TargetMatrix -and -not $Force) { return $script:TargetMatrix }

    $raw = Get-Content -LiteralPath $script:TargetMatrixPath -Raw -ErrorAction Stop
    $matrix = $raw | ConvertFrom-Json -ErrorAction Stop

    if ((Get-PropertyOrDefault -InputObject $matrix -Name 'schemaVersion' -Default 0) -ne 1) {
        throw "Unsupported target matrix schema in '$($script:TargetMatrixPath)'. Expected schemaVersion 1."
    }
    if (-not (Test-Member -InputObject $matrix -Name 'targets')) {
        throw "Target matrix '$($script:TargetMatrixPath)' has no 'targets' element."
    }

    $script:TargetMatrix = $matrix
    return $matrix
}
