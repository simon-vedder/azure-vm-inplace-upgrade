# Verification log

What ran, on what, and how long it took. Every row is a real run; nothing here is extrapolated.


Three lab runs on 2026-09-05 with `Invoke-InPlaceUpgrade`, fresh Marketplace VMs from
`deploy/lab.bicep` (Standard_B2ms, westeurope, no public IP), MediaDisk engine, no `/pkey`:

| Source image | Image picked | Setup start → build 26100 | Result |
|---|---|---|---|
| `2022-datacenter-g2` | 4, Datacenter (Desktop Experience) | 37 min | Completed, Desktop Experience kept |
| `2022-datacenter-core-g2` | 3, Datacenter (Core) | 23 min | Completed, still Server Core, no `explorer.exe` |
| `2016-datacenter-gensecond` | 4, Datacenter (Desktop Experience) | 42 min | Completed, 24H2 |
| `2019-datacenter-gensecond` | 4, Datacenter (Desktop Experience) | 43 min | Completed, driven by the Automation runbook, six telemetry records |
| `2022-datacenter-g2`, FeatureUpdate spike | Windows Update feature update, no media | ~2 h | build 26100.33296; the spike that shaped the engine |
| `2022-datacenter-g2`, `Start -Engine FeatureUpdate` | Windows Update feature update, no media | 186 min | Completed by the scheduled Check jobs, nine telemetry records; the engine's own end-to-end run |

The 2016 guest's older DISM reports the image name as `Windows Server 2025 SERVERDATACENTER`
instead of `Datacenter (Desktop Experience)`; the selection matches `EditionId` and
`InstallationType`, never names, so it still picked index 4. The media disk came up as `E:` on
2022 and `F:` on 2016, which is why the module searches for `setup.exe` instead of assuming a
letter. The Core and 2016 runs ran at the same time, each with its own media disk.

Timeline of the first 2022 run:

| Step | Duration |
|---|---|
| Preflight (Run Command probe + media lookup) | 35 s |
| Incremental OS disk snapshot | 5 s |
| Media disk from the hidden image, attach on LUN 0 | 25 s |
| Locate `setup.exe`, list `install.wim` images, pick index 4 | 2 min |
| Setup, downlevel phase (guest reachable, build still 20348) | 30 min |
| Reboots and offline phases | 6 min |
| Complete: build 26100 seen, tags, task removed, media disk deleted | 2 min |

Result object of the run:

```
Result            : Completed
Reason            : Windows Server 2025 Datacenter build 26100.
Build             : 26100
ProductName       : Windows Server 2025 Datacenter
TaskState         : Ready
TaskResult        : 0x00000000
AgeMinutes        : 37
Snapshot          : vm-ipu-2022-01-prews2025-20260905083758
MediaDiskRemoved  : True
```

Afterwards the guest reports `DisplayVersion 24H2`, build `26100.33296`, `Windows.old` present.
The VM's `instanceView.osVersion` says `10.0.26100.33296`; its `storageProfile.imageReference`
still says `2022-datacenter-g2` and always will. Two earlier attempts on the same VM failed with
`0xC1900215`, once without and once with `/pkey`; they are what led to the image-index detection.
The details are in [KNOWN-ISSUES.md](KNOWN-ISSUES.md).

