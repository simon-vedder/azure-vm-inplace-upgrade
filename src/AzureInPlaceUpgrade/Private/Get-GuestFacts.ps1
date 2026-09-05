function Get-GuestFacts {
    <#
    .SYNOPSIS
    Run the guest probe on a VM and return parsed facts or an error
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName
    )

    $result = Invoke-GuestScript -ResourceGroupName $ResourceGroupName -VMName $VMName -ScriptText (Get-GuestScript -Name Facts)
    if (-not $result.Success) {
        return [pscustomobject]@{ Facts = $null; Error = $result.Error }
    }

    $facts = ConvertFrom-GuestFacts -Output $result.Output
    if (-not $facts) {
        $detail = if ($result.Error) { $result.Error } else { $result.Output }
        return [pscustomobject]@{ Facts = $null; Error = "Guest probe returned no parsable facts. Guest said: $detail" }
    }

    return [pscustomobject]@{ Facts = $facts; Error = $null }
}
