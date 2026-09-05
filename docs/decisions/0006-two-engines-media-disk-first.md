# 0006 — Two upgrade engines behind one state machine, media disk first

**Status:** accepted · 2026-09-05 (spike verified both engines)

## Context

Two ways exist to get Windows Server 2025 onto an Azure VM in place:

1. **Media disk.** Microsoft's hidden Marketplace image
   `MicrosoftWindowsServer / WindowsServerUpgrade / server2025Upgrade` becomes a managed data disk
   that carries `setup.exe`. Works for every documented source version (2012 R2, 2016, 2019, 2022),
   needs no internet, is `en-US` only, needs volume-license activation, one disk per VM, billed
   while it exists.
2. **Windows Update feature update.** Since spring 2026, WS2019 and WS2022 can opt in through a
   registry key after the March 2026 cumulative update and receive 2025 as a feature update.
   No media, no disk, Windows Update knows the edition. Microsoft's announcement describes it as a
   manual *Download and install* click.

## Decision

The state machine, tags, preflight, snapshot and validation are engine-agnostic. The target matrix
lists which engines a source/target pair supports. `MediaDisk` is implemented first because it is
proven and covers the end-of-life population (2016 → 2025). `FeatureUpdate` is listed as
*experimental* and gets a lab spike: can the feature update be found, installed and rebooted from a
scheduled task without a human? If yes, it becomes the default for 2019/2022. If no, it stays
documented as manual-only.

## What the lab showed (2026-09-05)

Both engines reach build 26100 on a `2022-datacenter-g2` Marketplace VM. MediaDisk took 37
minutes from Setup start; FeatureUpdate took about two hours (15 min download, 88 min install
through the Windows Update Agent, 4 min commit, 4 min offline). FeatureUpdate needs no media disk
and no `install.wim` image selection, but it needs Windows Update reachability, the March 2026
cumulative update, the policy opt-in, a search with `DeploymentAction='OptionalInstallation'`
and, crucially, `Commit()` before the restart. MediaDisk stays the default; FeatureUpdate is the
alternative for guests that must not get a data disk attached or that sit on plain Windows
Update anyway.

## Consequences

- `Test-InPlaceUpgradeReadiness` reports engine availability per VM (media image present in the
  region, or feature-update prerequisites met).
- Engine choice is a `Start` parameter with a sensible default, never a tag value — a tag must
  not be able to select an arbitrary code path.
