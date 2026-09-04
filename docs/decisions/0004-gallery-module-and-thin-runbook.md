# 0004 — A PowerShell Gallery module and a thin runbook, not one big script

**Status:** accepted · 2026-09-04

## Context

The prototype was a single 1'500-line runbook. It worked, and it was untestable, unusable outside
Azure Automation and impossible to review in pieces.

## Decision

The upgrade logic is a module, `AzureInPlaceUpgrade`, one function per file, published to the
PowerShell Gallery. The Automation runbook is a thin wrapper: sign in, resolve scope, filter tags,
loop, call the module, summarise. The Bicep deployment imports the module into the Automation
Account from the Gallery at a pinned version; before the first Gallery release it points at a
GitHub release archive.

## Why

- Local use is a first-class scenario: `Install-Module AzureInPlaceUpgrade`, `Connect-AzAccount`,
  `Test-InPlaceUpgradeReadiness` on one VM. That is how anyone will try it before trusting it with
  a schedule.
- Pester can test the pure parts (matrix resolution, tag filtering, readiness rules, output parsing)
  without Azure.
- One implementation for local, Cloud Shell, pipeline and runbook.

## Rejected

Flattening the module into the runbook at build time (no distribution step, but a second artefact
to keep in sync and no `Install-Module` story). The Gallery is the distribution channel the target
audience already uses.

## Consequences

- The module must stay Windows-PowerShell-free (7.2+) *except* for the guest probe here-strings,
  which run inside the VM under Windows PowerShell 5.1.
- Automation runtime environment: PowerShell 7.2 or newer with a pinned Az version.
- Semantic versioning from the first release; the Bicep template pins the version it was tested with.
