targetScope = 'resourceGroup'

@description('Deploy this template into the management resource group, separate from the workload group.')
param location string = resourceGroup().location

@minLength(3)
@maxLength(64)
param identityName string

@description('Exact GitHub owner/repository; review the protected environment and workflow before granting access.')
@minLength(3)
param repository string

@minLength(1)
param githubEnvironment string

param workloadSubscriptionId string
param workloadResourceGroup string

@description('Reviewed lab ownership marker; this does not grant permissions.')
param owner string = 'unassigned'

@description('Explicit operator bootstrap only. Default creates no role assignment. Graph and runtime role bootstrap remain separate.')
param grantContributor bool = false

resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: {
    solution: 'lab-platform'
    'lab-environment': 'lab'
    owner: owner
    'cost-center': 'azd-lab'
    portfolio: 'azd'
    'managed-by': 'azd-lab'
    repository: repository
    'github-environment': githubEnvironment
    purpose: 'deployment'
  }
}

resource federation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: deployIdentity
  name: 'github-environment'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${repository}:environment:${githubEnvironment}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

resource workloadGroup 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: workloadResourceGroup
  scope: subscription(workloadSubscriptionId)
}

// A workload deployer must not gain Contributor access to its own federation.
// A mistaken equal scope fails closed: no assignment, and the output exposes it.
var isolatedScope = toLower('${workloadSubscriptionId}/${workloadResourceGroup}') != toLower('${subscription().subscriptionId}/${resourceGroup().name}')

module workloadRole './workload-role.bicep' = if (grantContributor && isolatedScope) {
  name: 'deployment-role-${uniqueString(deployIdentity.id, workloadGroup.id)}'
  scope: workloadGroup
  params: {
    principalId: deployIdentity.properties.principalId
  }
}

output identityResourceId string = deployIdentity.id
output clientId string = deployIdentity.properties.clientId
output principalId string = deployIdentity.properties.principalId
output federatedSubject string = federation.properties.subject
output workloadScope string = workloadGroup.id
output roleGrantRequested bool = grantContributor
output roleGrantAllowed bool = isolatedScope
output contributorGranted bool = grantContributor && isolatedScope
