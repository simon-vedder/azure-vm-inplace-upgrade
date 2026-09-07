// Subscription-scope deployment of the orchestrator: resource group, Automation Account with a
// system-assigned identity, the least-privilege role it needs, Log Analytics, module imports,
// runbook and schedules. Subscription scope because a custom role definition lives there.
//
//   az deployment sub create -l westeurope -f deploy/main.bicep -p moduleVersion=0.3.1-preview
//
// Nothing starts an upgrade by itself: the Start schedule is disabled until an operator enables
// it, and only VMs tagged UpgradeState=Pending are ever touched.
targetScope = 'subscription'

@description('Region for the resource group and everything in it.')
param location string = 'westeurope'

param resourceGroupName string = 'rg-inplaceupgrade-weu'
param automationAccountName string = 'aa-inplaceupgrade-weu'
param logAnalyticsWorkspaceName string = 'log-inplaceupgrade-weu'

@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('AzureInPlaceUpgrade module version on the PowerShell Gallery.')
param moduleVersion string

@description('Version stamp written to the module and runbook content links, System.Version form (up to four numeric parts, e.g. 0.3.0.1). Defaults to moduleVersion with any pre-release suffix stripped, because Automation rejects one; bump it to force Automation to re-import unchanged URIs.')
@minLength(0)
param contentVersion string = ''

@description('Override the module package source, for example a GitHub release asset before the first Gallery release. Empty means the Gallery URL for moduleVersion.')
param modulePackageUri string = ''

@description('Raw URL of the runbook wrapper. Pin to a tag in production.')
param runbookContentUri string = 'https://raw.githubusercontent.com/simon-vedder/azure-vm-inplace-upgrade/main/src/runbooks/Invoke-InPlaceUpgradeRunbook.ps1'

@description('Resource group the identity gets the operator role on. Empty assigns the role at subscription scope.')
param targetResourceGroupName string = ''

@description('Only VMs with this UpgradeRing tag are processed by the schedules. Empty means any ring.')
param ring string = ''

@minValue(1)
@maxValue(50)
param maxParallel int = 3

@minValue(30)
@maxValue(1440)
param timeoutMinutes int = 240

@minValue(15)
@maxValue(60)
param checkIntervalMinutes int = 20

@description('First run of both schedules, ISO 8601. Must be at least five minutes in the future; defaults to one hour from deployment.')
param scheduleStartTime string = dateTimeAdd(baseTime, 'PT1H')

param scheduleTimeZone string = 'Etc/UTC'

@description('Enable the Start schedule at deployment. Off by default; enable it when the first ring is approved.')
param startScheduleEnabled bool = false

@description('How often Start looks for work. Daily is the default on purpose: it makes scheduleStartTime a maintenance window, so upgrades begin at an hour you chose. Set it to Hour for a migration wave, when you want freed slots refilled the same day.')
@allowed([
  'Day'
  'Hour'
])
param startScheduleFrequency string = 'Day'

@description('Interval for the Start schedule, in units of startScheduleFrequency. Throughput ceiling is maxParallel VMs per Start run: with the daily default and maxParallel 3, three VMs a day begin upgrading.')
@minValue(1)
@maxValue(24)
param startScheduleInterval int = 1

param roleName string = 'Azure VM In-Place Upgrade Operator'

param tags object = {
  Project: 'azure-vm-inplace-upgrade'
}

param baseTime string = utcNow()

var effectiveModuleUri = empty(modulePackageUri)
  ? 'https://www.powershellgallery.com/api/v2/package/AzureInPlaceUpgrade/${moduleVersion}'
  : modulePackageUri

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module automation 'modules/automation.bicep' = {
  name: 'automation'
  scope: resourceGroup
  params: {
    location: location
    automationAccountName: automationAccountName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    logRetentionDays: logRetentionDays
    tags: tags
    modulePackageUri: effectiveModuleUri
    runbookContentUri: runbookContentUri
    contentVersion: empty(contentVersion) ? split(moduleVersion, '-')[0] : contentVersion
    subscriptionIdForJobs: subscription().subscriptionId
    ring: ring
    maxParallel: maxParallel
    timeoutMinutes: timeoutMinutes
    checkIntervalMinutes: checkIntervalMinutes
    startScheduleTime: scheduleStartTime
    startScheduleEnabled: startScheduleEnabled
    startScheduleFrequency: startScheduleFrequency
    startScheduleInterval: startScheduleInterval
    scheduleTimeZone: scheduleTimeZone
  }
}

// Exactly what Start-InPlaceUpgrade and Complete-InPlaceUpgrade call, nothing else. Reader is
// not enough (Run Command, tags); Virtual Machine Contributor could delete VMs.
resource operatorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, roleName)
  properties: {
    roleName: roleName
    description: 'Preflight, snapshot, media disk, Run Command and tag writes for tag-driven in-place upgrades of Windows Server VMs.'
    type: 'CustomRole'
    assignableScopes: [
      subscription().id
    ]
    permissions: [
      {
        actions: [
          'Microsoft.Compute/virtualMachines/read'
          'Microsoft.Compute/virtualMachines/write'
          'Microsoft.Compute/virtualMachines/instanceView/read'
          'Microsoft.Compute/virtualMachines/runCommand/action'
          'Microsoft.Compute/disks/read'
          'Microsoft.Compute/disks/write'
          'Microsoft.Compute/disks/delete'
          'Microsoft.Compute/snapshots/read'
          'Microsoft.Compute/snapshots/write'
          'Microsoft.Compute/locations/publishers/read'
          'Microsoft.Compute/locations/publishers/artifacttypes/offers/read'
          'Microsoft.Compute/locations/publishers/artifacttypes/offers/skus/read'
          'Microsoft.Compute/locations/publishers/artifacttypes/offers/skus/versions/read'
          'Microsoft.Network/networkInterfaces/join/action'
          'Microsoft.Resources/tags/write'
          'Microsoft.Resources/subscriptions/read'
          'Microsoft.Resources/subscriptions/resourceGroups/read'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

module assignAtSubscription 'modules/role-assignment-subscription.bicep' = if (empty(targetResourceGroupName)) {
  name: 'operator-role-assignment-subscription'
  params: {
    principalId: automation.outputs.principalId
    roleDefinitionId: operatorRole.id
  }
}

module assignAtResourceGroup 'modules/role-assignment-resourcegroup.bicep' = if (!empty(targetResourceGroupName)) {
  name: 'operator-role-assignment-resourcegroup'
  scope: az.resourceGroup(targetResourceGroupName)
  params: {
    principalId: automation.outputs.principalId
    roleDefinitionId: operatorRole.id
  }
}

output automationAccountId string = automation.outputs.automationAccountId
output principalId string = automation.outputs.principalId
output roleDefinitionId string = operatorRole.id
output workspaceId string = automation.outputs.workspaceId
output logIngestionEndpoint string = automation.outputs.logIngestionEndpoint
output dataCollectionRuleId string = automation.outputs.dataCollectionRuleId
