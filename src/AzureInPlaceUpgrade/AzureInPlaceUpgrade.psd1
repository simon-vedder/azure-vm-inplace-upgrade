@{
    RootModule           = 'AzureInPlaceUpgrade.psm1'
    ModuleVersion        = '0.1.0'
    CompatiblePSEditions = @('Core')
    GUID                 = 'd93feeee-c72c-4b2a-b0aa-d11b68ed20b8'
    Author               = 'Simon Vedder'
    CompanyName          = 'Simon Vedder'
    Copyright            = '(c) 2026 Simon Vedder. MIT License.'
    Description          = 'Tag-driven, unattended in-place Windows Server upgrades for Azure VMs: preflight, OS disk snapshot, detached Windows Setup, state tracking across Azure Automation jobs and in-guest validation.'
    PowerShellVersion    = '7.2'
    RequiredModules      = @(
        @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.19.0' }
        @{ ModuleName = 'Az.Compute'; ModuleVersion = '7.1.0' }
        @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.16.0' }
    )
    FunctionsToExport    = @(
        'Complete-InPlaceUpgrade'
        'Get-InPlaceUpgradeCandidate'
        'Get-InPlaceUpgradeTarget'
        'Invoke-InPlaceUpgrade'
        'Start-InPlaceUpgrade'
        'Test-InPlaceUpgradeReadiness'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'WindowsServer', 'InPlaceUpgrade', 'Upgrade', 'AzureAutomation', 'VirtualMachines', 'PSEdition_Core')
            LicenseUri   = 'https://github.com/simon-vedder/azure-vm-inplace-upgrade/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/simon-vedder/azure-vm-inplace-upgrade'
            ReleaseNotes = 'https://github.com/simon-vedder/azure-vm-inplace-upgrade/blob/main/CHANGELOG.md'
            Prerelease   = 'preview'
        }
    }
}
