# Known issues and sharp edges

Everything here is either observed in the working prototype this project was rewritten from, or
documented by Microsoft. Each entry says which. "To verify" means it is on the lab list.

## Setup and media

- **`0xC1900215` / "PidGenX function failed on this product key" under `/quiet`.** *(observed,
  reproduced 2026-09-05 on a plain `2022-datacenter-g2` Marketplace VM: `CallPidGenX ... hr =
  0x8a010001`, then `CDlpActionProductKeyValidate::SelectImageIndex: 0xC1900215`, two and a half
  minutes after Setup started)*
  Unattended Setup cannot always map the guest's AVMA activation to an image in the multi-edition
  `install.wim` on the upgrade media. The GUI asks you to pick the edition; `/quiet` has nobody to
  ask and aborts. Fix: pass the public KMS client setup key (GVLK) of the matching edition via
  `/pkey`. The key does not activate anything; it only tells Setup which image to use. The matrix
  ships those keys per target and edition. Passing the wrong edition's key silently installs the
  wrong edition — the module never guesses.
- **A failed Setup attempt leaves `CBS RebootPending` behind.** *(observed, 2026-09-05)* After
  the `0xC1900215` abort, Setup had cleaned up `$WINDOWS.~BT` but Component Based Servicing still
  flagged a pending reboot, so the preflight blocked the retry. Reboot, then start again; the
  module does not reboot a VM on its own.
- **`EI.cfg` is not a reliable way to force the edition for `/auto upgrade`.** *(observed)*
- **`/compat ignorewarning` is mandatory.** *(observed)* Without it, ignorable compatibility
  warnings abort the silent run.
- **The upgrade media is `en-US` only.** *(Microsoft)* Guests installed from a different language
  ISO fail. Set the system language to `en-US` before upgrading, or do not upgrade in place.
- **The media disk is not laid out like an ISO.** *(observed)* `setup.exe` is not guaranteed at the
  volume root; the module searches the volume, depth-capped.
- **A freshly attached data disk may not be visible in the guest for a while.** *(observed)*
  The ARM attach returns before the guest storage stack enumerates the device. The module rescans
  and retries.
- **`/dynamicupdate disable` means no download phase,** so the guest needs no internet for the
  media-disk engine. *(Microsoft)* `ping` proves nothing either way.
- **`TargetImageIndex` is media-dependent.** *(observed)* An index that is right for one media
  version can be wrong for another. Never assume it globally; detect it.

## Azure

- **`Update-AzVM` PUTs the whole VM, tags included.** *(observed, 2026-09-05)* Attaching the
  media disk with a VM object fetched minutes earlier silently reverted the tags written in
  between. Every `Update-AzVM` in this module now works on a freshly read object.
- **Az cmdlets rewrite date-like tag values.** *(observed, 2026-09-05)* `UpgradeStartedAt` was
  written as `2026-09-05T08:25:45.6700170Z` and read back as `09/05/2026 08:25:45` after a VM
  round trip: the SDK's JSON reader recognises ISO dates and re-serialises them in the process
  culture. The tag therefore holds Unix epoch seconds, which nothing rewrites.

- **Run Command dies with the first reboot and is capped at 90 minutes.** *(Microsoft)* Setup is
  never run synchronously; it runs from a scheduled task as SYSTEM with no execution time limit.
- **Azure Automation cloud jobs are cancelled after 3 hours (fair share).** *(Microsoft)* Hence the
  `Start` / `Check` split; `Full` mode is for local runs and Hybrid Runbook Workers only.
- **ARM metadata never changes after an in-place upgrade.** *(Microsoft)* `imageReference` still
  says Windows Server 2022, billing keeps the original meter, and the portal shows the old version.
  Validation happens in the guest (`CurrentBuildNumber`). Resource Graph `properties.extended.instanceView.osVersion`
  is updated by the guest agent and is the one ARM-side signal that does move.
- **Power state is not a progress signal.** *(observed)* The VM stays `running` while the guest
  reboots several times. An unreachable guest is treated as "rebooting", with a timeout.
- **Auto guest patching, hotpatch, automatic OS image upgrade and Azure Update Manager are "not
  officially supported" on an in-place-upgraded VM.** *(Microsoft)* Read
  [docs/when-not-to-use-this.md](docs/when-not-to-use-this.md) before tagging production.
- **The media disk must match region and, for zonal VMs, zone.** *(Microsoft)* One disk attaches to
  one VM at a time, so the module creates one per VM and deletes it after a final state. A failed
  run also deletes it unless told to keep it.
- **Ephemeral OS disks cannot be snapshotted** and unmanaged disks are unsupported. *(Microsoft)*
- **Trusted Launch / Secure Boot / vTPM.** *(to verify)* Microsoft's own assessment script checks
  these, which suggests edge cases. Flagged as a warning until the lab says otherwise.

## Upgrade rules

- **Same edition, same installation type, same architecture, same language only.** *(Microsoft)*
  No Standard → Datacenter, no Server Core ↔ Desktop Experience.
- **Domain controllers: Microsoft says don't.** *(Microsoft)* Promote new ones instead.
- **Clustered nodes: use Cluster-Aware Updating or a rolling upgrade.** *(Microsoft)*
- **Windows Server Datacenter: Azure Edition is out of scope.** Hotpatch and the Azure-Edition
  servicing model do not fit the media-disk path.

## Activation

- **KMS activation and Setup's edition choice are two different problems.** *(observed)* A PidGenX
  failure does not mean Azure KMS is broken.
- **A public GVLK is not a KMS host key** and never will be. *(Microsoft)*
- **The upgrade media requires volume-license (KMS) activation on the guest.** *(Microsoft)*
  Marketplace VMs have it; imported VMs may not. Retail/OEM channels are flagged.
- **A freshly provisioned Marketplace VM reports license status 5 (Notification) for a few
  minutes** before Azure KMS activation completes. *(observed, 2026-09-05: status 5 right after
  provisioning, status 1 fifteen minutes later, same VM, no change.)* The preflight warns; rerun
  it. If the status stays 5, check outbound TCP 1688 to `kms.core.windows.net`.

## Windows Update feature update (WS2019/2022 → 2025)

- Available since spring 2026, requires the March 2026 cumulative update and the
  `AllowWindowsServerFeatureUpdate` registry opt-in. *(Microsoft)*
- **Microsoft's announcement says an administrator must click *Download and install*.**
  Whether it can be triggered unattended from a scheduled task is *to verify*. Until then, the
  `FeatureUpdate` engine is listed in the matrix as experimental and not implemented.

## Rollback

- **An OS disk snapshot is a rollback point, not a tested restore.** Swap the OS disk from a disk
  created off the snapshot; data disks are not touched by the upgrade but snapshot them too if the
  application state matters. Test the procedure once before relying on it.
