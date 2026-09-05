function ConvertFrom-GuestWimImage {
    <#
    .SYNOPSIS
    Parse the IPU-IMAGES line into a WimPath and a typed image list (pure)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Output
    )

    $marker = 'IPU-IMAGES='
    $line = @($Output -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_.StartsWith($marker) }) | Select-Object -Last 1
    if (-not $line) {
        return [pscustomobject]@{ WimPath = $null; Images = @(); Error = "Guest returned no image list. Output: $Output" }
    }

    try { $raw = $line.Substring($marker.Length) | ConvertFrom-Json -ErrorAction Stop }
    catch { return [pscustomobject]@{ WimPath = $null; Images = @(); Error = "Image list did not parse: $($_.Exception.Message)" } }

    $images = @(@(Get-PropertyOrDefault -InputObject $raw -Name 'Images' -Default @()) | ForEach-Object {
            [pscustomobject]@{
                PSTypeName       = 'AzureInPlaceUpgrade.WimImage'
                Index            = [int](Get-PropertyOrDefault -InputObject $_ -Name 'Index' -Default 0)
                Name             = [string](Get-PropertyOrDefault -InputObject $_ -Name 'Name' -Default '')
                EditionId        = [string](Get-PropertyOrDefault -InputObject $_ -Name 'EditionId' -Default '')
                InstallationType = [string](Get-PropertyOrDefault -InputObject $_ -Name 'InstallationType' -Default '')
                Version          = [string](Get-PropertyOrDefault -InputObject $_ -Name 'Version' -Default '')
            }
        })

    [pscustomobject]@{
        WimPath = [string](Get-PropertyOrDefault -InputObject $raw -Name 'WimPath' -Default '')
        Images  = $images
        Error   = $null
    }
}
