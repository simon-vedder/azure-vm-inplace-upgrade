function Start-InPlaceUpgrade {
    <#
    .SYNOPSIS
    Snapshot one Azure VM, attach the upgrade media and start Windows Setup unattended

    .DESCRIPTION
    The Start half of the state machine (ADR 0003). Runs the preflight, creates an incremental
    snapshot of the OS disk as the rollback point, builds a managed disk from Microsoft's hidden
    upgrade image, attaches it, locates setup.exe inside the guest and starts it through a
    scheduled task running as SYSTEM (ADR 0001). Returns within minutes; the upgrade itself takes
    30 to 120 minutes and several reboots and is finished by Complete-InPlaceUpgrade.

    Tags written: UpgradeState (SnapshotCreated, then UpgradeStarted), UpgradeSnapshot,
    UpgradeEngine, UpgradeMediaDisk (MediaDisk engine only), UpgradeStartedAt (Unix epoch seconds, UTC). On any failure the state becomes Failed, the media disk
    is removed unless -KeepMediaDisk is set, and the snapshot stays.

    Idempotent: a VM already in UpgradeStarted or Completed is skipped, a VM in SnapshotCreated or
    Failed reuses its snapshot, an existing media disk is reused, an attached disk is not attached
    twice and a running Setup is not started again. The install.wim image is always passed
    explicitly (/installfrom, /imageindex), detected from the media's WIM metadata, because
    unattended Setup cannot choose between the Core and Desktop Experience images itself.

    This changes the VM. ConfirmImpact is High, so it prompts unless -Confirm:$false or -Force is
    given; -WhatIf runs the preflight and stops before the snapshot.

    .PARAMETER VM
    The VM object from Get-AzVM or Get-InPlaceUpgradeCandidate. Accepts pipeline input.

    .PARAMETER ResourceGroupName
    Resource group of the VM when -Name is used instead of -VM.

    .PARAMETER Name
    Name of the VM when -ResourceGroupName is used instead of -VM.

    .PARAMETER Target
    Target key from the matrix, for example WS2025. Defaults to the VM's UpgradeTarget tag.

    .PARAMETER Engine
    MediaDisk (default): Microsoft's upgrade media as a managed disk, no network needed, every
    documented source version. FeatureUpdate (experimental): the Windows Server 2025 feature
    update through the Windows Update Agent, WS2019/WS2022 only, needs Windows Update
    reachability; no media disk is created (ADR 0006).

    .PARAMETER MediaDiskResourceGroupName
    Resource group for the media disk. Defaults to the VM's resource group.

    .PARAMETER MediaDiskSkuName
    Storage SKU of the media disk. Standard_LRS is plenty; Setup reads it once.

    .PARAMETER ProductKey
    Explicit key for setup.exe /pkey. Use a public KMS client setup key (GVLK) only; the value
    ends up in the scheduled task definition, visible to every local administrator.

    .PARAMETER UseMatrixProductKey
    Pass the matrix's public KMS client setup key for the guest's edition as /pkey. Rarely needed:
    the 0xC1900215 failure is caused by image selection, not by the key (see KNOWN-ISSUES), and
    is solved by the explicit image index below. Kept for guests whose own key does not validate.

    .PARAMETER TargetImageIndex
    Override the install.wim image index for setup.exe /installfrom and /imageindex. By default
    the index is detected from the WIM metadata by matching the guest's edition and installation
    type; an override is refused when the index does not exist on the media.

    .PARAMETER MinimumFreeSpaceGB
    Free space required on C: by the preflight.

    .PARAMETER Force
    Proceed although the preflight reports NotEligible, and suppress the confirmation prompt.
    AlreadyAtTarget is never overridden.

    .PARAMETER KeepMediaDisk
    Keep the media disk when Start fails. Useful when debugging a Setup that dies immediately.

    .PARAMETER LogIngestionEndpoint
    Logs ingestion endpoint of a data collection endpoint (https://...ingest.monitor.azure.com).
    Together with -DataCollectionRuleId, every state transition is written to the
    InPlaceUpgrade_CL table. Empty means no telemetry.

    .PARAMETER DataCollectionRuleId
    Immutable id (dcr-...) of the data collection rule that routes Custom-InPlaceUpgrade_CL.

    .EXAMPLE
    # Start the upgrade of one tagged VM interactively (prompts before the snapshot)
    Start-InPlaceUpgrade -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01

    .EXAMPLE
    # Start everything that is approved for Ring0, no prompts, with the matrix product key
    Get-InPlaceUpgradeCandidate -Ring Ring0 | Start-InPlaceUpgrade -UseMatrixProductKey -Confirm:$false

    .EXAMPLE
    # Preflight and plan only
    Start-InPlaceUpgrade -ResourceGroupName rg-apps-prod-weu -Name vm-app-prod-weu-01 -WhatIf

    .INPUTS
    Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine

    .OUTPUTS
    AzureInPlaceUpgrade.StartResult

    .NOTES
    Author:              Simon Vedder (simonvedder.com)
    Version:             0.1.0
    Created:             2026-09-05
    LastModified:        2026-09-05
    RequiredPermissions: Microsoft.Compute/virtualMachines/read, write, instanceView/read, runCommand/action;
                         Microsoft.Compute/disks/read, write, delete; Microsoft.Compute/snapshots/read, write;
                         Microsoft.Compute/locations/publishers/artifacttypes/offers/skus/versions/read;
                         Microsoft.Resources/tags/write; Microsoft.Resources/subscriptions/resourceGroups/read
                         (a custom role with exactly these actions ships with the Bicep deployment)
    Prerequisites:       PowerShell 7.2+, Az.Compute, Az.Resources; a healthy Azure Guest Agent in the VM; an established Azure context

    .LINK
    https://github.com/simon-vedder/azure-vm-inplace-upgrade
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByObject')]
    [OutputType('AzureInPlaceUpgrade.StartResult')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
        $VM,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$ResourceGroupName,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter()]
        [string]$Target,

        [Parameter()]
        [ValidateSet('MediaDisk', 'FeatureUpdate')]
        [string]$Engine = 'MediaDisk',

        [Parameter()]
        [string]$MediaDiskResourceGroupName,

        [Parameter()]
        [ValidateSet('Standard_LRS', 'StandardSSD_LRS', 'Premium_LRS')]
        [string]$MediaDiskSkuName = 'Standard_LRS',

        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9]{5}(-[A-Za-z0-9]{5}){4}$')]
        [string]$ProductKey,

        [Parameter()]
        [switch]$UseMatrixProductKey,

        [Parameter()]
        [ValidateRange(1, 99)]
        [int]$TargetImageIndex,

        [Parameter()]
        [ValidateRange(10, 200)]
        [int]$MinimumFreeSpaceGB = 30,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$KeepMediaDisk,

        [Parameter()]
        [string]$LogIngestionEndpoint,

        [Parameter()]
        [string]$DataCollectionRuleId
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $Name -ErrorAction Stop
        }
        $vmName = [string]$VM.Name
        $rg = [string]$VM.ResourceGroupName

        $targetName = if ($Target) { $Target } else { Get-VMTagValue -VM $VM -Name $script:Tag.Target }
        if (-not $targetName) { throw "VM '$vmName' has no '$($script:Tag.Target)' tag and no -Target was given." }
        $targetObject = Get-InPlaceUpgradeTarget -Name $targetName
        $targetName = $targetObject.Name

        # Captured for the nested helpers below; the analyzer cannot see parameter use inside them.
        $logEndpoint = $LogIngestionEndpoint
        $logRuleId = $DataCollectionRuleId
        $readiness = $null
        $snapshotName = $null
        $mediaDiskRg = if ($MediaDiskResourceGroupName) { $MediaDiskResourceGroupName } else { $rg }
        $mediaDiskName = Get-UpgradeMediaDiskName -VMName $vmName -Target $targetName
        $setupPath = $null
        $startedAt = $null

        function Write-StartRecord {
            param([string]$State, [string]$Result, [string]$Reason, [nullable[int]]$ImageIndex)
            $record = ConvertTo-UpgradeRecord -VMName $vmName -ResourceGroupName $rg -State $State -Result $Result -Reason $Reason `
                -Target $targetName -Engine $Engine -TargetBuild $targetObject.TargetBuild `
                -SourceBuild $(if ($readiness) { $readiness.SourceBuild } else { $null }) -ImageIndex $ImageIndex `
                -Snapshot $(if ($snapshotName) { $snapshotName } else { '' }) -MediaDisk $(if ($snapshotName -and $Engine -eq 'MediaDisk') { "$mediaDiskRg/$mediaDiskName" } else { '' }) -Mode 'Start'
            $null = Write-UpgradeRecord -Record $record -LogIngestionEndpoint $logEndpoint -DataCollectionRuleId $logRuleId
        }

        function ConvertTo-StartResult {
            param([string]$Result, [string]$Reason)
            [pscustomobject]@{
                PSTypeName        = 'AzureInPlaceUpgrade.StartResult'
                VMName            = $vmName
                ResourceGroupName = $rg
                Target            = $targetName
                Engine            = $Engine
                Result            = $Result
                Reason            = $Reason
                Snapshot          = $snapshotName
                MediaDisk         = if ($snapshotName -and $Engine -eq 'MediaDisk') { "$mediaDiskRg/$mediaDiskName" } else { $null }
                SetupPath         = $setupPath
                StartedAt         = $startedAt
                Readiness         = $readiness
            }
        }

        $state = Get-VMTagValue -VM $VM -Name $script:Tag.State
        if ($state -ieq $script:State.UpgradeStarted) {
            return ConvertTo-StartResult 'Skipped' "VM is already in state $($script:State.UpgradeStarted); evaluate it with Complete-InPlaceUpgrade."
        }
        if ($state -ieq $script:State.Completed) {
            return ConvertTo-StartResult 'Skipped' "VM is in state $($script:State.Completed); set $($script:Tag.State)=Pending to run again."
        }

        Write-Verbose "[$vmName] Running the preflight."
        $readiness = Test-InPlaceUpgradeReadiness -VM $VM -Target $targetName -MinimumFreeSpaceGB $MinimumFreeSpaceGB
        if ($readiness.Decision -eq 'AlreadyAtTarget') {
            return ConvertTo-StartResult 'Skipped' "Guest already runs build $($readiness.SourceBuild); nothing to do."
        }
        if ($readiness.Decision -eq 'NotEligible') {
            $failed = ($readiness.Checks | Where-Object { $_.Result -eq 'Fail' } | ForEach-Object { "$($_.Name): $($_.Detail)" }) -join ' | '
            if (-not $Force) {
                Write-StartRecord -State $script:State.Pending -Result 'NotEligible' -Reason $failed
                return ConvertTo-StartResult 'NotEligible' $failed
            }
            Write-Warning "[$vmName] Proceeding despite failed preflight checks (-Force): $failed"
        }
        elseif ($Engine -eq 'FeatureUpdate') {
            $source = $targetObject.Sources | Where-Object { $_.Build -eq $readiness.SourceBuild } | Select-Object -First 1
            if (-not $source -or $source.Engines -notcontains 'FeatureUpdate') {
                return ConvertTo-StartResult 'NotEligible' "The FeatureUpdate engine is not available for build $($readiness.SourceBuild) to $targetName; use MediaDisk."
            }
        }
        elseif ($readiness.Engine -ne $Engine -and -not $Force) {
            return ConvertTo-StartResult 'NotEligible' "The preflight selected engine '$($readiness.Engine)', not '$Engine'."
        }

        $effectiveKey = $null
        if ($ProductKey) { $effectiveKey = $ProductKey }
        elseif ($UseMatrixProductKey) {
            $edition = ([string]$readiness.Edition) -replace '(Cor|Core)$', ''
            $effectiveKey = Get-PropertyOrDefault -InputObject $targetObject.ProductKeys -Name $edition
            if (-not $effectiveKey) { throw "The matrix has no product key for edition '$edition' of $targetName." }
            Write-Verbose "[$vmName] Using the matrix KMS client setup key for edition $edition."
        }

        $mediaEngine = Get-PropertyOrDefault -InputObject $targetObject.Engines -Name 'MediaDisk'
        $featureEngine = Get-PropertyOrDefault -InputObject $targetObject.Engines -Name 'FeatureUpdate'
        if ($Engine -eq 'MediaDisk' -and -not $mediaEngine) { throw "Target $targetName has no MediaDisk engine in the matrix." }
        if ($Engine -eq 'FeatureUpdate' -and -not $featureEngine) { throw "Target $targetName has no FeatureUpdate engine in the matrix." }

        $action = if ($Engine -eq 'FeatureUpdate') { "Snapshot the OS disk and start the Windows Update feature update to $($targetObject.DisplayName)" }
        else { "Snapshot the OS disk, attach upgrade media $($mediaEngine.sku) and start Windows Setup to $($targetObject.DisplayName)" }
        if ($Force) { $ConfirmPreference = 'None' }
        if (-not $PSCmdlet.ShouldProcess($vmName, $action)) {
            return ConvertTo-StartResult 'Skipped' 'WhatIf: preflight passed, nothing changed.'
        }

        $tagState = $script:Tag.State
        $tagSnapshot = $script:Tag.Snapshot
        $tagMediaDisk = $script:Tag.MediaDisk
        $tagStartedAt = $script:Tag.StartedAt
        $tagEngine = $script:Tag.Engine

        try {
            $existingSnapshot = Get-VMTagValue -VM $VM -Name $tagSnapshot
            # A retry after SnapshotCreated or Failed keeps the snapshot of the state before the
            # first attempt; that is the cleaner rollback point and saves a copy.
            if ($state -in @($script:State.SnapshotCreated, $script:State.Failed) -and $existingSnapshot -and
                (Get-AzSnapshot -ResourceGroupName $rg -SnapshotName $existingSnapshot -ErrorAction SilentlyContinue)) {
                $snapshotName = $existingSnapshot
                Write-Verbose "[$vmName] Reusing snapshot '$snapshotName' from the previous attempt."
            }
            else {
                Write-Verbose "[$vmName] Creating the OS disk snapshot."
                $snapshotName = (New-VMOSSnapshot -VM $VM -Target $targetName).Name
                Write-Verbose "[$vmName] Snapshot '$snapshotName' created."
            }
            Set-UpgradeTag -ResourceId $VM.Id -Tag @{ $tagState = $script:State.SnapshotCreated; $tagSnapshot = $snapshotName; $tagEngine = $Engine }
            Write-StartRecord -State $script:State.SnapshotCreated -Result 'SnapshotCreated' -Reason "Snapshot $snapshotName"

            if ($Engine -eq 'FeatureUpdate') {
                $launch = Start-GuestFeatureUpdate -ResourceGroupName $rg -VMName $vmName -FeatureUpdateEngine $featureEngine
                if (-not $launch.Started) { throw $launch.Reason }
                Write-Verbose "[$vmName] $($launch.Reason) $($launch.Raw)"

                $startedAt = (Get-Date).ToUniversalTime()
                Set-UpgradeTag -ResourceId $VM.Id -Tag @{ $tagState = $script:State.UpgradeStarted; $tagStartedAt = (ConvertTo-TagTimestamp -Value $startedAt) }
                Write-StartRecord -State $script:State.UpgradeStarted -Result 'Started' -Reason $launch.Reason
                return ConvertTo-StartResult 'Started' $launch.Reason
            }

            $disk = New-UpgradeMediaDisk -VM $VM -DiskName $mediaDiskName -DiskResourceGroupName $mediaDiskRg -MediaEngine $mediaEngine -SkuName $MediaDiskSkuName
            Set-UpgradeTag -ResourceId $VM.Id -Tag @{ $tagMediaDisk = "$mediaDiskRg/$mediaDiskName" }
            $lun = Add-UpgradeMediaDisk -VM $VM -Disk $disk
            Write-Verbose "[$vmName] Media disk on LUN $lun."

            $media = Resolve-GuestSetupPath -ResourceGroupName $rg -VMName $vmName
            if (-not $media.Success) { throw $media.Reason }
            $setupPath = $media.SetupPath
            Write-Verbose "[$vmName] Upgrade media at '$setupPath'."

            # Unattended Setup cannot choose between the Core and Desktop Experience images of the
            # same edition and aborts with 0xC1900215; the image is therefore always named
            # explicitly, detected from the WIM metadata unless -TargetImageIndex overrides it.
            $wim = Get-GuestWimImage -ResourceGroupName $rg -VMName $vmName -SetupPath $setupPath
            if ($wim.Error) { throw $wim.Error }
            $imageIndex = $TargetImageIndex
            if ($imageIndex -gt 0) {
                $chosen = $wim.Images | Where-Object { $_.Index -eq $imageIndex } | Select-Object -First 1
                if (-not $chosen) { throw "-TargetImageIndex $imageIndex does not exist in '$($wim.WimPath)'. Images: $(($wim.Images | ForEach-Object { "$($_.Index)=$($_.Name)" }) -join ', ')" }
                Write-Verbose "[$vmName] Using image $imageIndex '$($chosen.Name)' as requested."
            }
            else {
                $imageIndex = Select-UpgradeImageIndex -Image $wim.Images -EditionId $readiness.Edition -InstallationType $readiness.InstallationType
                if (-not $imageIndex) {
                    throw "No single image in '$($wim.WimPath)' matches edition '$($readiness.Edition)' with installation type '$($readiness.InstallationType)'. Images: $(($wim.Images | ForEach-Object { "$($_.Index)=$($_.Name) [$($_.EditionId)/$($_.InstallationType)]" }) -join ', '). Pass -TargetImageIndex explicitly."
                }
                $chosen = $wim.Images | Where-Object { $_.Index -eq $imageIndex } | Select-Object -First 1
                Write-Verbose "[$vmName] Image $imageIndex '$($chosen.Name)' matches $($readiness.Edition) / $($readiness.InstallationType)."
            }

            $launch = Start-GuestSetup -ResourceGroupName $rg -VMName $vmName -SetupPath $setupPath -ProductKey $effectiveKey -TargetImageIndex $imageIndex -InstallFrom $wim.WimPath
            if (-not $launch.Started) { throw $launch.Reason }
            Write-Verbose "[$vmName] $($launch.Reason) $($launch.Raw)"

            $startedAt = (Get-Date).ToUniversalTime()
            Set-UpgradeTag -ResourceId $VM.Id -Tag @{ $tagState = $script:State.UpgradeStarted; $tagStartedAt = (ConvertTo-TagTimestamp -Value $startedAt) }
            Write-StartRecord -State $script:State.UpgradeStarted -Result 'Started' -Reason $launch.Reason -ImageIndex $imageIndex

            return ConvertTo-StartResult 'Started' $launch.Reason
        }
        catch {
            $reason = $_.Exception.Message
            Write-Verbose "[$vmName] Start failed: $reason"
            try { Set-UpgradeTag -ResourceId $VM.Id -Tag @{ $tagState = $script:State.Failed } }
            catch { Write-Warning "[$vmName] Could not set $tagState=Failed: $($_.Exception.Message)" }
            Write-StartRecord -State $script:State.Failed -Result 'Failed' -Reason $reason

            if (-not $KeepMediaDisk -and $Engine -eq 'MediaDisk') {
                $cleanup = Remove-UpgradeMediaDisk -ResourceGroupName $rg -VMName $vmName -DiskResourceGroupName $mediaDiskRg -DiskName $mediaDiskName
                if (-not $cleanup.Removed) { Write-Warning "[$vmName] Media disk cleanup failed: $($cleanup.Error)" }
            }
            return ConvertTo-StartResult 'Failed' $reason
        }
    }
}
