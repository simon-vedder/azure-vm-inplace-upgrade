function Invoke-GuestScript {
    <#
    .SYNOPSIS
    Run a short PowerShell snippet inside the guest through Azure Run Command

    .DESCRIPTION
    Wraps Invoke-AzVMRunCommand (RunPowerShellScript) and normalises the result into
    Success / Output / Error. Success means the Run Command itself executed; the caller decides
    what the output means. Only short-lived commands go through here, never the upgrade itself
    (ADR 0001). The snippet executes under Windows PowerShell 5.1 inside the VM, so script text
    passed in must not use PowerShell 7 syntax.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter()][hashtable]$Parameter
    )

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ipu-{0}.ps1" -f [guid]::NewGuid())
    try {
        # UTF-8 without BOM: a BOM would be treated as part of the first statement by the guest.
        [System.IO.File]::WriteAllText($tempFile, $ScriptText, [System.Text.UTF8Encoding]::new($false))

        $invokeParams = @{
            ResourceGroupName = $ResourceGroupName
            VMName            = $VMName
            CommandId         = 'RunPowerShellScript'
            ScriptPath        = $tempFile
            ErrorAction       = 'Stop'
            # Probes are read-only and must run even when a caller has -WhatIf set.
            WhatIf            = $false
            Confirm           = $false
        }
        if ($Parameter -and $Parameter.Count -gt 0) {
            $stringParams = @{}
            foreach ($key in $Parameter.Keys) { $stringParams[$key] = [string]$Parameter[$key] }
            $invokeParams['Parameter'] = $stringParams
        }

        $result = Invoke-AzVMRunCommand @invokeParams

        $stdOut = ($result.Value | Where-Object { $_.Code -like '*StdOut*' } | Select-Object -ExpandProperty Message) -join "`n"
        $stdErr = ($result.Value | Where-Object { $_.Code -like '*StdErr*' } | Select-Object -ExpandProperty Message) -join "`n"

        Write-Verbose "[$VMName] Run Command stdout: $($stdOut.Trim())"
        if (-not [string]::IsNullOrWhiteSpace($stdErr)) { Write-Verbose "[$VMName] Run Command stderr: $($stdErr.Trim())" }

        return [pscustomobject]@{
            Success = $true
            Output  = $stdOut.Trim()
            Error   = $stdErr.Trim()
        }
    }
    catch {
        Write-Verbose "[$VMName] Run Command invocation failed: $($_.Exception.Message)"
        return [pscustomobject]@{ Success = $false; Output = ''; Error = $_.Exception.Message }
    }
    finally {
        if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
    }
}
