# deploy/

`main.bicep` deploys the orchestrator. `lab.bicep` builds one tagged source VM to verify the module
against.

## Orchestrator (`main.bicep`)

Subscription-scope deployment, because the custom role definition lives there:

```bash
az deployment sub create -l westeurope -f deploy/main.bicep \
  -p moduleVersion=0.1.0 targetResourceGroupName=rg-apps-prod-weu ring=Ring0 maxParallel=3
```

What it creates:

| Resource | Purpose |
|---|---|
| Resource group `rg-inplaceupgrade-weu` | everything below |
| Automation Account, system-assigned identity, local auth disabled | runs the runbook |
| Log Analytics workspace + diagnostic settings | job logs and streams |
| Module `AzureInPlaceUpgrade` (PowerShell 7.2 runtime, uses the runtime's global Az bundle) | the engine |
| Runbook `Invoke-InPlaceUpgradeRunbook` (PowerShell 7.2) | the thin wrapper from `src/runbooks/` |
| Schedule `inplaceupgrade-check`, every 20 minutes, linked | finishes running upgrades |
| Schedule `inplaceupgrade-start`, daily, **not linked** unless `startScheduleEnabled=true` | starts approved upgrades |
| Custom role *Azure VM In-Place Upgrade Operator* | exactly the actions Start and Complete need |
| Role assignment on `targetResourceGroupName`, or the subscription when empty | least privilege |

Nothing starts an upgrade by itself. The Start schedule is created but not linked to the runbook
until you redeploy with `startScheduleEnabled=true`, and even then only VMs tagged
`UpgradeState=Pending` are touched.

Before the first Gallery release, point `modulePackageUri` at a GitHub release asset (a zip of
`src/AzureInPlaceUpgrade`) and `runbookContentUri` at the raw runbook URL of a tag.

## Lab

```bash
az group create -n rg-ipu-lab-weu -l westeurope --tags Environment=lab Owner=simon CostCenter=lab Project=azure-vm-inplace-upgrade
az deployment group create -g rg-ipu-lab-weu -f deploy/lab.bicep \
  -p vmName=vm-ipu-2022-01 imageSku=2022-datacenter-g2 adminPassword="$(openssl rand -base64 30 | tr -dc 'A-Za-z0-9' | head -c 18)Xy9!"
```

The password is generated and forgotten on purpose. Nothing in this project ever logs on to the VM;
Run Command does all the talking. There is no public IP and no inbound rule.

Between sessions:

```bash
az vm deallocate -g rg-ipu-lab-weu -n vm-ipu-2022-01 --no-wait
```

When done:

```bash
az group delete -n rg-ipu-lab-weu --yes --no-wait
```
