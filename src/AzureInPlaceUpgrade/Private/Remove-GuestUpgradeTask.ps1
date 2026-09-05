function Remove-GuestUpgradeTask {
    <#
    .SYNOPSIS
    Unregister the Setup scheduled task after a final state; best effort
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; the public caller gates with ShouldProcess before invoking it.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName
    )

    $result = Invoke-GuestScript -ResourceGroupName $ResourceGroupName -VMName $VMName -ScriptText (Get-GuestScript -Name RemoveTask) -Parameter @{ TaskName = $script:GuestTaskName }
    return ($result.Success -and $result.Output -match 'RESULT=(REMOVED|NOTFOUND)')
}
