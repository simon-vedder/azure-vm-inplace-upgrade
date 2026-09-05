# deploy/

`lab.bicep` builds one tagged source VM to verify the module against. `main.bicep` (Automation
Account, identity, custom role, module import, schedules, Log Analytics, workbook) follows once
`Start-InPlaceUpgrade` exists.

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
