function Write-UpgradeRecord {
    <#
    .SYNOPSIS
    Send one record to a Log Analytics custom table through the Logs Ingestion API

    .DESCRIPTION
    Uses a data collection endpoint plus a data collection rule (immutable id), never the retired
    HTTP Data Collector API. The caller's identity needs Monitoring Metrics Publisher on the rule.
    A failure to write telemetry is reported through Write-Warning and never changes the outcome of
    an upgrade; the job output still carries the same information. Does nothing when no endpoint
    is configured, so local runs without a workspace stay silent.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Telemetry write; the public caller already passed its own ShouldProcess gate.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Record,
        [Parameter()][AllowEmptyString()][string]$LogIngestionEndpoint,
        [Parameter()][AllowEmptyString()][string]$DataCollectionRuleId,
        [Parameter()][string]$StreamName = 'Custom-InPlaceUpgrade_CL'
    )

    if ([string]::IsNullOrWhiteSpace($LogIngestionEndpoint) -or [string]::IsNullOrWhiteSpace($DataCollectionRuleId)) {
        return $false
    }

    try {
        $token = (Get-AzAccessToken -ResourceUrl 'https://monitor.azure.com' -ErrorAction Stop).Token
        if ($token -is [System.Security.SecureString]) {
            $token = [System.Net.NetworkCredential]::new('', $token).Password
        }
        $uri = '{0}/dataCollectionRules/{1}/streams/{2}?api-version=2023-01-01' -f $LogIngestionEndpoint.TrimEnd('/'), $DataCollectionRuleId, $StreamName
        $body = ConvertTo-Json -InputObject @($Record | Select-Object -ExcludeProperty PSTypeName) -Depth 5 -Compress
        $null = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/json' -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
        Write-Verbose "[$($Record.VMName)] Record written: $($Record.State)/$($Record.Result)."
        return $true
    }
    catch {
        Write-Warning "[$($Record.VMName)] Could not write the upgrade record to Log Analytics: $($_.Exception.Message)"
        return $false
    }
}
