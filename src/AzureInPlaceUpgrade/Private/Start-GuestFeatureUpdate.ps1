function Start-GuestFeatureUpdate {
    <#
    .SYNOPSIS
    Opt the guest in, find the Windows Server feature update and start the installer task
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; the public caller gates with ShouldProcess before invoking it.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)]$FeatureUpdateEngine
    )

    $result = Invoke-GuestScript -ResourceGroupName $ResourceGroupName -VMName $VMName -ScriptText (Get-GuestScript -Name FeatureUpdateLaunch) -Parameter @{
        TaskName       = $script:GuestTaskName
        LogDirectory   = $script:GuestLogDirectory
        RegistryOptIn  = [string]$FeatureUpdateEngine.registryOptIn
        SearchCriteria = [string]$FeatureUpdateEngine.searchCriteria
        TitlePrefix    = [string]$FeatureUpdateEngine.titlePrefix
    }
    if (-not $result.Success) {
        return [pscustomobject]@{ Started = $false; Reason = "Run Command failed: $($result.Error)"; Raw = $null }
    }

    $parsed = ConvertFrom-GuestResult -Output $result.Output
    if (-not $parsed) {
        return [pscustomobject]@{ Started = $false; Reason = "Unexpected guest response: $($result.Output)"; Raw = $result.Output }
    }

    switch ($parsed.Result) {
        'ALREADYRUNNING' { return [pscustomobject]@{ Started = $true; Reason = 'A feature update installer is already running in the guest.'; Raw = $parsed.Raw } }
        'NOTOFFERED' { return [pscustomobject]@{ Started = $false; Reason = "Windows Update does not offer '$($FeatureUpdateEngine.titlePrefix)' to this guest (offered: $($parsed.Values['OFFERED'])). Check the required cumulative update, Windows Update reachability and that no WSUS policy is in the way."; Raw = $parsed.Raw } }
        'STARTED' { return [pscustomobject]@{ Started = $true; Reason = "Feature update installer started for '$($parsed.Values['UPDATE'])'."; Raw = $parsed.Raw } }
        'FAILED' { return [pscustomobject]@{ Started = $false; Reason = "The installer task did not start: task state $($parsed.Values['STATE'])."; Raw = $parsed.Raw } }
        default { return [pscustomobject]@{ Started = $false; Reason = "Unexpected guest response: $($parsed.Raw)"; Raw = $parsed.Raw } }
    }
}
