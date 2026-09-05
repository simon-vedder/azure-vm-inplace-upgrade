function Start-GuestSetup {
    <#
    .SYNOPSIS
    Register and start the scheduled task that runs Setup, and report whether it is alive
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; the public caller gates with ShouldProcess before invoking it.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$SetupPath,
        [Parameter()][string]$ProductKey,
        [Parameter()][int]$TargetImageIndex = 0,
        [Parameter()][string]$InstallFrom
    )

    $result = Invoke-GuestScript -ResourceGroupName $ResourceGroupName -VMName $VMName -ScriptText (Get-GuestScript -Name Launch) -Parameter @{
        SetupPath        = $SetupPath
        TaskName         = $script:GuestTaskName
        ProductKey       = $ProductKey
        TargetImageIndex = $TargetImageIndex
        InstallFrom      = $InstallFrom
        LogDirectory     = $script:GuestLogDirectory
    }
    if (-not $result.Success) {
        return [pscustomobject]@{ Started = $false; Reason = "Run Command failed: $($result.Error)"; Raw = $null }
    }

    $parsed = ConvertFrom-GuestResult -Output $result.Output
    if (-not $parsed) {
        return [pscustomobject]@{ Started = $false; Reason = "Unexpected guest response: $($result.Output)"; Raw = $result.Output }
    }
    $raw = Hide-ProductKey -Text $parsed.Raw

    switch ($parsed.Result) {
        'NOTFOUND' { return [pscustomobject]@{ Started = $false; Reason = "setup.exe '$SetupPath' is not reachable from the guest."; Raw = $raw } }
        'INSTALLWIMNOTFOUND' { return [pscustomobject]@{ Started = $false; Reason = "install.wim needed for -TargetImageIndex was not found: $($parsed.Values['WIM'])"; Raw = $raw } }
        'ALREADYRUNNING' { return [pscustomobject]@{ Started = $true; Reason = 'An upgrade is already running in the guest.'; Raw = $raw } }
        'STARTED' { return [pscustomobject]@{ Started = $true; Reason = "Setup started (processes: $($parsed.Values['PROCESSES']))."; Raw = $raw } }
        'FAILED' {
            $excerpt = Get-GuestSetupLogTail -ResourceGroupName $ResourceGroupName -VMName $VMName
            return [pscustomobject]@{ Started = $false; Reason = "Setup exited immediately: task state $($parsed.Values['STATE']), last result $($parsed.Values['HEX']).`nLog excerpt:`n$excerpt"; Raw = $raw }
        }
        default { return [pscustomobject]@{ Started = $false; Reason = "Unexpected guest response: $raw"; Raw = $raw } }
    }
}
