Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
$script:TargetMatrixPath = Join-Path $PSScriptRoot 'targets.json'
$script:TargetMatrix = $null

# Tag names are the public contract with the people who approve upgrades. Changing one is a
# breaking change and goes through the CHANGELOG.
# Inside the guest: the scheduled task that runs Setup, and where /copylogs puts the logs.
$script:GuestTaskName = 'AzureInPlaceUpgrade'
$script:GuestLogDirectory = 'C:\Windows\Temp\AzureInPlaceUpgrade'

$script:State = @{
    Pending         = 'Pending'
    SnapshotCreated = 'SnapshotCreated'
    UpgradeStarted  = 'UpgradeStarted'
    Completed       = 'Completed'
    Failed          = 'Failed'
}

# Engines the module can drive. MediaDisk is the default and the only one without a network
# dependency; FeatureUpdate needs Windows Update reachability and is chosen explicitly (ADR 0006).
$script:ImplementedEngines = @('MediaDisk', 'FeatureUpdate')

foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -File) {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName
)
