function Get-GuestUpgradeStatus {
    <#
    .SYNOPSIS
    Read build, Setup processes and scheduled task state from the guest; $null when unreachable
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName
    )

    $result = Invoke-GuestScript -ResourceGroupName $ResourceGroupName -VMName $VMName -ScriptText (Get-GuestScript -Name Status) -Parameter @{ TaskName = $script:GuestTaskName }
    if (-not $result.Success) { return $null }

    $marker = 'IPU-STATUS='
    $line = @($result.Output -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_.StartsWith($marker) }) | Select-Object -Last 1
    if (-not $line) { return $null }

    try { $raw = $line.Substring($marker.Length) | ConvertFrom-Json -ErrorAction Stop } catch { return $null }

    $taskResult = Get-PropertyOrDefault -InputObject $raw -Name 'TaskResult'
    [pscustomobject]@{
        PSTypeName     = 'AzureInPlaceUpgrade.GuestStatus'
        Build          = [int](Get-PropertyOrDefault -InputObject $raw -Name 'Build' -Default 0)
        ProductName    = [string](Get-PropertyOrDefault -InputObject $raw -Name 'ProductName' -Default '')
        DisplayVersion = [string](Get-PropertyOrDefault -InputObject $raw -Name 'DisplayVersion' -Default '')
        SetupRunning   = [bool](Get-PropertyOrDefault -InputObject $raw -Name 'SetupRunning' -Default $false)
        TaskState      = [string](Get-PropertyOrDefault -InputObject $raw -Name 'TaskState' -Default 'None')
        TaskResult     = if ($null -ne $taskResult) { [uint32]$taskResult } else { $null }
    }
}
