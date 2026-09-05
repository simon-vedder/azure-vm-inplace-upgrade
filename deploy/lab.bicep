// Lab VM for verifying azure-vm-inplace-upgrade against a real guest.
//
// Deliberately minimal: no public IP, no inbound rules, no extensions. Every interaction goes
// through Run Command, and Setup progress is watched through boot diagnostics. Deallocate the VM
// between sessions and delete the resource group when done (see deploy/README.md).
targetScope = 'resourceGroup'

@description('Azure region. The upgrade media image exists in every public region.')
param location string = resourceGroup().location

@description('VM name; NIC and OS disk names derive from it.')
@minLength(1)
@maxLength(15)
param vmName string = 'vm-ipu-2022-01'

@description('Marketplace SKU of the source OS: 2022-datacenter-g2, 2022-datacenter-core-g2, 2019-datacenter-gensecond, 2016-datacenter-gensecond, 2012-r2-datacenter-gensecond.')
param imageSku string = '2022-datacenter-g2'

@description('VM size. Setup wants 2 vCPU and 4 GB or more; B2ms is enough and cheap.')
param vmSize string = 'Standard_B2ms'

@description('Security type. Standard first to isolate variables; TrustedLaunch is on the lab list.')
@allowed(['Standard', 'TrustedLaunch'])
param securityType string = 'Standard'

@description('Local administrator name. Never used interactively.')
param adminUsername string = 'ipuadmin'

@secure()
@description('Local administrator password. Generated per deployment, not stored anywhere.')
param adminPassword string

@description('Value of the UpgradeTarget tag written to the VM.')
param upgradeTarget string = 'WS2025'

@description('Tags applied to every resource.')
param tags object = {
  Environment: 'lab'
  Owner: 'simon'
  CostCenter: 'lab'
  Project: 'azure-vm-inplace-upgrade'
}

var vmTags = union(tags, {
  UpgradeTarget: upgradeTarget
  UpgradeState: 'Pending'
})

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-ipu-lab'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-ipu-lab'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.42.0.0/24']
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'snet-vms'
  properties: {
    addressPrefix: '10.42.0.0/26'
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${vmName}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: vmTags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        // Windows Update stays out of the picture so a run is reproducible; the FeatureUpdate
        // spike enables it deliberately.
        enableAutomaticUpdates: false
        patchSettings: {
          patchMode: 'Manual'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: imageSku
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-${vmName}'
        createOption: 'FromImage'
        diskSizeGB: 128
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: securityType == 'TrustedLaunch'
      ? {
          securityType: 'TrustedLaunch'
          uefiSettings: {
            secureBootEnabled: true
            vTpmEnabled: true
          }
        }
      : null
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

output vmName string = vm.name
output vmId string = vm.id
