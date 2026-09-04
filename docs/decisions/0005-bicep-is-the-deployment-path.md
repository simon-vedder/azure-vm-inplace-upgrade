# 0005 — Bicep is the deployment path

**Status:** accepted · 2026-09-04

## Context

The Automation Account, its identity, custom role, module import, runbook, schedules, Log Analytics
table and workbook need to be deployable by someone who has never seen this repository.

## Decision

Bicep, with a *Deploy to Azure* button in the README. No Terraform variant is planned.

## Why

The audience is Azure administrators, the tooling should be the one Microsoft ships and the one a
`Deploy to Azure` button understands. A second IaC flavour would double the surface to keep tested
without adding users.

## Consequences

- `deploy/main.bicep` is the single source for the infrastructure; `deploy/lab.bicep` builds the
  tagged test VMs the project verifies against.
- Parameters never carry secrets; the identity is system-assigned.
