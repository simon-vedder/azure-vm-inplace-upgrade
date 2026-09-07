function Get-InPlaceUpgradeTarget {
    <#
    .SYNOPSIS
    Resolve an upgrade target and its supported source versions from the target matrix

    .DESCRIPTION
    The target matrix shipped with the module (targets.json) is the only mapping from a target key
    such as WS2025 to source builds, editions, installation types, upgrade media images and the
    public KMS client setup keys Setup may need. This function reads it. Without parameters it
    returns every target; with -Name one target; with -SourceBuild only the targets that accept
    that build as a source, each with the matching source entry attached in the Source property.
    Read-only, no Azure calls.

    .PARAMETER Name
    The target key, for example WS2025. Case-insensitive. An unknown key throws and lists the
    known keys.

    .PARAMETER SourceBuild
    The Windows build number the guest currently runs (20348 for Windows Server 2022). Targets that
    do not accept it as a source are filtered out.

    .EXAMPLE
    # List every target and its sources
    Get-InPlaceUpgradeTarget | Select-Object Name, TargetBuild, @{ n = 'Sources'; e = { $_.Sources.Name -join ', ' } }

    .EXAMPLE
    # Which targets can a Windows Server 2016 (build 14393) guest go to?
    Get-InPlaceUpgradeTarget -SourceBuild 14393 | Select-Object Name, DisplayName, @{ n = 'Verified'; e = { $_.Source.Verified } }

    .EXAMPLE
    # The media image and product keys for WS2025
    (Get-InPlaceUpgradeTarget -Name WS2025).Engines.MediaDisk

    .INPUTS
    None

    .OUTPUTS
    AzureInPlaceUpgrade.Target

    .NOTES
    Author:              Simon Vedder (simonvedder.com)
    Version:             0.1.0
    Created:             2026-09-04
    LastModified:        2026-09-04
    RequiredPermissions: None (reads a file shipped with the module)
    Prerequisites:       PowerShell 7.2+

    .LINK
    https://github.com/simon-vedder/azure-vm-inplace-upgrade
    #>
    [CmdletBinding()]
    [OutputType('AzureInPlaceUpgrade.Target')]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$SourceBuild
    )

    $matrix = Get-TargetMatrix
    $names = @($matrix.targets.PSObject.Properties.Name)

    $selected = $names
    if ($Name) {
        $selected = @($names | Where-Object { $_ -ieq $Name.Trim() })
        if ($selected.Count -eq 0) {
            throw "Unknown upgrade target '$Name'. Known targets: $($names -join ', ')."
        }
    }

    foreach ($key in $selected) {
        $node = $matrix.targets.$key
        $sources = @($node.sources | ForEach-Object {
                [pscustomobject]@{
                    PSTypeName = 'AzureInPlaceUpgrade.Source'
                    Build      = [int]$_.build
                    Name       = [string]$_.name
                    Engines    = @($_.engines)
                    Verified   = [bool]$_.verified
                }
            })

        $source = $null
        if ($PSBoundParameters.ContainsKey('SourceBuild')) {
            $source = $sources | Where-Object { $_.Build -eq $SourceBuild } | Select-Object -First 1
            if (-not $source) { continue }
        }

        [pscustomobject]@{
            PSTypeName        = 'AzureInPlaceUpgrade.Target'
            Name              = $key
            DisplayName       = [string]$node.displayName
            TargetBuild       = [int]$node.targetBuild
            Sources           = $sources
            Source            = $source
            Editions          = @($node.editions)
            InstallationTypes = @($node.installationTypes)
            Language          = [string]$node.language
            Architecture      = [string]$node.architecture
            Engines           = $node.engines
            ProductKeys       = $node.productKeys
        }
    }
}
