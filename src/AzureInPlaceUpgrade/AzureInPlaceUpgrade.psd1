@{
    RootModule           = 'AzureInPlaceUpgrade.psm1'
    ModuleVersion        = '0.3.1'
    CompatiblePSEditions = @('Core')
    GUID                 = 'd93feeee-c72c-4b2a-b0aa-d11b68ed20b8'
    Author               = 'Simon Vedder'
    CompanyName          = 'Simon Vedder'
    Copyright            = '(c) 2026 Simon Vedder. MIT License.'
    Description          = 'Unattended in-place Windows Server upgrades for Azure VMs, one by name or a tagged fleet from a runbook: preflight, OS disk snapshot, detached Windows Setup, state tracking across Azure Automation jobs and in-guest validation.'
    PowerShellVersion    = '7.2'
    # Minimums match the Az bundle the Azure Automation PowerShell 7.2 runtime ships by default
    # (Az 11.2.0). Importing newer Az.Accounts into an Automation Account next to the default one
    # breaks assembly loading; the deployment therefore imports no Az modules at all.
    RequiredModules      = @(
        @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.15.0' }
        @{ ModuleName = 'Az.Compute'; ModuleVersion = '7.1.1' }
        @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.13.0' }
    )
    FunctionsToExport    = @(
        'Complete-InPlaceUpgrade'
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
