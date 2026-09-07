# deploy/

`main.bicep` deploys the orchestrator. `lab.bicep` builds one tagged source VM to verify the module
against.

## Orchestrator (`main.bicep`)

`azuredeploy.json` is the compiled form of `main.bicep` for the *Deploy to Azure* button; CI fails
when the two drift apart. Rebuild it with the Bicep version pinned in `.github/workflows/ci.yml`
(`az bicep install --version vX.Y.Z`, then `az bicep build -f deploy/main.bicep --outfile deploy/azuredeploy.json`).

Subscription-scope deployment, because the custom role definition lives there:

```bash
az deployment sub create -l westeurope -f deploy/main.bicep \
  -p moduleVersion=0.3.1-preview targetResourceGroupName=rg-apps-prod-weu ring=Ring0 maxParallel=3
```

What it creates:

| Resource | Purpose |
|---|---|
| Resource group `rg-inplaceupgrade-weu` | everything below |
| Automation Account, system-assigned identity, local auth disabled | runs the runbook |
| Log Analytics workspace + diagnostic settings | job logs and streams |
| Custom table `InPlaceUpgrade_CL`, data collection endpoint + rule, *Monitoring Metrics Publisher* for the identity | one record per state transition, written by the module |
| Automation variables `InPlaceUpgrade-LogIngestionEndpoint` / `-DataCollectionRuleId` | the runbook reads them; job schedules are immutable, variables are not |
| Workbook *In-place upgrades* | VMs by state, latest record per VM, failures, durations, activity |
| Module `AzureInPlaceUpgrade` (PowerShell 7.2 runtime, uses the runtime's global Az bundle) | the engine |
| Runbook `Invoke-InPlaceUpgradeRunbook` (PowerShell 7.2) | the thin wrapper from `src/runbooks/` |
| Schedule `inplaceupgrade-check`, every 20 minutes, linked | finishes running upgrades |
| Schedule `inplaceupgrade-start`, daily, **not linked** unless `startScheduleEnabled=true` | starts approved upgrades |
| Custom role *Azure VM In-Place Upgrade Operator* | exactly the actions Start and Complete need |
| Role assignment on `targetResourceGroupName`, or the subscription when empty | least privilege |

Nothing starts an upgrade by itself. The Start schedule is created but not linked to the runbook
until you redeploy with `startScheduleEnabled=true`, and even then only VMs tagged
`UpgradeState=Pending` are touched.

Tearing down: `az group delete` removes everything in the resource group, but the custom role
definition lives at subscription scope and stays behind, and so can an orphaned assignment whose
identity died with the Automation Account. Remove both:

```bash
role=$(az role definition list --custom-role-only true --query "[?roleName=='Azure VM In-Place Upgrade Operator'].name" -o tsv)
az role assignment list --all --query "[?contains(roleDefinitionId, '$role')].id" -o tsv | xargs -n1 az role assignment delete --ids
az role definition delete --name "Azure VM In-Place Upgrade Operator"
```

`modulePackageUri` defaults to the PowerShell Gallery package for `moduleVersion` (for example
`0.3.1-preview`); override it only for a private build, such as a GitHub release asset or a zip of
`src/AzureInPlaceUpgrade` on a storage account. Pin `runbookContentUri` to the raw runbook URL of the
matching tag in production. When the content behind an unchanged URI changes, bump `contentVersion` (defaults to `moduleVersion` with any pre-release suffix stripped, because it must look like a `System.Version`, e.g. `0.3.0.7`): Automation
only re-imports a module or re-publishes a runbook when the version stamp on the link changes.

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
