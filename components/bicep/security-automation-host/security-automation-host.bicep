@description('Local mode provisions no resources. Logic App mode schedules the PowerShell Automation runbook.')
@allowed(['none', 'function', 'automation', 'logic-app'])
param computeMode string = 'none'
param location string = resourceGroup().location
@minLength(3)
@maxLength(20)
param resourceToken string
param solutionName string
@description('Keep scheduled processing disabled until evidence inputs and identity permissions are configured.')
param scheduleEnabled bool = false
param schedule string = '0 0 */6 * * *'
@description('Immutable uploaded bundle name for Automation modes.')
param bundleBlob string = 'unconfigured.zip'
param bundleSha256 string = ''
@description('Required future ISO 8601 UTC start time when enabling the Automation schedule.')
param automationScheduleStartTime string = '2030-01-01T00:00:00Z'
@description('Solution-owned names; changing names does not remove or pause retained resources.')
@minLength(1)
@maxLength(63)
param automationRunbookName string = 'Invoke-SecurityReview'
@minLength(1)
@maxLength(63)
param automationRuntimeName string = 'SecurityPowerShell76'
@minLength(1)
@maxLength(63)
param automationScheduleName string = 'SecurityReviewSixHourly'
@description('Hourly interval for Automation and Logic App modes; Function uses the separate NCRONTAB schedule.')
@minValue(1)
@maxValue(24)
param scheduleIntervalHours int = 6
@description('Additional non-secret runbook parameters. StorageAccount, BundleBlob and BundleSha256 are reserved; this component supplies them.')
param workerJobParameters object = {}
@description('Additional non-secret Function app settings; host-owned authentication, storage, schedule and disable settings always win.')
param workerAppSettings object = {}
@description('Enable Blob version history when the solution requires durable recovery; does not make evidence immutable.')
param blobVersioningEnabled bool = false
@description('Solution-owned description; the wrapper must publish and verify its reviewed runbook before enabling.')
param automationRunbookDescription string = 'Processes approved immutable evidence bundle. Upload and publish source before running.'
param tags object = {}
@description('Optional explicitly selected source publisher object ID; receives write access only to the package container.')
param sourcePublisherPrincipalId string = ''
@allowed(['User', 'ServicePrincipal', 'Group'])
param sourcePublisherPrincipalType string = 'User'

var customJobParameters = toObject(filter(items(workerJobParameters), item => !contains(['storageaccount', 'bundleblob', 'bundlesha256'], toLower(item.key))), item => item.key, item => string(item.value))
var customAppSettings = filter(items(workerAppSettings), item => !startsWith(toLower(item.key), 'azurewebjobsstorage') && !contains(['applicationinsights_connection_string', 'azurewebjobsstorage__accountname', 'azurewebjobsstorage__credential', 'security_storage_account', 'security_schedule', 'azurewebjobs.securityreview.disabled'], toLower(item.key)))
var hosted = computeMode != 'none'
var useFunction = computeMode == 'function'
var useAutomation = computeMode == 'automation' || computeMode == 'logic-app'
var blobContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var blobReader = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
var blobOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var jobOperator = '4fe576fe-1146-4730-92eb-48519fa6bf9f'
// Direct template callers also fail closed when an enabled package has not been configured.
var bundleHashValid = length(bundleSha256) == 64 && empty(filter(range(0, length(bundleSha256)), index => !contains('0123456789abcdef', substring(bundleSha256, index, 1))))
var effectiveScheduleEnabled = scheduleEnabled && bundleHashValid && bundleBlob == '${bundleSha256}.zip'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = if (hosted) {
  name: 'st${resourceToken}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}
resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = if (hosted) {
  parent: storage
  name: 'default'
  properties: { deleteRetentionPolicy: { enabled: true, days: 7 }, isVersioningEnabled: blobVersioningEnabled }
}
resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for name in ['evidence', 'reports', 'packages']: if (hosted) {
  parent: blobs
  name: name
  properties: { publicAccess: 'None' }
}]
resource functionStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = if (useFunction) {
  name: 'stf${resourceToken}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}
resource functionBlobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = if (useFunction) {
  parent: functionStorage
  name: 'default'
  properties: { deleteRetentionPolicy: { enabled: true, days: 7 } }
}
resource functionReleases 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = if (useFunction) {
  parent: functionBlobs
  name: 'function-releases'
  properties: { publicAccess: 'None' }
}
resource sourcePublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (hosted && !empty(sourcePublisherPrincipalId)) {
  scope: containers[2]
  name: guid(containers[2].id, sourcePublisherPrincipalId, blobContributor)
  properties: {
    principalId: sourcePublisherPrincipalId
    principalType: sourcePublisherPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobContributor)
  }
}
resource plan 'Microsoft.Web/serverfarms@2024-04-01' = if (useFunction) {
  name: 'plan-${resourceToken}'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: { name: 'FC1', tier: 'FlexConsumption' }
  properties: { reserved: true }
}
resource diagnosticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (useFunction) {
  name: 'log-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    workspaceCapping: { dailyQuotaGb: json('0.1') }
  }
}
resource diagnostics 'Microsoft.Insights/components@2020-02-02' = if (useFunction) {
  name: 'appi-${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: diagnosticsWorkspace.id
  }
}
resource function 'Microsoft.Web/sites@2024-04-01' = if (useFunction) {
  name: 'func-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': 'security' })
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: concat([
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: diagnostics!.properties.ConnectionString }
        { name: 'AzureWebJobsStorage__accountName', value: functionStorage.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'SECURITY_STORAGE_ACCOUNT', value: storage.name }
        { name: 'SECURITY_SCHEDULE', value: schedule }
        { name: 'AzureWebJobs.SecurityReview.Disabled', value: string(!effectiveScheduleEnabled) }
      ], map(customAppSettings, item => { name: item.key, value: string(item.value) }))
    }
    functionAppConfig: {
      runtime: { name: 'powershell', version: '7.6' }
      scaleAndConcurrency: { maximumInstanceCount: 1, instanceMemoryMB: 2048 }
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${functionStorage!.properties.primaryEndpoints.blob}function-releases'
          authentication: { type: 'SystemAssignedIdentity' }
        }
      }
    }
  }
  dependsOn: [containers, functionReleases]
}
resource functionRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in [blobOwner]: if (useFunction) {
  scope: functionStorage
  name: guid(functionStorage.id, function.id, role)
  properties: {
    principalId: function!.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role)
  }
}]
resource automation 'Microsoft.Automation/automationAccounts@2024-10-23' = if (useAutomation) {
  name: 'aa-${resourceToken}'
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: { sku: { name: 'Basic' }, disableLocalAuth: true }
}
resource runtime 'Microsoft.Automation/automationAccounts/runtimeEnvironments@2024-10-23' = if (useAutomation) {
  parent: automation
  name: automationRuntimeName
  location: location
  properties: { runtime: { language: 'PowerShell', version: '7.6' } }
}
resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = if (useAutomation) {
  parent: automation
  name: automationRunbookName
  location: location
  properties: {
    runbookType: 'PowerShell'
    runtimeEnvironment: runtime.name
    description: automationRunbookDescription
    logProgress: false
    logVerbose: false
    draft: {}
  }
}
resource functionEvidenceReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (useFunction) {
  scope: containers[0]
  name: guid(containers[0].id, function.id, blobReader)
  properties: {
    principalId: function!.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobReader)
  }
}
resource functionReportWriter 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (useFunction) {
  scope: containers[1]
  name: guid(containers[1].id, function.id, blobContributor)
  properties: {
    principalId: function!.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobContributor)
  }
}
resource automationReaders 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for index in [0, 2]: if (useAutomation) {
  scope: containers[index]
  name: guid(containers[index].id, automation.id, blobReader)
  properties: {
    principalId: automation!.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobReader)
  }
}]
resource automationReportWriter 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (useAutomation) {
  scope: containers[1]
  name: guid(containers[1].id, automation.id, blobContributor)
  properties: {
    principalId: automation!.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobContributor)
  }
}
resource automationSchedule 'Microsoft.Automation/automationAccounts/schedules@2024-10-23' = if (computeMode == 'automation' && effectiveScheduleEnabled) {
  parent: automation
  name: automationScheduleName
  properties: {
    frequency: 'Hour'
    interval: scheduleIntervalHours
    startTime: automationScheduleStartTime
    timeZone: 'Etc/UTC'
    description: 'Set a future start time and approved package hash before enabling.'
  }
}
resource jobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2024-10-23' = if (computeMode == 'automation' && effectiveScheduleEnabled) {
  parent: automation
  name: guid(automation.id, runbook.name, automationSchedule.name)
  properties: {
    runbook: { name: runbook.name }
    schedule: { name: automationSchedule.name }
    parameters: union(customJobParameters, { StorageAccount: storage.name, BundleBlob: bundleBlob, BundleSha256: bundleSha256 })
  }
}
resource workflow 'Microsoft.Logic/workflows@2019-05-01' = if (computeMode == 'logic-app') {
  name: 'logic-${resourceToken}'
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    state: effectiveScheduleEnabled ? 'Enabled' : 'Disabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        Every_six_hours: { type: 'Recurrence', recurrence: { frequency: 'Hour', interval: scheduleIntervalHours } }
      }
      actions: {
        Start_review: {
          type: 'Http'
          inputs: {
            method: 'PUT'
            uri: '${environment().resourceManager}${automation.id}/jobs/@{guid()}?api-version=2024-10-23'
            authentication: { type: 'ManagedServiceIdentity', audience: environment().resourceManager }
            body: {
              properties: {
                runbook: { name: runbook.name }
                parameters: union(customJobParameters, { StorageAccount: storage.name, BundleBlob: bundleBlob, BundleSha256: bundleSha256 })
              }
            }
          }
          runAfter: {}
        }
      }
      outputs: {}
    }
  }
}
resource workflowJobs 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (computeMode == 'logic-app') {
  scope: automation
  name: guid(automation.id, workflow.id, jobOperator)
  properties: {
    principalId: workflow!.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', jobOperator)
  }
}

output storageAccountName string = hosted ? storage.name : ''
output functionAppName string = useFunction ? function.name : ''
output automationAccountName string = useAutomation ? automation.name : ''
output runbookName string = useAutomation ? runbook.name : ''
output workflowName string = computeMode == 'logic-app' ? workflow.name : ''
output principalId string = useFunction ? function!.identity.principalId : (useAutomation ? automation!.identity.principalId : '')
output solution string = solutionName
output scheduledProcessingEnabled bool = effectiveScheduleEnabled && hosted

output runtimeName string = useAutomation ? runtime.name : ''
output scheduleName string = computeMode == 'automation' ? automationScheduleName : ''
output automationAccountId string = useAutomation ? automation.id : ''
output storageAccountId string = hosted ? storage.id : ''
output blobEndpoint string = hosted ? storage!.properties.primaryEndpoints.blob : ''
output functionAppId string = useFunction ? function.id : ''
output workflowId string = computeMode == 'logic-app' ? workflow.id : ''
