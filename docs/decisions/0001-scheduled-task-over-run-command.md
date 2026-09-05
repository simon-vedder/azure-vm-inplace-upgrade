# 0001 — Setup runs from a scheduled task, not from Run Command

**Status:** accepted · 2026-09-04

## Context

`Invoke-AzVMRunCommand` is the only channel into the guest that needs no network path, no
credentials and no agent beyond the Azure Guest Agent. It has two hard limits: 90 minutes of
execution, and it does not survive a reboot. A Windows Server in-place upgrade takes 30 to 120
minutes and reboots several times.

## Decision

Run Command only *registers and starts* a scheduled task that runs `setup.exe` as
`NT AUTHORITY\SYSTEM` with `ExecutionTimeLimit = 0`, then returns within seconds. Progress is read
with short Run Commands that query the registry build number, the task state and the Setup
processes.

## Consequences

- The task name is the idempotency key: a running task or a live `setuphost`/`setupprep` process
  means "already upgrading", never "start again".
- A task can register fine and its action fail instantly (path with a space, SYSTEM cannot execute
  the media). The launcher waits ten seconds and reports the task's last result and the process
  list, so a dead start is visible immediately instead of at the timeout.
- `LastTaskResult` is a UInt32 HRESULT. Casting it to `[int]` overflows for values above
  `Int32.MaxValue` (`0xC1900093` does). It is only ever cast to `[uint32]`.
