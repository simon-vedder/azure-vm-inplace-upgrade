function Set-UpgradeTag {
    <#
    .SYNOPSIS
    Merge tags onto a resource, preserving everything else

    .DESCRIPTION
    Update-AzTag -Operation Merge only adds or overwrites the given keys; governance tags and
    inherited tags survive. Values are stringified because Azure tags are strings.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; the public caller gates with ShouldProcess before invoking it.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][hashtable]$Tag
    )

    $stringTags = @{}
    foreach ($key in $Tag.Keys) { $stringTags[$key] = [string]$Tag[$key] }
    $null = Update-AzTag -ResourceId $ResourceId -Tag $stringTags -Operation Merge -ErrorAction Stop
    Write-Verbose ("Tags merged: " + (($stringTags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '))
}
