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
resource upgradeModule 'Microsoft.Automation/automationAccounts/powershell72Modules@2023-11-01' = {
  parent: automationAccount
  name: 'AzureInPlaceUpgrade'
  properties: {
    contentLink: {
      uri: modulePackageUri
    }
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

output principalId string = automationAccount.identity.principalId
output automationAccountId string = automationAccount.id
output workspaceId string = workspace.id
