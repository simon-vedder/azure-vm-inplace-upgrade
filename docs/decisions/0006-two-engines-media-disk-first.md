# 0006 — Two upgrade engines behind one state machine, media disk first

**Status:** proposed · 2026-09-04

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

## Consequences

- `Test-InPlaceUpgradeReadiness` reports engine availability per VM (media image present in the
  region, or feature-update prerequisites met).
- Engine choice is a `Start` parameter with a sensible default, never a tag value — a tag must
  not be able to select an arbitrary code path.
