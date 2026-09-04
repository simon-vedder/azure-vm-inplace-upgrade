# Security

This module changes operating systems on virtual machines. Treat it with the care that implies.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository. Do not open a public issue for
anything that could be exploited. You will get an answer within a few days.

## What to never put in an issue

Tenant IDs, subscription IDs, resource IDs, VM names from production, Run Command output, Setup logs
with hostnames. Redact first.

## Design notes relevant to security

- Runs under a managed identity the customer owns; the project never holds credentials.
- The preflight is read-only. State changes are opt-in per VM via the `UpgradeState=Pending` tag.
- Setup runs as `NT AUTHORITY\SYSTEM` through a scheduled task inside the guest; the task is
  registered by Run Command, which already requires `Microsoft.Compute/virtualMachines/runCommand/action`.
- No telemetry, no phone-home. The only outbound call the module makes on your behalf is the
  optional Log Analytics ingestion you configure.
