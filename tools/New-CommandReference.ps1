<#
.SYNOPSIS
Generate the per-command reference under docs/commands from the module's own help.

.DESCRIPTION
The reference is generated, never hand-edited: the comment-based help in the function is the single
source, so the documentation cannot drift from the code. Run it after changing help or parameters,
and commit the result. CI runs it with -Check and fails when the committed files differ.

Writes one page per exported command plus an index with the module-wide requirements.

.PARAMETER Check
Generate into a temporary folder and compare against docs/commands. Exits non-zero on a difference
instead of writing anything.

.EXAMPLE
./tools/New-CommandReference.ps1

.EXAMPLE
./tools/New-CommandReference.ps1 -Check
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Get-ChildItem -Path (Join-Path $repoRoot 'src') -Filter '*.psd1' -Recurse |
    Where-Object { $_.BaseName -eq $_.Directory.Name } | Select-Object -First 1
if (-not $manifestPath) { throw "No module manifest found under $repoRoot/src." }

$manifest = Test-ModuleManifest -Path $manifestPath.FullName
Import-Module $manifestPath.FullName -Force
$moduleName = $manifest.Name
$commands = @(Get-Command -Module $moduleName | Sort-Object Name)
if (-not $commands.Count) { throw "$moduleName exports no commands." }

$common = @(
    'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction',
    'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer',
    'PipelineVariable', 'WhatIf', 'Confirm'
)

function Format-HelpText {
    # Help text arrives as an array of objects with a Text property, or as plain strings.
    param([Parameter()][AllowNull()]$Text)
    $parts = @($Text | ForEach-Object { if ($null -eq $_) { '' } elseif ($_ -is [string]) { $_ } else { [string]$_.Text } })
    $joined = ($parts -join "`n").Trim()
    return ($joined -replace "`r`n", "`n")
}

function Format-Cell {
    # One table cell: no line breaks, no unescaped pipes.
    param([Parameter()][AllowNull()][string]$Text)
    if (-not $Text) { return '' }
    return (($Text -replace '\s*\n\s*', ' ') -replace '\|', '\|').Trim()
}

$pages = @{}

foreach ($command in $commands) {
    $help = Get-Help -Name $command.Name -Full
    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("# $($command.Name)")
    $lines.Add('')
    $synopsis = Format-HelpText $help.Synopsis
    if ($synopsis) { $lines.Add("> $synopsis"); $lines.Add('') }

    $description = Format-HelpText $help.Description
    if ($description) { $lines.Add($description); $lines.Add('') }

    $lines.Add('## Syntax')
    $lines.Add('')
    $lines.Add('```powershell')
    # Get-Command -Syntax renders the parameter sets as text; the help object does not.
    foreach ($set in @((Get-Command -Name $command.Name -Syntax) -split "`r?`n")) {
        $text = $set.Trim()
        if ($text) { $lines.Add($text); $lines.Add('') }
    }
    while ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $lines.Add('```')
    $lines.Add('')

    $notes = Format-HelpText $help.alertSet.alert
    if ($notes) {
        $lines.Add('## Requirements and notes')
        $lines.Add('')
        $lines.Add($notes)
        $lines.Add('')
    }

    $parameters = @($help.parameters.parameter | Where-Object { $_.name -notin $common })
    $lines.Add('## Parameters')
    $lines.Add('')
    if ($parameters.Count) {
        $lines.Add('| Name | Type | Required | Pipeline | Default | Description |')
        $lines.Add('|---|---|---|---|---|---|')
        foreach ($parameter in $parameters) {
            $type = [string]$parameter.type.name
            $required = if ("$($parameter.required)" -eq 'true') { 'yes' } else { 'no' }
            $pipeline = if ("$($parameter.pipelineInput)" -like '*true*') { 'yes' } else { 'no' }
            $default = Format-Cell ([string]$parameter.defaultValue)
            if ($default -in '', 'None', 'False') { $default = '' }
            $text = Format-Cell (Format-HelpText $parameter.description)
            $lines.Add("| ``-$($parameter.name)`` | $type | $required | $pipeline | $default | $text |")
        }
    }
    else {
        $lines.Add('This command takes no parameters of its own.')
    }
    $lines.Add('')

    $supportsShouldProcess = $command.Parameters.ContainsKey('WhatIf')
    if ($supportsShouldProcess) {
        $lines.Add('Supports `-WhatIf` and `-Confirm`.')
        $lines.Add('')
    }

    $examples = @($help.examples.example)
    if ($examples.Count) {
        $lines.Add('## Examples')
        $lines.Add('')
        $index = 0
        foreach ($example in $examples) {
            $index++
            $code = ((Format-HelpText $example.code) -replace '^PS>\s*', '').Trim()
            $remark = Format-HelpText $example.remarks
            $lines.Add("### Example $index")
            $lines.Add('')
            $lines.Add('```powershell')
            $lines.Add($code)
            $lines.Add('```')
            if ($remark) { $lines.Add(''); $lines.Add($remark) }
            $lines.Add('')
        }
    }

    $outputs = @($help.returnValues.returnValue.type.name | Where-Object { $_ })
    if ($outputs.Count) {
        $lines.Add('## Output')
        $lines.Add('')
        foreach ($output in $outputs) { $lines.Add("- $((Format-HelpText $output))") }
        $lines.Add('')
    }

    $lines.Add('---')
    $lines.Add('')
    $lines.Add("[All commands](README.md) | [Module README](../../README.md)")
    $lines.Add('')
    $lines.Add('*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*')

    $pages["$($command.Name).md"] = ($lines -join "`n").TrimEnd() + "`n"
}

# ---- index -------------------------------------------------------------------------------------
$index = [System.Collections.Generic.List[string]]::new()
$index.Add("# $moduleName command reference")
$index.Add('')
$index.Add(([string]$manifest.Description).Trim())
$index.Add('')
$index.Add('## Requirements')
$index.Add('')
$index.Add('| | |')
$index.Add('|---|---|')
$index.Add("| Module version | $($manifest.Version)$(if ($manifest.PrivateData.PSData.Prerelease) { "-$($manifest.PrivateData.PSData.Prerelease)" }) |")
$index.Add("| PowerShell | $($manifest.PowerShellVersion)+ ($($manifest.CompatiblePSEditions -join ', ')) |")
$required = @($manifest.RequiredModules | ForEach-Object { "``$($_.Name)`` $($_.Version)+" })
$index.Add("| Required modules | $(if ($required.Count) { $required -join ', ' } else { 'none' }) |")
$index.Add("| Install | ``Install-Module $moduleName$(if ($manifest.PrivateData.PSData.Prerelease) { ' -AllowPrerelease' })`` |")
$index.Add('')
$index.Add('Per-command permissions are on each page under **Requirements and notes**.')
$index.Add('')
$index.Add('## Commands')
$index.Add('')
$index.Add('| Command | What it does |')
$index.Add('|---|---|')
foreach ($command in $commands) {
    $synopsis = Format-Cell (Format-HelpText (Get-Help -Name $command.Name).Synopsis)
    $index.Add("| [$($command.Name)]($($command.Name).md) | $synopsis |")
}
$index.Add('')
$index.Add('---')
$index.Add('')
$index.Add('*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not these files.*')
$pages['README.md'] = ($index -join "`n").TrimEnd() + "`n"

# ---- write or check ----------------------------------------------------------------------------
$target = Join-Path $repoRoot 'docs' 'commands'

if ($Check) {
    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($name in ($pages.Keys | Sort-Object)) {
        $path = Join-Path $target $name
        if (-not (Test-Path -Path $path)) { $problems.Add("missing: docs/commands/$name"); continue }
        $current = (Get-Content -Path $path -Raw) -replace "`r`n", "`n"
        if ($current -ne $pages[$name]) { $problems.Add("out of date: docs/commands/$name") }
    }
    foreach ($file in @(Get-ChildItem -Path $target -Filter '*.md' -ErrorAction SilentlyContinue)) {
        if (-not $pages.ContainsKey($file.Name)) { $problems.Add("orphaned: docs/commands/$($file.Name)") }
    }
    if ($problems.Count) {
        $problems | ForEach-Object { Write-Host "  $_" }
        throw "The command reference is not current. Run ./tools/New-CommandReference.ps1 and commit the result."
    }
    "The command reference matches the help of $($commands.Count) command(s)."
    return
}

$null = New-Item -ItemType Directory -Path $target -Force
foreach ($file in @(Get-ChildItem -Path $target -Filter '*.md' -ErrorAction SilentlyContinue)) {
    if (-not $pages.ContainsKey($file.Name)) { Remove-Item -Path $file.FullName -Force }
}
foreach ($name in ($pages.Keys | Sort-Object)) {
    Set-Content -Path (Join-Path $target $name) -Value $pages[$name] -Encoding utf8 -NoNewline
}
"Wrote $($pages.Count) file(s) to docs/commands for $($commands.Count) command(s)."
