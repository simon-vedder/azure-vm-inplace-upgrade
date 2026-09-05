function Resolve-UpgradeCompletion {
    <#
    .SYNOPSIS
    Decide what state a VM in UpgradeStarted is in (pure, no Azure calls)

    .DESCRIPTION
    The Check side of the state machine. Four situations are distinguished:
      guest reports the target build              -> Completed
      guest unreachable or Setup running          -> InProgress, or Failed once the timeout passed
      guest on the old build, task ended in error -> Failed
      VM stopped or deallocated                   -> Failed
    A task result counts as an error only when it is an HRESULT with the severity bit set
    (0x8xxxxxxx / 0xCxxxxxxx, which covers every MOSETUP_E_* code) or a plain 1. Task Scheduler's
    own status codes (0x41301 running, 0x41303 not yet run, 0x41306 terminated) appear when a
    reboot cuts the task short and are not failures.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][string]$PowerState,
        [Parameter()][AllowNull()]$Status,
        [Parameter()][AllowNull()][nullable[datetime]]$StartedAt,
        [Parameter()][ValidateRange(1, 10080)][int]$TimeoutMinutes = 240,
        [Parameter()][datetime]$Now = (Get-Date).ToUniversalTime()
    )

    $ageMinutes = $null
    $expired = $false
    if ($null -ne $StartedAt) {
        $ageMinutes = [int]($Now - $StartedAt.ToUniversalTime()).TotalMinutes
        $expired = $ageMinutes -gt $TimeoutMinutes
    }

    function ConvertTo-Outcome {
        param([string]$Result, [string]$Reason, [bool]$TaskFailed = $false)
        [pscustomobject]@{
            PSTypeName = 'AzureInPlaceUpgrade.CompletionDecision'
            Result     = $Result
            Reason     = $Reason
            TaskFailed = $TaskFailed
            Expired    = $expired
            AgeMinutes = $ageMinutes
        }
    }

    if ($PowerState -in @('deallocated', 'stopped')) {
        return ConvertTo-Outcome 'Failed' "VM is '$PowerState' while an upgrade was in progress."
    }

    if ($null -eq $Status) {
        if ($expired) { return ConvertTo-Outcome 'Failed' "Guest unreachable and the upgrade started $ageMinutes minutes ago (timeout $TimeoutMinutes)." }
        return ConvertTo-Outcome 'InProgress' 'Guest not reachable (reboot in progress).'
    }

    if ($Status.Build -eq $Target.TargetBuild) {
        return ConvertTo-Outcome 'Completed' "$($Status.ProductName) build $($Status.Build)."
    }

    if ($Status.SetupRunning -or $Status.TaskState -eq 'Running') {
        if ($expired) { return ConvertTo-Outcome 'Failed' "Setup still running after $ageMinutes minutes (timeout $TimeoutMinutes)." }
        return ConvertTo-Outcome 'InProgress' "Setup running (build $($Status.Build))."
    }

    if ($null -ne $Status.TaskResult) {
        # 0x80000000 as a literal is a negative Int32 in PowerShell; test the severity bit by shift.
        $code = [uint32]$Status.TaskResult
        if (($code -shr 31) -eq 1 -or $code -eq 1) {
            $hex = '0x{0:X8}' -f $code
            return ConvertTo-Outcome 'Failed' "Setup task exited with $hex and the build is still $($Status.Build)." $true
        }
    }

    if ($expired) { return ConvertTo-Outcome 'Failed' "Build is still $($Status.Build) after $ageMinutes minutes (timeout $TimeoutMinutes)." }
    return ConvertTo-Outcome 'InProgress' "Build is still $($Status.Build); waiting."
}
