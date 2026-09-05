function Resolve-GuestSetupPath {
    <#
    .SYNOPSIS
    Find setup.exe on the attached media disk from inside the guest, with retries
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName,
        [Parameter()][int]$MaxAttempts = 6,
        [Parameter()][int]$RetryDelaySeconds = 15
    )

    $lastOutput = ''
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $result = Invoke-GuestScript -ResourceGroupName $ResourceGroupName -VMName $VMName -ScriptText (Get-GuestScript -Name SetupPath)
        if (-not $result.Success) {
            return [pscustomobject]@{ Success = $false; SetupPath = $null; Reason = "Could not probe the guest for setup.exe: $($result.Error)" }
        }

        $parsed = ConvertFrom-GuestResult -Output $result.Output
        if ($parsed -and $parsed.Result -eq 'OK' -and $parsed.Values['SETUP']) {
            return [pscustomobject]@{ Success = $true; SetupPath = [string]$parsed.Values['SETUP']; Reason = 'Media found.' }
        }

        $lastOutput = if ($parsed) { $parsed.Raw } else { $result.Output }
        if ($attempt -lt $MaxAttempts) {
            Write-Verbose "[$VMName] setup.exe not visible yet (attempt $attempt/$MaxAttempts): $lastOutput"
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    return [pscustomobject]@{ Success = $false; SetupPath = $null; Reason = "setup.exe was not found after $MaxAttempts attempts. Last guest state: $lastOutput" }
}
