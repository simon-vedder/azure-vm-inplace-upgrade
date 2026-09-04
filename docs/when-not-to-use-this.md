# When not to use this

Read this before tagging anything that matters.

## Microsoft's position, verbatim in spirit

Microsoft's Azure documentation for in-place upgrades opens with a caution: the process causes a
disconnection between the VM's data plane and control plane. Auto guest patching, automatic OS
image upgrades, hotpatching and Azure Update Manager **are not officially supported afterwards and
may fail immediately or in the future**. The image reference, publisher, offer and plan never
change. Microsoft's recommendation for anyone who needs those features is to **create a new VM**.

This project does not make that caveat go away. It makes the upgrade unattended and repeatable
for the cases where rebuilding is not an option.

## Rebuild instead if you can

If the VM is built from code, replaceable and stateless, redeploy it on a Windows Server 2025
image. You get a clean OS, current ARM metadata, hotpatch eligibility and none of the risk below.
In-place upgrades are for machines that are expensive to rebuild: hand-configured application
servers, license-bound software, servers nobody documented.

## Do not use in place for

| Case | Why | Do this instead |
|---|---|---|
| Domain controllers | Microsoft advises against it; AD improvements in 2025 need a clean install | Promote new DCs, demote old ones |
| Failover cluster nodes | Not a supported in-place path | Cluster-Aware Updating or a cluster OS rolling upgrade |
| Windows Server Datacenter: Azure Edition | Hotpatch servicing model, different media | Redeploy on the 2025 Azure Edition image |
| Ephemeral OS disks | No snapshot, disk resets on reallocation | Redeploy |
| Unmanaged disks | Not supported | Migrate to managed disks first |
| Non-`en-US` installs | Upgrade media is `en-US` only | Change system language, or redeploy |
| Retail / OEM activated guests | Media requires volume licensing | Convert to KMS client key first |
| Pooled Azure Virtual Desktop hosts | Unsupported | Rebuild from image |
| Anything without a tested restore | A snapshot you never restored is a hope | Restore once in a lab, then proceed |

## Things the preflight cannot see

- Third-party software that blocks Setup (backup agents, filter drivers, EDR). Microsoft says to
  disable antivirus and firewalls during the upgrade; the module does not do that for you.
- Application compatibility with Windows Server 2025. The OS upgrading fine says nothing about
  the SQL Server, the ERP or the line-of-business service on top of it.
- Whether the maintenance window is long enough. Budget 60 to 120 minutes plus reboots per VM.
