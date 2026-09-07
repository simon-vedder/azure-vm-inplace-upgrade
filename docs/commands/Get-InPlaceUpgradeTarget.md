# Get-InPlaceUpgradeTarget

> Resolve an upgrade target and its supported source versions from the target matrix

The target matrix shipped with the module (targets.json) is the only mapping from a tag value
such as WS2025 to source builds, editions, installation types, upgrade media images and the
public KMS client setup keys Setup may need. This function reads it. Without parameters it
returns every target; with -Name one target; with -SourceBuild only the targets that accept
that build as a source, each with the matching source entry attached in the Source property.
Read-only, no Azure calls.

## Syntax

```powershell
Get-InPlaceUpgradeTarget [[-Name] <string>] [-SourceBuild <int>] [<CommonParameters>]
```

## Requirements and notes

Author:              Simon Vedder (simonvedder.com)
Version:             0.1.0
Created:             2026-09-04
LastModified:        2026-09-04
RequiredPermissions: None (reads a file shipped with the module)
Prerequisites:       PowerShell 7.2+

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-Name` | String | no | no |  | The target key, for example WS2025. Case-insensitive. An unknown key throws and lists the known keys. |
| `-SourceBuild` | Int32 | no | no | 0 | The Windows build number the guest currently runs (20348 for Windows Server 2022). Targets that do not accept it as a source are filtered out. |

## Examples

### Example 1

```powershell
# List every target and its sources
Get-InPlaceUpgradeTarget | Select-Object Name, TargetBuild, @{ n = 'Sources'; e = { $_.Sources.Name -join ', ' } }
```

### Example 2

```powershell
# Which targets can a Windows Server 2016 (build 14393) guest go to?
Get-InPlaceUpgradeTarget -SourceBuild 14393 | Select-Object Name, DisplayName, @{ n = 'Verified'; e = { $_.Source.Verified } }
```

### Example 3

```powershell
# The media image and product keys for WS2025
(Get-InPlaceUpgradeTarget -Name WS2025).Engines.MediaDisk
```

## Output

- AzureInPlaceUpgrade.Target

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
