function ConvertTo-UpgradeRecord {
    <#
    .SYNOPSIS
    Build one structured record for a state transition (pure)

    .DESCRIPTION
    Every record has the same shape so the Log Analytics table and the workbook can rely on it.
    Free-text fields are capped: Reason at 1000 characters, LogExcerpt at 4000. Never contains
    credentials or keys; the Setup arguments are not recorded at all.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)][string]$Result,
        [Parameter()][AllowEmptyString()][string]$Reason = '',
        [Parameter()][AllowEmptyString()][string]$Target = '',
        [Parameter()][AllowEmptyString()][string]$Engine = '',
        [Parameter()][AllowNull()][nullable[int]]$SourceBuild,
        [Parameter()][AllowNull()][nullable[int]]$TargetBuild,
        [Parameter()][AllowNull()][nullable[int]]$ImageIndex,
        [Parameter()][AllowNull()][nullable[int]]$DurationMinutes,
        [Parameter()][AllowEmptyString()][string]$TaskResult = '',
        [Parameter()][AllowEmptyString()][string]$Snapshot = '',
        [Parameter()][AllowEmptyString()][string]$MediaDisk = '',
        [Parameter()][AllowEmptyString()][string]$Mode = '',
        [Parameter()][AllowEmptyString()][string]$LogExcerpt = '',
        [Parameter()][datetime]$TimeGenerated = (Get-Date).ToUniversalTime()
    )

    $jobId = ''
    $meta = Get-Variable -Name PSPrivateMetadata -ValueOnly -ErrorAction SilentlyContinue
    if ($meta -and (Test-Member -InputObject $meta -Name 'JobId') -and $meta.JobId) { $jobId = [string]$meta.JobId }

    $version = ''
    $module = Get-Module -Name AzureInPlaceUpgrade -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($module) { $version = $module.Version.ToString() }

    [pscustomobject]@{
        PSTypeName        = 'AzureInPlaceUpgrade.Record'
        TimeGenerated     = $TimeGenerated.ToUniversalTime().ToString('o')
        VMName            = $VMName
        ResourceGroupName = $ResourceGroupName
        Target            = $Target
        State             = $State
        Result            = $Result
        Reason            = if ($Reason.Length -gt 1000) { $Reason.Substring(0, 1000) } else { $Reason }
        Engine            = $Engine
        SourceBuild       = $SourceBuild
        TargetBuild       = $TargetBuild
        ImageIndex        = $ImageIndex
        DurationMinutes   = $DurationMinutes
        TaskResult        = $TaskResult
        Snapshot          = $Snapshot
        MediaDisk         = $MediaDisk
        Mode              = $Mode
        JobId             = $jobId
        ModuleVersion     = $version
        LogExcerpt        = if ($LogExcerpt.Length -gt 4000) { $LogExcerpt.Substring(0, 4000) } else { $LogExcerpt }
    }
}
