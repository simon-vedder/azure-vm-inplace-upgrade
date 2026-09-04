Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
$script:TargetMatrixPath = Join-Path $PSScriptRoot 'targets.json'
$script:TargetMatrix = $null

# Tag names are the public contract with the people who approve upgrades. Changing one is a
# breaking change and goes through the CHANGELOG.
$script:Tag = @{
    Target    = 'UpgradeTarget'
    Ring      = 'UpgradeRing'
    State     = 'UpgradeState'
    StartedAt = 'UpgradeStartedAt'
}

$script:State = @{
    Pending         = 'Pending'
    SnapshotCreated = 'SnapshotCreated'
    UpgradeStarted  = 'UpgradeStarted'
    Completed       = 'Completed'
    Failed          = 'Failed'
}

# Engines the module can actually drive today. The matrix may list more (FeatureUpdate is
# experimental); the preflight only ever selects from this list.
$script:ImplementedEngines = @('MediaDisk')

foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -File) {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName
)
