function Test-CandidateTag {
    <#
    .SYNOPSIS
    Decide whether a VM's tags select it for processing

    .DESCRIPTION
    Pure filter used by Get-InPlaceUpgradeCandidate. A VM qualifies when it carries an
    UpgradeTarget tag and every filter that was given (target, state, ring) matches
    case-insensitively. An empty filter means "any". Without a state filter a VM in any state
    qualifies; the orchestrator always passes one, so that a VM is only ever picked up in the state
    a mode expects.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]$VM,
        [Parameter()][string]$Target,
        [Parameter()][string]$State,
        [Parameter()][string]$Ring
    )

    $tagTarget = Get-VMTagValue -VM $VM -Name $script:Tag.Target
    if (-not $tagTarget) { return $false }
    if ($Target -and $tagTarget -ine $Target.Trim()) { return $false }

    if ($State) {
        $tagState = Get-VMTagValue -VM $VM -Name $script:Tag.State
        if (-not $tagState -or $tagState -ine $State.Trim()) { return $false }
    }

    if ($Ring) {
        $tagRing = Get-VMTagValue -VM $VM -Name $script:Tag.Ring
        if (-not $tagRing -or $tagRing -ine $Ring.Trim()) { return $false }
    }

    return $true
}
