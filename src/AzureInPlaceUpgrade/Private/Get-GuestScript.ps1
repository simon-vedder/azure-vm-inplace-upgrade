function Get-GuestScript {
    <#
    .SYNOPSIS
    Return one of the scripts that run inside the guest through Run Command

    .DESCRIPTION
    Every in-guest script lives here so that one Pester test can parse all of them and fail on
    PowerShell 7 syntax: Run Command executes them under Windows PowerShell 5.1. They report
    through a single marker line (IPU-FACTS=, IPU-STATUS= or RESULT=) that the module-side
    parsers look for, so any other output the guest produces is harmless.

    Facts      read-only inventory for the preflight
    SetupPath  bring the media disk online and locate setup.exe
    WimImages  list the images in the media's install.wim with edition and installation type
    Launch     register and start the scheduled task that runs Setup (ADR 0001)
    Status     build number, Setup processes, task state and last result
    LogTail    excerpt of the Panther logs after a failure
    RemoveTask unregister the scheduled task after a final state
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Facts', 'SetupPath', 'WimImages', 'Launch', 'Status', 'LogTail', 'RemoveTask')]
        [string]$Name
    )

    switch ($Name) {
        'Facts' {
            return @'
$ErrorActionPreference = 'Stop'

$cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
$freeGB = [math]::Round((Get-PSDrive -Name C).Free / 1GB, 2)

$pending = $false
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending = $true }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending = $true }
$sessionManager = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
if ($sessionManager -and $sessionManager.PSObject.Properties['PendingFileRenameOperations'] -and $sessionManager.PendingFileRenameOperations) { $pending = $true }

# Windows activation: ApplicationID 55c92734-... is the Windows OS product; other rows are Office etc.
$channel = 'unknown'
$licenseStatus = -1
$license = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f'" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($license) {
    $channel = [string]$license.ProductKeyChannel
    $licenseStatus = [int]$license.LicenseStatus
}

$language = [string]$os.OSLanguage
try { $language = [System.Globalization.CultureInfo]::GetCultureInfo([int]$os.OSLanguage).Name } catch { }

$displayVersion = ''
if ($cv.PSObject.Properties['DisplayVersion']) { $displayVersion = [string]$cv.DisplayVersion }

$facts = [pscustomobject]@{
    Build                 = [int]$cv.CurrentBuildNumber
    ProductName           = [string]$cv.ProductName
    EditionId             = [string]$cv.EditionID
    InstallationType      = [string]$cv.InstallationType
    DisplayVersion        = $displayVersion
    Architecture          = [string]$os.OSArchitecture
    Language              = $language
    FreeGB                = $freeGB
    PendingReboot         = $pending
    DomainRole            = [int]$cs.DomainRole
    ClusterServicePresent = [bool](Get-Service -Name 'ClusSvc' -ErrorAction SilentlyContinue)
    ActivationChannel     = $channel
    LicenseStatus         = $licenseStatus
    SetupRunning          = [bool](Get-Process -Name 'setuphost', 'setupprep' -ErrorAction SilentlyContinue)
}

Write-Output ('IPU-FACTS=' + ($facts | ConvertTo-Json -Compress))
'@
        }

        'SetupPath' {
            return @'
$ErrorActionPreference = 'Stop'

# The ARM attach returns before the guest storage stack has enumerated the new SCSI device, so
# force a rescan on every attempt. A data disk can also come up offline depending on the SAN policy.
Update-HostStorageCache -ErrorAction SilentlyContinue
Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Out-Null

$disks = Get-Disk
$disks | Where-Object { $_.OperationalStatus -eq 'Offline' } | ForEach-Object { Set-Disk -Number $_.Number -IsOffline $false }
$disks | Where-Object { $_.IsReadOnly } | ForEach-Object { Set-Disk -Number $_.Number -IsReadOnly $false }

$systemLetter = $env:SystemDrive.Substring(0, 1)
$found = $null
$listing = @()
foreach ($vol in (Get-Volume | Where-Object { $_.DriveLetter })) {
    if ([string]$vol.DriveLetter -eq $systemLetter) { continue }
    $root = '{0}:\' -f $vol.DriveLetter

    # The upgrade media is not laid out like an ISO; setup.exe is not guaranteed at the root.
    # Depth is capped so an unrelated large data disk cannot make this hang.
    $match = Get-ChildItem -Path $root -Filter 'setup.exe' -File -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) { $found = $match.FullName; break }

    $topLevel = (Get-ChildItem -Path $root -ErrorAction SilentlyContinue | Select-Object -First 20 -ExpandProperty Name) -join ','
    $listing += ('{0}[{1}]:{2}' -f $vol.DriveLetter, $vol.FileSystemLabel, $topLevel)
}

if ($found) {
    Write-Output ('RESULT=OK;SETUP={0}' -f $found)
}
else {
    $diskSummary = ($disks | ForEach-Object { '#{0}:{1}:{2}' -f $_.Number, $_.OperationalStatus, $_.PartitionStyle }) -join ','
    Write-Output ('RESULT=NOTFOUND;DISKS={0};LISTING={1}' -f $diskSummary, ($listing -join '|'))
}
'@
        }

        'WimImages' {
            return @'
param([string]$SetupPath)
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetDirectoryName($SetupPath)
$wim = Get-ChildItem -Path $root -Recurse -Depth 2 -Include 'install.wim', 'install.esd' -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $wim) {
    Write-Output ('IPU-IMAGES=' + (@{ WimPath = ''; Images = @() } | ConvertTo-Json -Compress))
    exit 0
}

$images = @()
foreach ($img in (Get-WindowsImage -ImagePath $wim.FullName)) {
    $detail = Get-WindowsImage -ImagePath $wim.FullName -Index $img.ImageIndex
    $images += [pscustomobject]@{
        Index            = [int]$img.ImageIndex
        Name             = [string]$img.ImageName
        EditionId        = [string]$detail.EditionId
        InstallationType = [string]$detail.InstallationType
        Version          = [string]$detail.Version
    }
}

Write-Output ('IPU-IMAGES=' + (@{ WimPath = $wim.FullName; Images = $images } | ConvertTo-Json -Compress -Depth 3))
'@
        }

        'Launch' {
            return @'
param([string]$SetupPath, [string]$TaskName, [string]$ProductKey, [int]$TargetImageIndex, [string]$InstallFrom, [string]$LogDirectory)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SetupPath)) {
    Write-Output 'RESULT=NOTFOUND'
    exit 0
}

# Idempotency: never start a second Setup next to a running one.
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing -and $existing.State -eq 'Running') {
    Write-Output 'RESULT=ALREADYRUNNING'
    exit 0
}
if (Get-Process -Name 'setuphost', 'setupprep' -ErrorAction SilentlyContinue) {
    Write-Output 'RESULT=ALREADYRUNNING'
    exit 0
}

New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null

$arguments = '/auto upgrade /quiet /eula accept /compat ignorewarning /dynamicupdate disable /showoobe none /telemetry disable /copylogs "{0}"' -f $LogDirectory
if ($ProductKey) { $arguments = '{0} /pkey {1}' -f $arguments, $ProductKey }

$workingDirectory = [System.IO.Path]::GetDirectoryName($SetupPath)
if ($TargetImageIndex -gt 0) {
    $installFile = $InstallFrom
    if (-not $installFile) { $installFile = Join-Path $workingDirectory 'sources\install.wim' }
    if (-not (Test-Path -LiteralPath $installFile)) {
        Write-Output ('RESULT=INSTALLWIMNOTFOUND;WIM={0}' -f $installFile)
        exit 0
    }
    $arguments = '{0} /installfrom "{1}" /imageindex {2}' -f $arguments, $installFile, $TargetImageIndex
}

$action = New-ScheduledTaskAction -Execute $SetupPath -Argument $arguments -WorkingDirectory $workingDirectory
$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 0 -MultipleInstances IgnoreNew -DontStopOnIdleEnd -Priority 4

Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings `
    -Description 'Unattended Windows Server in-place upgrade (azure-vm-inplace-upgrade)' -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 10

$task = Get-ScheduledTask -TaskName $TaskName
$taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
$setupProcesses = @(Get-Process -Name 'setup', 'setuphost', 'setupprep' -ErrorAction SilentlyContinue)
$processNames = ($setupProcesses | Select-Object -ExpandProperty ProcessName) -join ','
$lastResultHex = ('0x{0:X8}' -f [uint32]$taskInfo.LastTaskResult)

# A task can register fine while its action dies at once (path with a space, SYSTEM cannot run
# the media). Report the state and last result now instead of letting the caller wait for a timeout.
$state = 'FAILED'
if ($task.State -eq 'Running' -or $setupProcesses.Count -gt 0) { $state = 'STARTED' }
Write-Output ('RESULT={0};STATE={1};LASTRESULT={2};HEX={3};PROCESSES={4};ARGS={5}' -f $state, $task.State, $taskInfo.LastTaskResult, $lastResultHex, $processNames, $arguments)
'@
        }

        'Status' {
            return @'
param([string]$TaskName)
$ErrorActionPreference = 'Stop'

$cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$setupRunning = [bool](Get-Process -Name 'setuphost', 'setupprep' -ErrorAction SilentlyContinue)

$taskState = 'None'
$taskResult = $null
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    $taskState = [string]$task.State
    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($info) { $taskResult = [uint32]$info.LastTaskResult }
}

$displayVersion = ''
if ($cv.PSObject.Properties['DisplayVersion']) { $displayVersion = [string]$cv.DisplayVersion }

$status = [pscustomobject]@{
    Build          = [int]$cv.CurrentBuildNumber
    ProductName    = [string]$cv.ProductName
    DisplayVersion = $displayVersion
    SetupRunning   = $setupRunning
    TaskState      = $taskState
    TaskResult     = $taskResult
}
Write-Output ('IPU-STATUS=' + ($status | ConvertTo-Json -Compress))
'@
        }

        'LogTail' {
            return @'
param([string]$CopyLogsPath)
$ErrorActionPreference = 'SilentlyContinue'

# Setup stages its logs under $WINDOWS.~BT from the first second; /copylogs only fills the
# target later. Check the staging area first, the copy target as a fallback.
$roots = @('C:\$WINDOWS.~BT\Sources\Panther', (Join-Path $CopyLogsPath 'Panther'), $CopyLogsPath)
$out = New-Object System.Text.StringBuilder

foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $null = $out.AppendLine("ROOT=$root")

    foreach ($logName in 'setuperr.log', 'setupact.log') {
        $logPath = Join-Path $root $logName
        if (Test-Path -LiteralPath $logPath) {
            $tail = Get-Content -LiteralPath $logPath -Tail 25
            $null = $out.AppendLine("--- $logName (last 25 lines) ---")
            $null = $out.AppendLine(($tail -join "`n"))
        }
    }

    # Early hard blocks (edition, pending reboot, incompatible apps) land in the compat XML,
    # not in setupact.log.
    $compatFiles = Get-ChildItem -LiteralPath $root -Filter '*.xml' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Compat|ScanResult' }
    foreach ($xml in $compatFiles) {
        $blocking = Select-String -LiteralPath $xml.FullName -Pattern 'Block|Message=' -ErrorAction SilentlyContinue | Select-Object -First 10 -ExpandProperty Line
        if ($blocking) {
            $null = $out.AppendLine("--- $($xml.Name) (blocking entries) ---")
            $null = $out.AppendLine(($blocking -join "`n"))
        }
    }

    if ($out.Length -gt 0) { break }
}

$text = $out.ToString()
if ([string]::IsNullOrWhiteSpace($text)) {
    Write-Output 'RESULT=NOLOGS'
}
else {
    if ($text.Length -gt 3000) { $text = $text.Substring(0, 3000) + "`n...(truncated)" }
    Write-Output ('RESULT=OK' + "`n" + $text)
}
'@
        }

        'RemoveTask' {
            return @'
param([string]$TaskName)
$ErrorActionPreference = 'SilentlyContinue'
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Output 'RESULT=REMOVED'
}
else {
    Write-Output 'RESULT=NOTFOUND'
}
'@
        }
    }
}
