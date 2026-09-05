# Known issues and sharp edges

Everything here is either observed in the working prototype this project was rewritten from, or
documented by Microsoft. Each entry says which. "To verify" means it is on the lab list.

## Setup and media

- **`0xC1900215` under `/quiet`: the GUI works, the unattended run does not.** *(observed,
  reproduced twice on 2026-09-05 on a plain `2022-datacenter-g2` Marketplace VM, with and without
  `/pkey`)* `setuperr.log` shows `CallPidGenX: PidGenX function failed on this product key
  (hr = 0x8a010001)` and looks like a licensing problem. It is not. `setupact.log` tells the real
  story:

  ```
  ProductKey: Matching Install Wim: Found [2] matching images.
  ProductKey: Product key was successfully validated.
  ProductKey: SelectImageIndex: Found multiple matching images. Querying for image index.
  ProductKey: Image selection response not found.
  ProductKey: SelectImageIndex: Image index not found in response. Selecting image index from SkuLib.
  ProductKey: No SkuLib Upgrade edition available.
  CDlpActionProductKeyValidate::SelectImageIndex(1978): Result = 0xC1900215
  ```

  The upgrade media carries two images per edition, Core and Desktop Experience. In the GUI a
  human picks one. In `/quiet` mode nobody answers, Setup falls back to its SkuLib, finds no
  upgrade edition there and aborts. The PidGenX line is the failed attempt to report the host's
  install channel to telemetry, a side show. A `/pkey`, even a valid one, changes nothing because
  the key is not the problem.

  **Fix:** name the image. The module lists the media's `install.wim` with `Get-WindowsImage`,
  matches the guest's `EditionId` and `InstallationType` against it and passes
  `/installfrom <install.wim> /imageindex <n>`. On the `server2025Upgrade` media of 2026-09
  the images are 1 Standard Core, 2 Standard Desktop Experience, 3 Datacenter Core,
  4 Datacenter Desktop Experience; the module never assumes those numbers.
  *(verified 2026-09-05: the same VM that failed twice completed 2022 → 2025 in 37 minutes with
  `/installfrom` and `/imageindex 4`, no `/pkey`)*
- **After the upgrade the guest shows a pending reboot and license status 5 again.** *(observed)*
  CBS asks for one more reboot and the new OS re-activates against Azure KMS on its own within
  minutes (status 1 again ten minutes after the upgrade, no action taken); `Windows.old` (about 5 GB here) stays for the rollback window. The preflight reports
  AlreadyAtTarget and Complete skips the VM, so neither is a problem for the tool.
- **`/pkey` is not the answer to `0xC1900215`.** *(observed)* Microsoft Q&A threads recommend
  the target version's KMS client setup key. It validates, and Setup still fails at image
  selection. The module keeps `-UseMatrixProductKey` for guests whose own key does not validate.
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
- **Older DISM reports different image names.** *(observed, 2026-09-05)* On a Windows Server
  2016 guest `Get-WindowsImage` calls image 4 `Windows Server 2025 SERVERDATACENTER`; on 2022 it
  is `Windows Server 2025 Datacenter (Desktop Experience)`. `EditionId` and `InstallationType`
  are stable across DISM versions, names are not. The module matches metadata only.
- **The media disk's drive letter varies.** *(observed)* `E:` on a 2022 guest, `F:` on a 2016
  guest with a temporary disk on `E:`. The module searches every non-system volume.
- **The scheduled task may not survive a multi-version upgrade.** *(observed, 2016 → 2025)*
  After the upgrade the guest reported no task at all (state `None`, no result). Completion is
  decided on the build number, so this changes nothing; the cleanup step simply finds nothing to
  remove.

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
- **Do not import a newer Az.Accounts into the Automation Account.** *(observed, 2026-09-05)*
  The PowerShell 7.2 runtime ships a global Az 11.2.0 bundle. Importing Az.Accounts 5.5.3 next to
  it made every job die at `Import-Module Az.Accounts` with "Unable to find type
  AzAssemblyLoadContextInitializer" and a missing MSAL assembly. The deployment imports only
  `AzureInPlaceUpgrade`; its manifest minimums are the runtime defaults (Az.Accounts 2.15.0,
  Az.Compute 7.1.1, Az.Resources 6.13.0). Runtime environments with a pinned Az version are the
  clean way out once they leave preview.
- **Automation only re-imports a module or re-publishes a runbook when the content link's
  `version` changes.** *(observed, 2026-09-05)* A redeploy with a changed package behind the same
  URI was a silent no-op; the runbook kept its old parameters and `Start-AzAutomationRunbook`
  answered "Invalid runbook parameters". The Bicep stamps `contentVersion` on both links; it must
  look like a `System.Version` (`0.2.0.7`), a pre-release suffix is rejected.
- **Job schedules are immutable once linked.** *(observed)* Changing their parameters in the
  template does nothing. Anything that may change later (the telemetry target) is an Automation
  variable the runbook reads, not a job parameter.
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
  *(observed, 2026-09-05)* The click is not required. A plain `IsInstalled=0` search of the Windows
  Update Agent does not return the feature update, but
  `IsInstalled=0 and DeploymentAction='OptionalInstallation'` returns **Windows Server 2025**
  (category Upgrades, `EulaAccepted=True`, `CanRequestUserInput=False`, reboot required) once the
  opt-in key is set and the March 2026 CU or later is installed. `Microsoft.Update.Session` downloads
  and installs it from a SYSTEM scheduled task. *(verified 2026-09-05: build 26100.33296 after
  download 15 min, install 88 min, commit 4 min, offline phase 4 min; the media disk did the
  same upgrade in 37 minutes.)*
- **`Install()` only stages the feature update; `Restart-Computer` afterwards reboots without
  applying it.** *(observed, 2026-09-05)* The guest came back on the old build twice, with
  `0x80242014` (post-reboot operation still pending) in the update history. What works:
  `IUpdateInstaller4.Commit(0)` on an installer whose `Updates` collection holds the update
  (a fresh installer without it answers `0x80240004`), then a restart through the update
  orchestrator (`UsoClient RestartDevice`, `shutdown /r` as fallback). Commit itself ran four
  minutes. The engine's worker does exactly this.
- **The feature update empties `C:\Windows\Temp`.** *(observed)* The worker's log under
  `C:\Windows\Temp\AzureInPlaceUpgrade` is gone after the upgrade, so a post-upgrade log excerpt
  is not available for this engine; the Windows Update history (`Windows Server 2025`, result 2)
  is the record that survives. The engine's end-to-end run took 186 minutes against 37 for the
  media disk on the same image; the install phase alone ran over two hours.

## Rollback

- **An OS disk snapshot is a rollback point, not a tested restore.** Swap the OS disk from a disk
  created off the snapshot; data disks are not touched by the upgrade but snapshot them too if the
  application state matters. Test the procedure once before relying on it.
