# Contributing

Thanks for looking at this. The bar is simple: **anything that changes a VM must have run against a
real VM before it is merged**, and anything with logic has a test.

## Ground rules

- PowerShell 7.2 or newer. Windows PowerShell 5.1 is not a target. The only 5.1-compatible code is
  the guest probe text that runs *inside* the VM through Run Command — keep those here-strings free
  of PowerShell 7 syntax.
- Az modules only (`Az.Accounts`, `Az.Compute`, `Az.Resources`). Approved verbs. Comment-based help
  on every public function, including the exact RBAC actions it needs.
- `-WhatIf` / `-Confirm` on every function that changes state. Read-only functions never prompt.
- No secrets, tenant IDs, subscription IDs or customer names anywhere — not in code, tests, docs or
  issues. Product keys in `targets.json` are Microsoft's public KMS client setup keys and nothing else.
- Tests: `Invoke-Pester ./tests`. Analyzer: `Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`.
  Both must be clean. CI runs the same.

## Adding a target or source to the matrix

1. It must be an upgrade path Microsoft documents as supported for Azure VMs.
2. Add it with `"verified": false`.
3. Flip `verified` to `true` only in a pull request that states the lab run: source image, target,
   engine, duration, result. That sentence is the evidence.

## Pull requests

- One topic per PR, imperative commit messages ("Add pending-reboot check", not "changes").
- Update `CHANGELOG.md` under *Unreleased*.
- If behaviour or setup changed, the README changes in the same PR.
