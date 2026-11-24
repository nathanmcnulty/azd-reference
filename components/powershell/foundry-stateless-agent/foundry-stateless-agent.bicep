@description('Optional public-Azure Foundry resources. Disabled by default; the consumer hook separately creates and verifies the named prompt-agent version.')
param enabled bool = false
param location string = resourceGroup().location
@minLength(3)
@maxLength(64)
param accountName string
@minLength(2)
@maxLength(64)
param projectName string
@description('Explicit deployment name used by the prompt definition.')
@minLength(1)
@maxLength(128)
param modelDeploymentName string = 'gpt-6-luna'
@description('Catalog default checked 2026-10-15; verify region, SKU, version, quota and price before deployment. Never silently substitute another model.')
param modelName string = 'gpt-6-luna'
param modelVersion string = '2026-09-22'
@allowed(['Standard', 'GlobalStandard', 'DataZoneStandard'])
param modelSku string = 'GlobalStandard'
@minValue(1)
@maxValue(1000)
param modelCapacity int = 1
@description('Optional explicitly approved setup operator. Omit when its existing permissions suffice. Never pass the collection identity here.')
param setupPrincipalId string = ''
@allowed(['User', 'ServicePrincipal', 'Group'])
param setupPrincipalType string = 'User'
param tags object = {}

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = if (enabled) {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = if (enabled) {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: { displayName: projectName, description: 'Optional tool-free stateless advisory agent.' }
}
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (enabled) {
  parent: account
  name: modelDeploymentName
  sku: { name: modelSku, capacity: modelCapacity }
  properties: {
    model: { format: 'OpenAI', name: modelName, version: modelVersion }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}
// The new project's managed identity can use models in its own new Foundry account.
// This does not grant it access to any Microsoft 365 or solution data service.
var foundryUser = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
resource projectModelAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enabled) {
  scope: account
  name: guid(account.id, project.id, foundryUser)
  properties: {
    principalId: project!.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryUser)
  }
}
resource setupAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enabled && !empty(setupPrincipalId)) {
  scope: project
  name: guid(project.id, setupPrincipalId, foundryUser)
  properties: {
    principalId: setupPrincipalId
    principalType: setupPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryUser)
  }
}

output accountId string = enabled ? account.id : ''
output foundryAccountName string = enabled ? account.name : ''
output projectId string = enabled ? project.id : ''
output foundryProjectName string = enabled ? project.name : ''
output projectEndpoint string = enabled ? 'https://${account.name}.services.ai.azure.com/api/projects/${project.name}' : ''
output deployedModelName string = enabled ? deployment.name : ''
output selectedModelName string = enabled ? modelName : ''
output selectedModelVersion string = enabled ? modelVersion : ''
