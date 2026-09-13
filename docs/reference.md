# Reference: tags, state and what one run records

Everything the orchestrator reads to decide, everything it writes back, and what each value
means. If a value is not listed here, the tool does not read it.

## Where the state lives

**On the VM, in tags.** There is no database and no queue. Jobs run minutes or hours apart and
each one works out where a machine is from its tags alone, which is also why a rerun is safe.
See [ADR 0002](decisions/0002-tags-are-state-logs-are-history.md).

Tags are written with `Update-AzTag -Operation Merge`, so governance tags survive. Tags hold
**state**, one value each and overwritten by the next run. What happened goes to Log Analytics,
which is the history.

Tags matter in fleet mode only. Running the module against one machine by name reads no tags at
all.

## Tags on the virtual machine

| Tag | Written by | What it holds |
|---|---|---|
| `UpgradeTarget` | you | what is wanted: `WS2025`, `WS2022` or `WS2019`. A value that is not a key in `targets.json` never reaches an Azure image |
| `UpgradeState` | you, then the runbook | where the machine is. Setting it to `Pending` **is** the approval; there is no separate approval tag |
| `UpgradeRing` | you, optional | when it may run, so a fleet moves ring by ring |
| `UpgradeStartedAt` | the runbook | the timeout base, Unix epoch seconds. Not ISO, because Az cmdlets rewrite date strings on a VM round trip |
| `UpgradeSnapshot` | the runbook | the rollback point of the current run, so Complete finds what Start created and an operator sees it beside the VM |
| `UpgradeMediaDisk` | the runbook | the media disk of the current run, for the same reason |

### The states

```
Pending → SnapshotCreated → UpgradeStarted → Completed
                                          ↘ Failed
```

A mode only picks up machines in the state it expects: `Start` reads `Pending`, `Check` reads
`UpgradeStarted`. A machine that fails stays in `Failed` with its snapshot in place until
somebody sets it back to `Pending`. Nothing retries destructive work on its own.

## What one run records

One row per attempt in the Log Analytics custom table `InPlaceUpgrade_CL`, written through the
Logs Ingestion API and shown in the workbook.

| Column | What it holds |
|---|---|
| `TimeGenerated`, `JobId`, `Mode`, `ModuleVersion` | when, which job, which mode, which version |
| `VMName`, `ResourceGroupName` | the machine |
| `Target`, `SourceBuild`, `TargetBuild`, `ImageIndex` | what was asked for and what was found |
| `State`, `Result`, `Reason` | where it got to, whether that counts as success, and why |
| `Engine` | which path ran: the media disk or the feature update |
| `DurationMinutes`, `TaskResult` | how long, and what Setup returned |
| `Snapshot`, `MediaDisk` | the artefacts of that run |
| `LogExcerpt` | the part of the guest log that explains a failure |

No credentials and no guest content beyond the log excerpt.

## What it never reads

- Tags other than the six above
- The previous run's rows in Log Analytics. State is on the machine, not in the history
- Anything inside the guest except through the VM agent, and only read-only during preflight
