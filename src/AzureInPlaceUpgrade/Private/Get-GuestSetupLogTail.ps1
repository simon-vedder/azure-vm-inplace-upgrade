function Get-GuestSetupLogTail {
    <#
    .SYNOPSIS
    Pull a short excerpt of the Windows Setup logs from the guest after a failure
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName
    )

    $result = Invoke-GuestScript -ResourceGroupName $ResourceGroupName -VMName $VMName -ScriptText (Get-GuestScript -Name LogTail) -Parameter @{ CopyLogsPath = $script:GuestLogDirectory }
    if (-not $result.Success -or $result.Output -match '^RESULT=NOLOGS') {
        return 'No Setup log excerpt could be retrieved from the guest (logs not written yet, or the guest is unreachable).'
    }
    return ($result.Output -replace '^RESULT=OK\r?\n', '')
}
