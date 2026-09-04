function Resolve-InPlaceUpgradeReadiness {
    <#
    .SYNOPSIS
    Turn collected facts into a readiness decision (pure, no Azure calls)

    .DESCRIPTION
    Every rule the preflight applies lives here, in one place, testable with fabricated facts.
    Checks are evaluated cheapest first and never stop early, so the operator sees the full list
    of problems in one run instead of one per run. A single Fail makes the VM NotEligible; Warn
    is informational. A guest that already runs the target build is AlreadyAtTarget regardless of
    any other finding, because there is nothing to do.
    #>
    [CmdletBinding()]
    [OutputType('AzureInPlaceUpgrade.Readiness')]
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)]$ArmFacts,
        [Parameter()][AllowNull()]$GuestFacts,
        [Parameter()][AllowEmptyString()][string]$GuestError,
        [Parameter()][ValidateRange(1, 1000)][int]$MinimumFreeSpaceGB = 30,
        [Parameter()][AllowNull()]$Media
    )

    $checks = [System.Collections.Generic.List[object]]::new()
    function Add-Check {
        param([string]$Name, [ValidateSet('Pass', 'Warn', 'Fail', 'Skip')][string]$Result, [string]$Detail)
        $checks.Add([pscustomobject]@{ PSTypeName = 'AzureInPlaceUpgrade.Check'; Name = $Name; Result = $Result; Detail = $Detail })
    }

    $alreadyAtTarget = $false
    $source = $null
    $engine = $null

    # --- control plane -------------------------------------------------------------------------

    if ($ArmFacts.PowerState -eq 'running') { Add-Check 'PowerState' 'Pass' 'VM is running.' }
    else { Add-Check 'PowerState' 'Fail' "VM power state is '$($ArmFacts.PowerState)'; it must be running." }

    if ($ArmFacts.OsType -ieq 'Windows') { Add-Check 'OsType' 'Pass' 'Windows OS disk.' }
    else { Add-Check 'OsType' 'Fail' "OS type is '$($ArmFacts.OsType)', not Windows." }

    if ($ArmFacts.OsDiskManaged) { Add-Check 'OsDiskManaged' 'Pass' 'Managed OS disk; a snapshot is possible.' }
    else { Add-Check 'OsDiskManaged' 'Fail' 'OS disk is unmanaged; migrate to managed disks first.' }

    if ($ArmFacts.OsDiskEphemeral) { Add-Check 'OsDiskEphemeral' 'Fail' 'Ephemeral OS disk; it cannot be snapshotted and resets on reallocation.' }
    else { Add-Check 'OsDiskEphemeral' 'Pass' 'Persistent OS disk.' }

    if ($ArmFacts.SecurityType -and $ArmFacts.SecurityType -in @('TrustedLaunch', 'ConfidentialVM')) {
        Add-Check 'SecurityType' 'Warn' "$($ArmFacts.SecurityType) VM; the media-disk path is not lab-verified for this security type yet."
    }
    else { Add-Check 'SecurityType' 'Pass' 'Standard security type.' }

    # --- guest ---------------------------------------------------------------------------------

    if ($ArmFacts.PowerState -ne 'running') {
        Add-Check 'GuestReachable' 'Skip' 'Guest checks skipped because the VM is not running.'
    }
    elseif ($null -eq $GuestFacts) {
        $detail = if ($GuestError) { "Guest probe failed: $GuestError" } else { 'Guest probe returned nothing.' }
        Add-Check 'GuestReachable' 'Fail' "$detail Verify the Azure Guest Agent and Run Command on this VM."
    }
    else {
        Add-Check 'GuestReachable' 'Pass' "Guest reports $($GuestFacts.ProductName) build $($GuestFacts.Build)."

        if ($GuestFacts.Build -eq $Target.TargetBuild) {
            $alreadyAtTarget = $true
            Add-Check 'SourceBuild' 'Skip' "Guest is already on build $($GuestFacts.Build) ($($Target.DisplayName)); nothing to do."
        }
        else {
            $source = $Target.Sources | Where-Object { $_.Build -eq $GuestFacts.Build } | Select-Object -First 1
            if ($source) {
                $evidence = if ($source.Verified) { 'lab-verified in this project' } else { 'documented by Microsoft, not yet verified in this project' }
                Add-Check 'SourceBuild' 'Pass' "$($source.Name) (build $($source.Build)) to $($Target.DisplayName): $evidence."
            }
            else {
                $allowed = ($Target.Sources | ForEach-Object { "$($_.Name) ($($_.Build))" }) -join ', '
                Add-Check 'SourceBuild' 'Fail' "Build $($GuestFacts.Build) is not a supported source for $($Target.Name). Supported: $allowed."
            }
        }

        # Server Core installs may report the edition with a Cor/Core suffix; the edition itself is
        # the same, the installation type is checked separately.
        $edition = [string]$GuestFacts.EditionId
        $normalizedEdition = $edition -replace '(Cor|Core)$', ''
        if ($Target.Editions -contains $normalizedEdition) { Add-Check 'Edition' 'Pass' "Edition $edition." }
        else {
            $hint = if ($edition -match 'Azure') { ' Windows Server Azure Edition is out of scope for in-place upgrades.' } else { '' }
            Add-Check 'Edition' 'Fail' "Edition '$edition' is not eligible; allowed: $($Target.Editions -join ', ').$hint"
        }

        if ($Target.InstallationTypes -contains $GuestFacts.InstallationType) { Add-Check 'InstallationType' 'Pass' "Installation type '$($GuestFacts.InstallationType)'." }
        else { Add-Check 'InstallationType' 'Fail' "Installation type '$($GuestFacts.InstallationType)' is not eligible; allowed: $($Target.InstallationTypes -join ', ')." }

        if ($GuestFacts.Architecture -ieq $Target.Architecture) { Add-Check 'Architecture' 'Pass' "$($GuestFacts.Architecture)." }
        else { Add-Check 'Architecture' 'Fail' "Architecture '$($GuestFacts.Architecture)'; the upgrade media is $($Target.Architecture)." }

        if ($GuestFacts.Language -ieq $Target.Language) { Add-Check 'Language' 'Pass' "OS language $($GuestFacts.Language)." }
        else { Add-Check 'Language' 'Fail' "OS language is '$($GuestFacts.Language)'; the upgrade media is $($Target.Language) only. Set the system language to $($Target.Language) or redeploy." }

        if ($GuestFacts.FreeGB -ge $MinimumFreeSpaceGB) { Add-Check 'FreeSpace' 'Pass' "$($GuestFacts.FreeGB) GB free on C: (minimum $MinimumFreeSpaceGB GB)." }
        else { Add-Check 'FreeSpace' 'Fail' "Only $($GuestFacts.FreeGB) GB free on C:; $MinimumFreeSpaceGB GB required. Expand the OS disk or clean up." }

        if ($GuestFacts.PendingReboot) { Add-Check 'PendingReboot' 'Fail' 'A reboot is pending in the guest; Setup would abort. Reboot first.' }
        else { Add-Check 'PendingReboot' 'Pass' 'No pending reboot.' }

        if ($GuestFacts.DomainRole -in @(4, 5)) { Add-Check 'DomainController' 'Fail' 'This is a domain controller. Microsoft advises against in-place upgrades of DCs; promote a new one instead.' }
        else { Add-Check 'DomainController' 'Pass' 'Not a domain controller.' }

        if ($GuestFacts.ClusterServicePresent) { Add-Check 'Cluster' 'Fail' 'Failover Clustering is installed. Use Cluster-Aware Updating or a cluster OS rolling upgrade.' }
        else { Add-Check 'Cluster' 'Pass' 'Not a cluster node.' }

        if ($GuestFacts.SetupRunning) { Add-Check 'SetupRunning' 'Fail' 'Windows Setup is already running in the guest.' }
        else { Add-Check 'SetupRunning' 'Pass' 'No Setup process running.' }

        $channel = [string]$GuestFacts.ActivationChannel
        if ($channel -like 'Volume*') { Add-Check 'Activation' 'Pass' "Activation channel $channel." }
        elseif ([string]::IsNullOrWhiteSpace($channel) -or $channel -ieq 'unknown') { Add-Check 'Activation' 'Warn' 'Activation channel could not be read; the upgrade media requires volume-license (KMS) activation.' }
        else { Add-Check 'Activation' 'Warn' "Activation channel is '$channel'; the upgrade media requires volume-license (KMS) activation. Install the KMS client setup key first." }
    }

    # --- media and engine ----------------------------------------------------------------------

    $mediaOk = $null
    if ($null -ne $Media) {
        $mediaEngine = Get-PropertyOrDefault -InputObject $Target.Engines -Name 'MediaDisk'
        $imageName = if ($mediaEngine) { "$($mediaEngine.publisher)/$($mediaEngine.offer)/$($mediaEngine.sku)" } else { 'upgrade media' }
        if ($Media.Error) {
            $mediaOk = $false
            Add-Check 'MediaImage' 'Fail' "Could not look up $imageName in '$($ArmFacts.Location)': $($Media.Error)"
        }
        elseif ($Media.Version) {
            $mediaOk = $true
            Add-Check 'MediaImage' 'Pass' "$imageName version $($Media.Version) is available in '$($ArmFacts.Location)'."
        }
        else {
            $mediaOk = $false
            Add-Check 'MediaImage' 'Fail' "$imageName is not available in region '$($ArmFacts.Location)'."
        }
    }

    if ($source -and -not $alreadyAtTarget) {
        $candidates = @($source.Engines | Where-Object { $script:ImplementedEngines -contains $_ })
        if ($candidates.Count -eq 0) {
            Add-Check 'Engine' 'Fail' "No implemented engine for this path (listed: $($source.Engines -join ', ')); implemented: $($script:ImplementedEngines -join ', ')."
        }
        elseif ($candidates -contains 'MediaDisk') {
            if ($mediaOk -eq $false) {
                Add-Check 'Engine' 'Fail' 'MediaDisk is the only implemented engine for this path and its upgrade image is unavailable.'
            }
            else {
                $engine = 'MediaDisk'
                if ($null -eq $mediaOk) { Add-Check 'Engine' 'Warn' 'MediaDisk selected; upgrade image availability was not checked.' }
                else { Add-Check 'Engine' 'Pass' 'MediaDisk engine selected.' }
            }
        }
    }

    # --- decision ------------------------------------------------------------------------------

    $failures = @($checks | Where-Object { $_.Result -eq 'Fail' }).Count
    $warnings = @($checks | Where-Object { $_.Result -eq 'Warn' }).Count
    $decision = if ($alreadyAtTarget) { 'AlreadyAtTarget' } elseif ($failures -gt 0) { 'NotEligible' } else { 'Eligible' }

    [pscustomobject]@{
        PSTypeName        = 'AzureInPlaceUpgrade.Readiness'
        VMName            = $ArmFacts.VMName
        ResourceGroupName = $ArmFacts.ResourceGroupName
        Location          = $ArmFacts.Location
        Target            = $Target.Name
        TargetBuild       = $Target.TargetBuild
        SourceBuild       = if ($GuestFacts) { $GuestFacts.Build } else { $null }
        SourceName        = if ($source) { $source.Name } else { $null }
        Edition           = if ($GuestFacts) { $GuestFacts.EditionId } else { $null }
        InstallationType  = if ($GuestFacts) { $GuestFacts.InstallationType } else { $null }
        Language          = if ($GuestFacts) { $GuestFacts.Language } else { $null }
        Engine            = $engine
        MediaImageVersion = if ($Media) { $Media.Version } else { $null }
        Decision          = $decision
        Eligible          = ($decision -eq 'Eligible')
        Failures          = $failures
        Warnings          = $warnings
        Checks            = $checks.ToArray()
        EvaluatedAt       = (Get-Date).ToUniversalTime()
    }
}
