# 0003 — Start and Check are separate Automation jobs

**Status:** accepted · 2026-09-04

## Context

Azure Automation cancels cloud-sandbox jobs after three hours of fair-share runtime. One upgrade
fits; a batch of five does not. A single "start everything and wait" job is therefore unreliable
exactly where the tool is supposed to help.

## Decision

- `Start`: prechecks, snapshot, media disk, launch Setup, set `UpgradeStarted`, return. Minutes.
  Scheduled once at the beginning of a maintenance window.
- `Check`: for every VM in `UpgradeStarted`, read the guest build and the task result, move to
  `Completed` or `Failed`, clean up the media disk. Minutes. Scheduled every 20 to 30 minutes.
- `Full`: start, wait, validate in one run. For local execution, Cloud Shell and Hybrid Runbook
  Workers, where the fair-share limit does not apply.

## Consequences

- The `UpgradeStartedAt` tag exists only so `Check` can apply a timeout without shared memory.
- `Check` treats an unreachable guest as "rebooting" until the timeout, then as failed.
- The same module functions back all three modes; the runbook wrapper only decides which to call.
