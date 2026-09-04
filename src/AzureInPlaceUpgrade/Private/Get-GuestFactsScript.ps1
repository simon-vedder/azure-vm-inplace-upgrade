function Get-GuestFactsScript {
    <#
    .SYNOPSIS
    Return the in-guest probe that collects everything the readiness rules need

    .DESCRIPTION
    Runs under Windows PowerShell 5.1 inside the VM via Run Command, so the text stays free of
    PowerShell 7 syntax. It reads only; it changes nothing. The result is emitted as one JSON line
    prefixed with IPU-FACTS= so that ConvertFrom-GuestFacts can find it among any other output.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

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
