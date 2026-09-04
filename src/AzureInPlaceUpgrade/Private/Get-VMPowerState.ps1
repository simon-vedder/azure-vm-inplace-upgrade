function Get-VMPowerState {
    <#
    .SYNOPSIS
    Return the normalised power state of a VM ('running', 'deallocated', 'stopped', 'unknown')
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName
    )

    try {
        $status = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status -ErrorAction Stop
        $code = ($status.Statuses | Where-Object { $_.Code -like 'PowerState/*' } | Select-Object -First 1).Code
        if ($code) { return ($code -split '/')[-1] }
        return 'unknown'
    }
    catch {
        Write-Verbose "[$VMName] Could not read power state: $($_.Exception.Message)"
        return 'unknown'
    }
}
