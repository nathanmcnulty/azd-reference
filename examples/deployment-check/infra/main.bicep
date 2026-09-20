targetScope = 'subscription'

@minLength(2)
param environmentName string

param location string

var resourceGroupName = 'rg-${environmentName}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
