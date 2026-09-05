function ConvertFrom-GuestFacts {
    <#
    .SYNOPSIS
    Parse the IPU-FACTS line out of Run Command output into a typed object

    .DESCRIPTION
    Pure function. Returns $null when no marker line is present or the JSON does not parse, so
    the caller can treat "no facts" and "unreachable" the same way. Missing fields get safe
    defaults; the readiness rules never see $null where they expect a value.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Output
    )

    $marker = 'IPU-FACTS='
    $line = @($Output -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_.StartsWith($marker) }) | Select-Object -Last 1
    if (-not $line) { return $null }

    try {
        $raw = $line.Substring($marker.Length) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Verbose "Guest facts line did not parse as JSON: $($_.Exception.Message)"
        return $null
    }

    [pscustomobject]@{
        PSTypeName            = 'AzureInPlaceUpgrade.GuestFacts'
        Build                 = [int](Get-PropertyOrDefault -InputObject $raw -Name 'Build' -Default 0)
        ProductName           = [string](Get-PropertyOrDefault -InputObject $raw -Name 'ProductName' -Default '')
        EditionId             = [string](Get-PropertyOrDefault -InputObject $raw -Name 'EditionId' -Default '')
        InstallationType      = [string](Get-PropertyOrDefault -InputObject $raw -Name 'InstallationType' -Default '')
        DisplayVersion        = [string](Get-PropertyOrDefault -InputObject $raw -Name 'DisplayVersion' -Default '')
        Architecture          = [string](Get-PropertyOrDefault -InputObject $raw -Name 'Architecture' -Default '')
        Language              = [string](Get-PropertyOrDefault -InputObject $raw -Name 'Language' -Default '')
        FreeGB                = [double](Get-PropertyOrDefault -InputObject $raw -Name 'FreeGB' -Default 0)
        PendingReboot         = [bool](Get-PropertyOrDefault -InputObject $raw -Name 'PendingReboot' -Default $false)
        DomainRole            = [int](Get-PropertyOrDefault -InputObject $raw -Name 'DomainRole' -Default 0)
        ClusterServicePresent = [bool](Get-PropertyOrDefault -InputObject $raw -Name 'ClusterServicePresent' -Default $false)
        ActivationChannel     = [string](Get-PropertyOrDefault -InputObject $raw -Name 'ActivationChannel' -Default 'unknown')
        LicenseStatus         = [int](Get-PropertyOrDefault -InputObject $raw -Name 'LicenseStatus' -Default -1)
        SetupRunning          = [bool](Get-PropertyOrDefault -InputObject $raw -Name 'SetupRunning' -Default $false)
    }
}
