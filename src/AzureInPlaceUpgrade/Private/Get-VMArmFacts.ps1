function Get-VMArmFacts {
    <#
    .SYNOPSIS
    Extract the control-plane facts the preflight needs from a VM object

    .DESCRIPTION
    Pure projection of a PSVirtualMachine (or anything shaped like one) into a flat object, so the
    readiness rules never touch Az types directly and can be tested with fabricated input.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$VM,
        [Parameter()][string]$PowerState = 'unknown'
    )

    $storage = Get-PropertyOrDefault -InputObject $VM -Name 'StorageProfile'
    $osDisk = Get-PropertyOrDefault -InputObject $storage -Name 'OsDisk'

    $managedDisk = Get-PropertyOrDefault -InputObject $osDisk -Name 'ManagedDisk'
    $managed = [bool](Get-PropertyOrDefault -InputObject $managedDisk -Name 'Id' -Default '')

    # Ephemeral OS disks carry DiffDiskSettings.Option = 'Local'; everything else has no settings.
    $diff = Get-PropertyOrDefault -InputObject $osDisk -Name 'DiffDiskSettings'
    $ephemeral = [bool](Get-PropertyOrDefault -InputObject $diff -Name 'Option' -Default '')

    $zones = @(Get-PropertyOrDefault -InputObject $VM -Name 'Zones' -Default @())
    $zone = if ($zones.Count -gt 0) { [string]$zones[0] } else { $null }

    $security = Get-PropertyOrDefault -InputObject $VM -Name 'SecurityProfile'
    $securityType = Get-PropertyOrDefault -InputObject $security -Name 'SecurityType'
    if ($securityType) { $securityType = [string]$securityType }

    [pscustomobject]@{
        PSTypeName        = 'AzureInPlaceUpgrade.ArmFacts'
        VMName            = [string](Get-PropertyOrDefault -InputObject $VM -Name 'Name' -Default '')
        ResourceGroupName = [string](Get-PropertyOrDefault -InputObject $VM -Name 'ResourceGroupName' -Default '')
        Location          = [string](Get-PropertyOrDefault -InputObject $VM -Name 'Location' -Default '')
        Zone              = $zone
        PowerState        = $PowerState
        OsType            = [string](Get-PropertyOrDefault -InputObject $osDisk -Name 'OsType' -Default '')
        OsDiskManaged     = $managed
        OsDiskEphemeral   = $ephemeral
        SecurityType      = $securityType
    }
}
