// Resource-group scope: Automation Account with identity, Log Analytics, module imports, the
// runbook and its two schedules. Called from main.bicep, which owns the role and its assignment.
targetScope = 'resourceGroup'

param location string
param automationAccountName string
param logAnalyticsWorkspaceName string
param logRetentionDays int
param tags object

@description('Where the AzureInPlaceUpgrade module package comes from. PowerShell Gallery URL by default, or a GitHub release asset before the first Gallery release.')
param modulePackageUri string

@description('Raw URL of the runbook script. Pinned to a tag or commit in production.')
param runbookContentUri string

@description('Version stamp for the module package and runbook content. Change it to force a re-import.')
param contentVersion string

param subscriptionIdForJobs string
param ring string
param maxParallel int
param timeoutMinutes int
param checkIntervalMinutes int
param startScheduleTime string
param startScheduleEnabled bool
param scheduleTimeZone string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Custom table for one record per state transition. The column list is the contract with
// ConvertTo-UpgradeRecord in the module and with the stream declaration of the rule below.
var recordColumns = [
  { name: 'TimeGenerated', type: 'datetime' }
  { name: 'VMName', type: 'string' }
  { name: 'ResourceGroupName', type: 'string' }
  { name: 'Target', type: 'string' }
  { name: 'State', type: 'string' }
  { name: 'Result', type: 'string' }
  { name: 'Reason', type: 'string' }
  { name: 'Engine', type: 'string' }
  { name: 'SourceBuild', type: 'int' }
  { name: 'TargetBuild', type: 'int' }
  { name: 'ImageIndex', type: 'int' }
  { name: 'DurationMinutes', type: 'int' }
  { name: 'TaskResult', type: 'string' }
  { name: 'Snapshot', type: 'string' }
  { name: 'MediaDisk', type: 'string' }
  { name: 'Mode', type: 'string' }
  { name: 'JobId', type: 'string' }
  { name: 'ModuleVersion', type: 'string' }
  { name: 'LogExcerpt', type: 'string' }
]

resource recordTable 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = {
  parent: workspace
  name: 'InPlaceUpgrade_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: logRetentionDays
    schema: {
      name: 'InPlaceUpgrade_CL'
      columns: recordColumns
    }
  }
}

resource collectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: 'dce-${automationAccountName}'
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource collectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-${automationAccountName}'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: collectionEndpoint.id
    streamDeclarations: {
      'Custom-InPlaceUpgrade_CL': {
        columns: recordColumns
      }
    }
    destinations: {
      logAnalytics: [
        {
          name: 'workspace'
          workspaceResourceId: workspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-InPlaceUpgrade_CL' ]
        destinations: [ 'workspace' ]
        transformKql: 'source'
        outputStream: 'Custom-InPlaceUpgrade_CL'
      }
    ]
  }
  dependsOn: [
    recordTable
  ]
}

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    publicNetworkAccess: true
    disableLocalAuth: true
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: automationAccount
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        category: 'JobLogs'
        enabled: true
      }
      {
        category: 'JobStreams'
        enabled: true
      }
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
  }
}

// No Az module imports on purpose. The PowerShell 7.2 runtime ships a global Az bundle
// (11.2.0 at the time of writing: Az.Accounts 2.15.0, Az.Compute 7.1.1, Az.Resources 6.13.0).
// Importing a newer Az.Accounts next to it broke assembly loading in the sandbox
// ("Unable to find type AzAssemblyLoadContextInitializer", MSAL assembly not found) - observed
// 2026-09-05. The module's manifest minimums match the runtime defaults instead.
// The version property is what makes ARM re-import when the package behind the same URI
// changed; without it a redeploy with an unchanged URI is a no-op.
resource upgradeModule 'Microsoft.Automation/automationAccounts/powershell72Modules@2023-11-01' = {
  parent: automationAccount
  name: 'AzureInPlaceUpgrade'
  properties: {
    contentLink: {
      uri: modulePackageUri
      version: contentVersion
    }
  }
}

// Telemetry target as Automation variables: the runbook reads them when its own parameters
// are empty. Job schedules are immutable once linked, variables can be updated by redeploying.
resource variableEndpoint 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount
  name: 'InPlaceUpgrade-LogIngestionEndpoint'
  properties: {
    isEncrypted: false
    value: '"${collectionEndpoint.properties.logsIngestion.endpoint}"'
    description: 'Logs ingestion endpoint of the data collection endpoint for InPlaceUpgrade_CL.'
  }
}

resource variableRule 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount
  name: 'InPlaceUpgrade-DataCollectionRuleId'
  properties: {
    isEncrypted: false
    value: '"${collectionRule.properties.immutableId}"'
    description: 'Immutable id of the data collection rule that routes Custom-InPlaceUpgrade_CL.'
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Invoke-InPlaceUpgradeRunbook'
  location: location
  tags: tags
  properties: {
    // 'PowerShell72' selects the PowerShell 7.2 runtime; 'PowerShell' would be Windows PowerShell 5.1.
    runbookType: 'PowerShell72'
    logProgress: false
    logVerbose: false
    description: 'Tag-driven in-place upgrades: Start once per maintenance window, Check every few minutes.'
    publishContentLink: {
      uri: runbookContentUri
      version: contentVersion
    }
  }
  dependsOn: [
    upgradeModule
  ]
}

resource checkSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'inplaceupgrade-check'
  properties: {
    description: 'Evaluates VMs in UpgradeStarted and finishes them.'
    frequency: 'Minute'
    interval: checkIntervalMinutes
    startTime: startScheduleTime
    timeZone: scheduleTimeZone
  }
}

// The ARM API cannot create a disabled schedule, so the Start schedule always exists and only
// gets linked to the runbook (the job schedule below) when startScheduleEnabled is true.
resource startSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'inplaceupgrade-start'
  properties: {
    description: 'Starts upgrades for VMs in UpgradeState=Pending, up to MaxParallel. Linked to the runbook only when enabled at deployment.'
    frequency: 'Day'
    interval: 1
    startTime: startScheduleTime
    timeZone: scheduleTimeZone
  }
}

resource checkJob 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.id, 'check', runbook.name)
  properties: {
    schedule: {
      name: checkSchedule.name
    }
    runbook: {
      name: runbook.name
    }
    parameters: {
      SubscriptionId: subscriptionIdForJobs
      Mode: 'Check'
      Ring: ring
      TimeoutMinutes: string(timeoutMinutes)
    }
  }
}

resource startJob 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (startScheduleEnabled) {
  parent: automationAccount
  name: guid(automationAccount.id, 'start', runbook.name)
  properties: {
    schedule: {
      name: startSchedule.name
    }
    runbook: {
      name: runbook.name
    }
    parameters: {
      SubscriptionId: subscriptionIdForJobs
      Mode: 'Start'
      Ring: ring
      MaxParallel: string(maxParallel)
    }
  }
}

// Monitoring Metrics Publisher: the only role the Logs Ingestion API accepts for a writer.
resource metricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(collectionRule.id, automationAccount.id, '3913510d-42f4-4e42-8a64-420c390055eb')
  scope: collectionRule
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(workspace.id, 'inplaceupgrade-workbook')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'In-place upgrades'
    category: 'workbook'
    sourceId: workspace.id
    version: '1.0'
    serializedData: replace(loadTextContent('workbook.json'), '{workspaceId}', workspace.id)
  }
}

output principalId string = automationAccount.identity.principalId
output logIngestionEndpoint string = collectionEndpoint.properties.logsIngestion.endpoint
output dataCollectionRuleId string = collectionRule.properties.immutableId
output automationAccountId string = automationAccount.id
output workspaceId string = workspace.id
