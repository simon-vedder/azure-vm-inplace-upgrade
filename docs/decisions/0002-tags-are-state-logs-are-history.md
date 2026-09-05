# 0002 — Tags hold the state, Log Analytics holds the history

**Status:** accepted · 2026-09-04

## Context

The orchestrator runs as separate Automation jobs minutes or hours apart. Each job needs to know
where every VM is in the process without a database.

## Decision

Four tags on the VM: `UpgradeTarget` (what is wanted), `UpgradeRing` (optional, when it may run),
`UpgradeState` (`Pending → SnapshotCreated → UpgradeStarted → Completed | Failed`) and
`UpgradeStartedAt` (the timeout base, Unix epoch seconds because Az cmdlets rewrite ISO date strings on a VM round trip). Two more point at the artefacts of the current run,
`UpgradeSnapshot` and `UpgradeMediaDisk`, so that Complete finds what Start created without
guessing names and an operator sees the rollback point next to the VM. They are overwritten by
the next run; that is state, not history. Setting `UpgradeState=Pending` **is** the approval; there is
no separate approval tag. Tags are written with `Update-AzTag -Operation Merge` so governance tags
survive.

Everything that happened — durations, exit codes, log excerpts, which engine ran — goes to a
Log Analytics custom table through the Logs Ingestion API and is shown in a workbook.

## Why

- Tags are visible in the portal, in Resource Graph and in cost reports without any tooling.
- A tag can be set by a human, a policy or a pipeline. That makes the approval step trivially
  integrable.
- Tags are a terrible history store (one value, 256 characters, no ordering). A table is a good one.

## Consequences

- Only VMs in the *expected* state are picked up by a mode. `Start` reads `Pending`, `Check` reads
  `UpgradeStarted`. Rerunning a job is safe.
- A VM that fails stays in `Failed` with its snapshot in place until somebody sets it back to
  `Pending`. Nothing retries destructive work on its own.
