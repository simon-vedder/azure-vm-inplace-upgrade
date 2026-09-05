#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $manifestPath = Join-Path $PSScriptRoot '..' 'src' 'AzureInPlaceUpgrade' 'AzureInPlaceUpgrade.psd1'
    Import-Module $manifestPath -Force -ErrorAction Stop
    $module = Get-Module AzureInPlaceUpgrade

    # Private functions are fetched from the module scope once. Invoking the FunctionInfo runs the
    # body inside the module, so $script: variables resolve as they do in production.
    $Private = & $module {
        @{
            Resolve      = Get-Command Resolve-InPlaceUpgradeReadiness
            ConvertFacts = Get-Command ConvertFrom-GuestFacts
            ArmFacts     = Get-Command Get-VMArmFacts
            CandidateTag = Get-Command Test-CandidateTag
            TagValue     = Get-Command Get-VMTagValue
            GuestResult  = Get-Command ConvertFrom-GuestResult
            HideKey      = Get-Command Hide-ProductKey
            MediaName    = Get-Command Get-UpgradeMediaDiskName
            Completion   = Get-Command Resolve-UpgradeCompletion
            GuestScript  = Get-Command Get-GuestScript
            ToStamp      = Get-Command ConvertTo-TagTimestamp
            FromStamp    = Get-Command ConvertFrom-TagTimestamp
            WimParse     = Get-Command ConvertFrom-GuestWimImage
            SelectImage  = Get-Command Select-UpgradeImageIndex
        }
    }

    function New-GuestFacts {
        param([hashtable]$Override = @{})
        $facts = @{
            Build                 = 20348
            ProductName           = 'Windows Server 2022 Datacenter'
            EditionId             = 'ServerDatacenter'
            InstallationType      = 'Server'
            DisplayVersion        = '21H2'
            Architecture          = '64-bit'
            Language              = 'en-US'
            FreeGB                = 80.5
            PendingReboot         = $false
            DomainRole            = 3
            ClusterServicePresent = $false
            ActivationChannel     = 'Volume:GVLK'
            LicenseStatus         = 1
            SetupRunning          = $false
        }
        foreach ($key in $Override.Keys) { $facts[$key] = $Override[$key] }
        [pscustomobject]$facts
    }

    function New-ArmFacts {
        param([hashtable]$Override = @{})
        $facts = @{
            VMName            = 'vm-test-01'
            ResourceGroupName = 'rg-test'
            Location          = 'westeurope'
            Zone              = $null
            PowerState        = 'running'
            OsType            = 'Windows'
            OsDiskManaged     = $true
            OsDiskEphemeral   = $false
            SecurityType      = $null
        }
        foreach ($key in $Override.Keys) { $facts[$key] = $Override[$key] }
        [pscustomobject]$facts
    }

    function New-FakeVM {
        param([hashtable]$Tags = @{}, [string]$Name = 'vm-test-01')
        [pscustomobject]@{ Name = $Name; ResourceGroupName = 'rg-test'; Location = 'westeurope'; Tags = $Tags }
    }

    $Target2025 = Get-InPlaceUpgradeTarget -Name WS2025
    $MediaPresent = [pscustomobject]@{ Checked = $true; Version = '26100.4652.250712'; Error = $null }
    $MediaMissing = [pscustomobject]@{ Checked = $true; Version = $null; Error = $null }
    $MediaError = [pscustomobject]@{ Checked = $true; Version = $null; Error = 'AuthorizationFailed' }

    function Get-Check {
        param($Readiness, [string]$Name)
        $Readiness.Checks | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    }
}

Describe 'Module' {
    It 'has a valid manifest' {
        Test-ModuleManifest -Path $manifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly the public functions' {
        $exported = @((Get-Module AzureInPlaceUpgrade).ExportedFunctions.Keys | Sort-Object)
        $exported | Should -Be @('Complete-InPlaceUpgrade', 'Get-InPlaceUpgradeCandidate', 'Get-InPlaceUpgradeTarget', 'Invoke-InPlaceUpgrade', 'Start-InPlaceUpgrade', 'Test-InPlaceUpgradeReadiness')
    }

    It 'keeps every guest script free of PowerShell 7 syntax (<_>)' -ForEach @('Facts', 'SetupPath', 'WimImages', 'Launch', 'Status', 'LogTail', 'RemoveTask') {
        $script = & $Private.GuestScript -Name $_
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        $script | Should -Not -Match '\?\?'          # null-coalescing
        $script | Should -Not -Match '\?\.'          # null-conditional
        $script | Should -Not -Match '\s\?\s.*\s:\s' # ternary
        $script | Should -Not -Match '&&|\|\|'       # pipeline chain operators
    }
}

Describe 'Target matrix' {
    BeforeAll { $targets = @(Get-InPlaceUpgradeTarget) }

    It 'lists WS2019, WS2022 and WS2025' {
        @($targets.Name | Sort-Object) | Should -Be @('WS2019', 'WS2022', 'WS2025')
    }

    It 'every source build is lower than its target build' {
        foreach ($target in $targets) {
            foreach ($source in $target.Sources) { $source.Build | Should -BeLessThan $target.TargetBuild }
        }
    }

    It 'only references known engines' {
        foreach ($target in $targets) {
            foreach ($source in $target.Sources) {
                foreach ($engine in $source.Engines) { $engine | Should -BeIn @('MediaDisk', 'FeatureUpdate') }
            }
        }
    }

    It 'has a media SKU that matches the target year' {
        foreach ($target in $targets) {
            $year = $target.DisplayName.Split(' ')[-1]
            $target.Engines.MediaDisk.sku | Should -Be "server${year}Upgrade"
            $target.Engines.MediaDisk.publisher | Should -Be 'MicrosoftWindowsServer'
            $target.Engines.MediaDisk.offer | Should -Be 'WindowsServerUpgrade'
        }
    }

    It 'has a public KMS client key for every allowed edition' {
        foreach ($target in $targets) {
            foreach ($edition in $target.Editions) {
                $target.ProductKeys.$edition | Should -Match '^([A-Z0-9]{5}-){4}[A-Z0-9]{5}$'
            }
        }
    }

    It 'names the required update for every FeatureUpdate source' {
        $ws2025 = $targets | Where-Object Name -eq 'WS2025'
        foreach ($source in ($ws2025.Sources | Where-Object { $_.Engines -contains 'FeatureUpdate' })) {
            $ws2025.Engines.FeatureUpdate.requiredUpdates.($source.Build.ToString()) | Should -Match '^KB\d{7}$'
        }
    }

    It 'carries a boolean verified flag per source' {
        foreach ($target in $targets) {
            foreach ($source in $target.Sources) { $source.Verified | Should -BeOfType [bool] }
        }
    }
}

Describe 'Get-InPlaceUpgradeTarget' {
    It 'resolves a name case-insensitively' {
        (Get-InPlaceUpgradeTarget -Name ws2025).Name | Should -Be 'WS2025'
    }

    It 'throws on an unknown target and lists the known ones' {
        { Get-InPlaceUpgradeTarget -Name WS2030 } | Should -Throw '*Known targets*WS2025*'
    }

    It 'accepts 2012 R2, 2016, 2019 and 2022 as sources for WS2025' {
        @((Get-InPlaceUpgradeTarget -Name WS2025).Sources.Build) | Should -Be @(9600, 14393, 17763, 20348)
    }

    It 'filters by source build and attaches the matching source' {
        $result = @(Get-InPlaceUpgradeTarget -SourceBuild 20348)
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'WS2025'
        $result[0].Source.Name | Should -Be 'Windows Server 2022'
    }

    It 'lets Windows Server 2016 go to 2019, 2022 and 2025' {
        @((Get-InPlaceUpgradeTarget -SourceBuild 14393).Name | Sort-Object) | Should -Be @('WS2019', 'WS2022', 'WS2025')
    }

    It 'returns nothing for a build that is only ever a target' {
        @(Get-InPlaceUpgradeTarget -SourceBuild 26100).Count | Should -Be 0
    }
}

Describe 'Tag selection (Test-CandidateTag)' {
    It 'selects a VM with a target and the expected state' {
        $vm = New-FakeVM -Tags @{ UpgradeTarget = 'WS2025'; UpgradeState = 'Pending' }
        & $Private.CandidateTag -VM $vm -State 'Pending' | Should -BeTrue
    }

    It 'rejects a VM without an UpgradeTarget tag' {
        $vm = New-FakeVM -Tags @{ UpgradeState = 'Pending' }
        & $Private.CandidateTag -VM $vm -State 'Pending' | Should -BeFalse
    }

    It 'rejects a VM in a different state' {
        $vm = New-FakeVM -Tags @{ UpgradeTarget = 'WS2025'; UpgradeState = 'Completed' }
        & $Private.CandidateTag -VM $vm -State 'Pending' | Should -BeFalse
    }

    It 'requires the state tag to exist when a state filter is given' {
        $vm = New-FakeVM -Tags @{ UpgradeTarget = 'WS2025' }
        & $Private.CandidateTag -VM $vm -State 'Pending' | Should -BeFalse
    }

    It 'accepts any state when the state filter is empty' {
        $vm = New-FakeVM -Tags @{ UpgradeTarget = 'WS2025' }
        & $Private.CandidateTag -VM $vm -State '' | Should -BeTrue
    }

    It 'matches tag names and values case-insensitively and trims whitespace' {
        $vm = New-FakeVM -Tags @{ upgradetarget = ' ws2025 '; UPGRADESTATE = 'pending' }
        & $Private.CandidateTag -VM $vm -Target 'WS2025' -State 'Pending' | Should -BeTrue
    }

    It 'filters by ring' {
        $vm = New-FakeVM -Tags @{ UpgradeTarget = 'WS2025'; UpgradeState = 'Pending'; UpgradeRing = 'Ring1' }
        & $Private.CandidateTag -VM $vm -State 'Pending' -Ring 'Ring0' | Should -BeFalse
        & $Private.CandidateTag -VM $vm -State 'Pending' -Ring 'Ring1' | Should -BeTrue
    }

    It 'treats a VM without tags as not selected' {
        $vm = New-FakeVM -Tags @{}
        & $Private.CandidateTag -VM $vm | Should -BeFalse
        (& $Private.TagValue -VM ([pscustomobject]@{ Name = 'x' }) -Name 'UpgradeTarget') | Should -BeNullOrEmpty
    }
}

Describe 'Get-InPlaceUpgradeCandidate (Get-AzVM mocked)' {
    BeforeAll {
        Mock -ModuleName AzureInPlaceUpgrade Get-AzVM {
            $all = @(
                (New-FakeVM -Name 'vm-pending' -Tags @{ UpgradeTarget = 'WS2025'; UpgradeState = 'Pending' })
                (New-FakeVM -Name 'vm-done' -Tags @{ UpgradeTarget = 'WS2025'; UpgradeState = 'Completed' })
                (New-FakeVM -Name 'vm-untagged' -Tags @{})
            )
            if ($Name) { return ($all | Where-Object Name -eq $Name) }
            return $all
        }
    }

    It 'returns the single matching VM as one object, not nothing (regression: if-statement unrolling)' {
        $result = @(Get-InPlaceUpgradeCandidate -ResourceGroupName 'rg-test')
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'vm-pending'
    }

    It 'returns every tagged VM when the state filter is empty' {
        @(Get-InPlaceUpgradeCandidate -ResourceGroupName 'rg-test' -State '').Name | Sort-Object | Should -Be @('vm-done', 'vm-pending')
    }

    It 'returns an untagged VM only with -Name and -IgnoreTags' {
        @(Get-InPlaceUpgradeCandidate -ResourceGroupName 'rg-test' -Name 'vm-untagged').Count | Should -Be 0
        @(Get-InPlaceUpgradeCandidate -ResourceGroupName 'rg-test' -Name 'vm-untagged' -IgnoreTags).Name | Should -Be 'vm-untagged'
    }

    It 'refuses -IgnoreTags without -Name and -Name without a resource group' {
        { Get-InPlaceUpgradeCandidate -IgnoreTags } | Should -Throw '*only allowed together with -Name*'
        { Get-InPlaceUpgradeCandidate -Name 'vm-x' } | Should -Throw '*requires -ResourceGroupName*'
    }
}

Describe 'Guest result parsing (ConvertFrom-GuestResult)' {
    It 'parses RESULT=OK;SETUP=path' {
        $r = & $Private.GuestResult -Output "noise`nRESULT=OK;SETUP=F:\\WindowsServer2025\\setup.exe"
        $r.Result | Should -Be 'OK'
        $r.Values['SETUP'] | Should -Be 'F:\\WindowsServer2025\\setup.exe'
    }

    It 'parses a NOTFOUND diagnostic with pipe-separated listing' {
        $r = & $Private.GuestResult -Output 'RESULT=NOTFOUND;DISKS=#0:Online:GPT,#1:Online:MBR;LISTING=D[Temp]:a,b|E[Media]:x'
        $r.Result | Should -Be 'NOTFOUND'
        $r.Values['LISTING'] | Should -Be 'D[Temp]:a,b|E[Media]:x'
        $r.Raw | Should -Match '^RESULT=NOTFOUND'
    }

    It 'returns null without a RESULT line' {
        & $Private.GuestResult -Output 'just text' | Should -BeNullOrEmpty
    }
}

Describe 'Helpers' {
    It 'masks a product key in setup arguments' {
        & $Private.HideKey -Text '/auto upgrade /pkey D764K-2NDRG-47T6Q-P8T8W-YP6DF /quiet' | Should -Be '/auto upgrade /pkey ***** /quiet'
        & $Private.HideKey -Text '/auto upgrade /quiet' | Should -Be '/auto upgrade /quiet'
    }

    It 'round-trips a tag timestamp through epoch seconds' {
        $at = [datetime]::new(2026, 9, 5, 8, 25, 45, [System.DateTimeKind]::Utc)
        $stamp = & $Private.ToStamp -Value $at
        $stamp | Should -Match '^\d+$'
        (& $Private.FromStamp -Value $stamp) | Should -Be $at
    }

    It 'still reads ISO and the Az-mangled invariant form as UTC' {
        (& $Private.FromStamp -Value '2026-09-05T08:25:45.6700170Z').ToString('u') | Should -Be '2026-09-05 08:25:45Z'
        (& $Private.FromStamp -Value '09/05/2026 08:25:45').ToString('u') | Should -Be '2026-09-05 08:25:45Z'
        & $Private.FromStamp -Value 'yesterday' | Should -BeNullOrEmpty
        & $Private.FromStamp -Value '' | Should -BeNullOrEmpty
    }

    It 'derives a stable media disk name' {
        & $Private.MediaName -VMName 'vm-a' -Target 'WS2025' | Should -Be 'vm-a-upgrademedia-ws2025'
    }
}

Describe 'Completion rules (Resolve-UpgradeCompletion)' {
    BeforeAll {
        $now = [datetime]::new(2026, 9, 5, 12, 0, 0, [System.DateTimeKind]::Utc)
        $fresh = $now.AddMinutes(-30)
        $stale = $now.AddMinutes(-300)
        function New-Status {
            param([hashtable]$Override = @{})
            $s = @{ Build = 20348; ProductName = 'Windows Server 2022 Datacenter'; DisplayVersion = '21H2'; SetupRunning = $false; TaskState = 'Ready'; TaskResult = [uint32]0 }
            foreach ($k in $Override.Keys) { $s[$k] = $Override[$k] }
            [pscustomobject]$s
        }
    }

    It 'is Completed when the guest reports the target build' {
        $d = & $Private.Completion -Target $Target2025 -PowerState running -Status (New-Status @{ Build = 26100; ProductName = 'Windows Server 2025 Datacenter' }) -StartedAt $fresh -Now $now
        $d.Result | Should -Be 'Completed'
        $d.Reason | Should -Match '26100'
    }

    It 'fails a stopped or deallocated VM' {
        (& $Private.Completion -Target $Target2025 -PowerState deallocated -Status $null -StartedAt $fresh -Now $now).Result | Should -Be 'Failed'
        (& $Private.Completion -Target $Target2025 -PowerState stopped -Status $null -StartedAt $fresh -Now $now).Result | Should -Be 'Failed'
    }

    It 'treats an unreachable guest as rebooting until the timeout' {
        (& $Private.Completion -Target $Target2025 -PowerState running -Status $null -StartedAt $fresh -Now $now).Result | Should -Be 'InProgress'
        $d = & $Private.Completion -Target $Target2025 -PowerState running -Status $null -StartedAt $stale -Now $now
        $d.Result | Should -Be 'Failed'
        $d.Expired | Should -BeTrue
        $d.AgeMinutes | Should -Be 300
    }

    It 'keeps waiting while Setup runs, until the timeout' {
        (& $Private.Completion -Target $Target2025 -PowerState running -Status (New-Status @{ SetupRunning = $true }) -StartedAt $fresh -Now $now).Result | Should -Be 'InProgress'
        (& $Private.Completion -Target $Target2025 -PowerState running -Status (New-Status @{ TaskState = 'Running' }) -StartedAt $fresh -Now $now).Result | Should -Be 'InProgress'
        (& $Private.Completion -Target $Target2025 -PowerState running -Status (New-Status @{ SetupRunning = $true }) -StartedAt $stale -Now $now).Result | Should -Be 'Failed'
    }

    It 'fails on a Setup HRESULT and flags the task failure' {
        $d = & $Private.Completion -Target $Target2025 -PowerState running -Status (New-Status @{ TaskResult = [uint32]::Parse('C1900215', [System.Globalization.NumberStyles]::HexNumber) }) -StartedAt $fresh -Now $now
        $d.Result | Should -Be 'Failed'
        $d.TaskFailed | Should -BeTrue
        $d.Reason | Should -Match '0xC1900215'
    }

    It 'fails on a plain exit code 1' {
        (& $Private.Completion -Target $Target2025 -PowerState running -Status (New-Status @{ TaskResult = [uint32]1 }) -StartedAt $fresh -Now $now).Result | Should -Be 'Failed'
    }

    It 'does not treat Task Scheduler status codes as failures' {
        foreach ($code in @(0x41301, 0x41303, 0x41306)) {
            $d = & $Private.Completion -Target $Target2025 -PowerState running -Status (New-Status @{ TaskResult = [uint32]$code }) -StartedAt $fresh -Now $now
            $d.Result | Should -Be 'InProgress'
            $d.TaskFailed | Should -BeFalse
        }
    }

    It 'waits on the old build with a clean task until the timeout' {
        (& $Private.Completion -Target $Target2025 -PowerState running -Status (New-Status) -StartedAt $fresh -Now $now).Result | Should -Be 'InProgress'
        (& $Private.Completion -Target $Target2025 -PowerState running -Status (New-Status) -StartedAt $stale -Now $now).Result | Should -Be 'Failed'
    }

    It 'never expires without a start timestamp' {
        $d = & $Private.Completion -Target $Target2025 -PowerState running -Status (New-Status) -StartedAt $null -Now $now
        $d.Result | Should -Be 'InProgress'
        $d.Expired | Should -BeFalse
        $d.AgeMinutes | Should -BeNullOrEmpty
    }
}

Describe 'Image selection (Select-UpgradeImageIndex)' {
    BeforeAll {
        # The four images of the server2025Upgrade media, as listed live on 2026-09-05.
        $wimLine = 'IPU-IMAGES={"WimPath":"E:\\Windows Server 2025\\sources\\install.wim","Images":[{"Index":1,"Name":"Windows Server 2025 Standard","EditionId":"ServerStandard","InstallationType":"Server Core","Version":"10.0.26100.33296"},{"Index":2,"Name":"Windows Server 2025 Standard (Desktop Experience)","EditionId":"ServerStandard","InstallationType":"Server","Version":"10.0.26100.33296"},{"Index":3,"Name":"Windows Server 2025 Datacenter","EditionId":"ServerDatacenter","InstallationType":"Server Core","Version":"10.0.26100.33296"},{"Index":4,"Name":"Windows Server 2025 Datacenter (Desktop Experience)","EditionId":"ServerDatacenter","InstallationType":"Server","Version":"10.0.26100.33296"}]}'
        $wim = & $Private.WimParse -Output ("noise`n" + $wimLine)
    }

    It 'parses the guest image list' {
        $wim.Error | Should -BeNullOrEmpty
        $wim.WimPath | Should -Be 'E:\Windows Server 2025\sources\install.wim'
        $wim.Images.Count | Should -Be 4
        $wim.Images[3].Index | Should -Be 4
        $wim.Images[3].InstallationType | Should -Be 'Server'
    }

    It 'returns an error object when the marker is missing' {
        (& $Private.WimParse -Output 'nothing').Error | Should -Match 'no image list'
    }

    It 'picks Datacenter Desktop Experience for a Datacenter Server guest' {
        & $Private.SelectImage -Image $wim.Images -EditionId 'ServerDatacenter' -InstallationType 'Server' | Should -Be 4
    }

    It 'picks the Core image for a Server Core guest, also with a Cor edition suffix' {
        & $Private.SelectImage -Image $wim.Images -EditionId 'ServerDatacenter' -InstallationType 'Server Core' | Should -Be 3
        & $Private.SelectImage -Image $wim.Images -EditionId 'ServerStandardCor' -InstallationType 'Server Core' | Should -Be 1
    }

    It 'refuses to guess when nothing or more than one image matches' {
        & $Private.SelectImage -Image $wim.Images -EditionId 'ServerDatacenterAzureEdition' -InstallationType 'Server' | Should -BeNullOrEmpty
        $twice = @($wim.Images[3], $wim.Images[3])
        & $Private.SelectImage -Image $twice -EditionId 'ServerDatacenter' -InstallationType 'Server' | Should -BeNullOrEmpty
        & $Private.SelectImage -Image @() -EditionId 'ServerDatacenter' -InstallationType 'Server' | Should -BeNullOrEmpty
    }
}

Describe 'Guest output parsing (ConvertFrom-GuestFacts)' {
    It 'finds the facts line among other output' {
        $json = (New-GuestFacts) | ConvertTo-Json -Compress
        $output = "WARNING: something`nIPU-FACTS=$json`ntrailing noise"
        $facts = & $Private.ConvertFacts -Output $output
        $facts.Build | Should -Be 20348
        $facts.EditionId | Should -Be 'ServerDatacenter'
        $facts.FreeGB | Should -Be 80.5
        $facts.PendingReboot | Should -BeFalse
    }

    It 'returns null when the marker is missing' {
        & $Private.ConvertFacts -Output 'no facts here' | Should -BeNullOrEmpty
        & $Private.ConvertFacts -Output '' | Should -BeNullOrEmpty
    }

    It 'returns null on broken JSON' {
        & $Private.ConvertFacts -Output 'IPU-FACTS={"Build": 20348,' | Should -BeNullOrEmpty
    }

    It 'fills safe defaults for missing fields' {
        $facts = & $Private.ConvertFacts -Output 'IPU-FACTS={"Build":14393,"EditionId":"ServerStandard"}'
        $facts.Build | Should -Be 14393
        $facts.ActivationChannel | Should -Be 'unknown'
        $facts.Language | Should -Be ''
        $facts.PendingReboot | Should -BeFalse
        $facts.DomainRole | Should -Be 0
    }
}

Describe 'ARM facts projection (Get-VMArmFacts)' {
    It 'reads a managed, zonal, Trusted Launch VM' {
        $vm = [pscustomobject]@{
            Name              = 'vm-a'
            ResourceGroupName = 'rg-a'
            Location          = 'westeurope'
            Zones             = @('2')
            StorageProfile    = [pscustomobject]@{
                OsDisk = [pscustomobject]@{ OsType = 'Windows'; ManagedDisk = [pscustomobject]@{ Id = '/subscriptions/x/disks/os' }; DiffDiskSettings = $null }
            }
            SecurityProfile   = [pscustomobject]@{ SecurityType = 'TrustedLaunch' }
        }
        $facts = & $Private.ArmFacts -VM $vm -PowerState 'running'
        $facts.OsDiskManaged | Should -BeTrue
        $facts.OsDiskEphemeral | Should -BeFalse
        $facts.Zone | Should -Be '2'
        $facts.SecurityType | Should -Be 'TrustedLaunch'
        $facts.PowerState | Should -Be 'running'
    }

    It 'reads an unmanaged, ephemeral, regional VM without a security profile' {
        $vm = [pscustomobject]@{
            Name              = 'vm-b'
            ResourceGroupName = 'rg-b'
            Location          = 'westeurope'
            StorageProfile    = [pscustomobject]@{
                OsDisk = [pscustomobject]@{ OsType = 'Windows'; ManagedDisk = $null; DiffDiskSettings = [pscustomobject]@{ Option = 'Local' } }
            }
        }
        $facts = & $Private.ArmFacts -VM $vm
        $facts.OsDiskManaged | Should -BeFalse
        $facts.OsDiskEphemeral | Should -BeTrue
        $facts.Zone | Should -BeNullOrEmpty
        $facts.SecurityType | Should -BeNullOrEmpty
        $facts.PowerState | Should -Be 'unknown'
    }
}

Describe 'Readiness rules (Resolve-InPlaceUpgradeReadiness)' {
    It 'declares a healthy Windows Server 2022 guest eligible for WS2025 on the MediaDisk engine' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts) -Media $MediaPresent
        $r.Decision | Should -Be 'Eligible'
        $r.Eligible | Should -BeTrue
        $r.Engine | Should -Be 'MediaDisk'
        $r.SourceName | Should -Be 'Windows Server 2022'
        $r.MediaImageVersion | Should -Be '26100.4652.250712'
        $r.Failures | Should -Be 0
        $r.Warnings | Should -Be 0
        (Get-Check $r 'SourceBuild').Detail | Should -Match 'lab-verified'
    }

    It 'says so when a documented path has not been verified here yet' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ Build = 17763; ProductName = 'Windows Server 2019 Datacenter' }) -Media $MediaPresent
        (Get-Check $r 'SourceBuild').Result | Should -Be 'Pass'
        (Get-Check $r 'SourceBuild').Detail | Should -Match 'not yet verified'
    }

    It 'only ever emits known check results' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts) -Media $MediaPresent
        foreach ($check in $r.Checks) { $check.Result | Should -BeIn @('Pass', 'Warn', 'Fail', 'Skip') }
    }

    It 'reports AlreadyAtTarget when the guest already runs the target build' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ Build = 26100 }) -Media $MediaPresent
        $r.Decision | Should -Be 'AlreadyAtTarget'
        $r.Eligible | Should -BeFalse
        $r.Engine | Should -BeNullOrEmpty
        (Get-Check $r 'SourceBuild').Result | Should -Be 'Skip'
    }

    It 'skips guest checks when the VM is not running' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts @{ PowerState = 'deallocated' }) -GuestFacts $null -Media $MediaPresent
        $r.Decision | Should -Be 'NotEligible'
        (Get-Check $r 'PowerState').Result | Should -Be 'Fail'
        (Get-Check $r 'GuestReachable').Result | Should -Be 'Skip'
        Get-Check $r 'Edition' | Should -BeNullOrEmpty
    }

    It 'fails when the guest is unreachable and carries the probe error' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts $null -GuestError 'VM agent is unresponsive' -Media $MediaPresent
        $r.Decision | Should -Be 'NotEligible'
        (Get-Check $r 'GuestReachable').Result | Should -Be 'Fail'
        (Get-Check $r 'GuestReachable').Detail | Should -Match 'unresponsive'
    }

    It 'rejects a source build that is not in the matrix and selects no engine' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ Build = 10240 }) -Media $MediaPresent
        (Get-Check $r 'SourceBuild').Result | Should -Be 'Fail'
        (Get-Check $r 'SourceBuild').Detail | Should -Match 'Windows Server 2022 \(20348\)'
        Get-Check $r 'Engine' | Should -BeNullOrEmpty
        $r.Engine | Should -BeNullOrEmpty
        $r.Decision | Should -Be 'NotEligible'
    }

    It 'rejects a domain controller' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ DomainRole = 5 }) -Media $MediaPresent
        (Get-Check $r 'DomainController').Result | Should -Be 'Fail'
        $r.Decision | Should -Be 'NotEligible'
    }

    It 'rejects Azure Edition with a hint' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ EditionId = 'ServerDatacenterAzureEdition' }) -Media $MediaPresent
        (Get-Check $r 'Edition').Result | Should -Be 'Fail'
        (Get-Check $r 'Edition').Detail | Should -Match 'Azure Edition is out of scope'
    }

    It 'accepts a Server Core edition id with a Cor suffix' {
        $facts = New-GuestFacts @{ EditionId = 'ServerDatacenterCor'; InstallationType = 'Server Core'; ProductName = 'Windows Server 2022 Datacenter' }
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts $facts -Media $MediaPresent
        (Get-Check $r 'Edition').Result | Should -Be 'Pass'
        (Get-Check $r 'InstallationType').Result | Should -Be 'Pass'
        $r.Decision | Should -Be 'Eligible'
    }

    It 'rejects an unknown installation type' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ InstallationType = 'Client' }) -Media $MediaPresent
        (Get-Check $r 'InstallationType').Result | Should -Be 'Fail'
    }

    It 'rejects a pending reboot' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ PendingReboot = $true }) -Media $MediaPresent
        (Get-Check $r 'PendingReboot').Result | Should -Be 'Fail'
        $r.Decision | Should -Be 'NotEligible'
    }

    It 'applies the free-space minimum' {
        $facts = New-GuestFacts @{ FreeGB = 20 }
        (Get-Check (& $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts $facts -Media $MediaPresent) 'FreeSpace').Result | Should -Be 'Fail'
        (Get-Check (& $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts $facts -Media $MediaPresent -MinimumFreeSpaceGB 15) 'FreeSpace').Result | Should -Be 'Pass'
    }

    It 'rejects a non-en-US guest because the media is en-US only' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ Language = 'de-DE' }) -Media $MediaPresent
        (Get-Check $r 'Language').Result | Should -Be 'Fail'
        (Get-Check $r 'Language').Detail | Should -Match 'en-US only'
    }

    It 'rejects a wrong architecture' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ Architecture = 'ARM 64-bit' }) -Media $MediaPresent
        (Get-Check $r 'Architecture').Result | Should -Be 'Fail'
    }

    It 'rejects a cluster node and a running Setup' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ ClusterServicePresent = $true; SetupRunning = $true }) -Media $MediaPresent
        (Get-Check $r 'Cluster').Result | Should -Be 'Fail'
        (Get-Check $r 'SetupRunning').Result | Should -Be 'Fail'
        $r.Failures | Should -Be 2
    }

    It 'warns when the volume-licensed guest is not activated (no outbound to Azure KMS)' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ LicenseStatus = 5 }) -Media $MediaPresent
        (Get-Check $r 'Activation').Result | Should -Be 'Warn'
        (Get-Check $r 'Activation').Detail | Should -Match 'license status 5'
        $r.Decision | Should -Be 'Eligible'
    }

    It 'warns on a non-volume activation channel but stays eligible' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts @{ ActivationChannel = 'Retail' }) -Media $MediaPresent
        (Get-Check $r 'Activation').Result | Should -Be 'Warn'
        $r.Decision | Should -Be 'Eligible'
        $r.Warnings | Should -Be 1
    }

    It 'warns on Trusted Launch but stays eligible' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts @{ SecurityType = 'TrustedLaunch' }) -GuestFacts (New-GuestFacts) -Media $MediaPresent
        (Get-Check $r 'SecurityType').Result | Should -Be 'Warn'
        $r.Decision | Should -Be 'Eligible'
    }

    It 'fails the engine when the upgrade image is missing in the region' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts) -Media $MediaMissing
        (Get-Check $r 'MediaImage').Result | Should -Be 'Fail'
        (Get-Check $r 'Engine').Result | Should -Be 'Fail'
        $r.Engine | Should -BeNullOrEmpty
        $r.Decision | Should -Be 'NotEligible'
    }

    It 'surfaces a media lookup error' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts) -Media $MediaError
        (Get-Check $r 'MediaImage').Result | Should -Be 'Fail'
        (Get-Check $r 'MediaImage').Detail | Should -Match 'AuthorizationFailed'
    }

    It 'selects MediaDisk with a warning when the media was not checked' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts) -GuestFacts (New-GuestFacts) -Media $null
        Get-Check $r 'MediaImage' | Should -BeNullOrEmpty
        (Get-Check $r 'Engine').Result | Should -Be 'Warn'
        $r.Engine | Should -Be 'MediaDisk'
        $r.Decision | Should -Be 'Eligible'
    }

    It 'rejects unmanaged, ephemeral and non-Windows OS disks' {
        $r = & $Private.Resolve -Target $Target2025 -ArmFacts (New-ArmFacts @{ OsDiskManaged = $false; OsDiskEphemeral = $true; OsType = 'Linux' }) -GuestFacts (New-GuestFacts) -Media $MediaPresent
        (Get-Check $r 'OsDiskManaged').Result | Should -Be 'Fail'
        (Get-Check $r 'OsDiskEphemeral').Result | Should -Be 'Fail'
        (Get-Check $r 'OsType').Result | Should -Be 'Fail'
    }

    It 'evaluates a WS2016 to WS2019 path from the matrix' {
        $target = Get-InPlaceUpgradeTarget -Name WS2019
        $facts = New-GuestFacts @{ Build = 14393; ProductName = 'Windows Server 2016 Standard'; EditionId = 'ServerStandard' }
        $media = [pscustomobject]@{ Checked = $true; Version = '17763.1.1'; Error = $null }
        $r = & $Private.Resolve -Target $target -ArmFacts (New-ArmFacts) -GuestFacts $facts -Media $media
        $r.Decision | Should -Be 'Eligible'
        $r.SourceName | Should -Be 'Windows Server 2016'
        $r.TargetBuild | Should -Be 17763
    }
}
