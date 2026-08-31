targetScope = 'resourceGroup'

param location string = 'eastus2'

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'pim-fixture-workflow'
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
            }
          }
        }
      }
      actions: {}
      outputs: {}
    }
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: 'fixture-workspace'
}

module actionGroup '../../../../components/bicep/azure-monitor-scheduled-query-notifications/logic-app-action-group.bicep' = {
  name: 'pim-action-group-fixture'
  params: {
    actionGroupName: 'pim-fixture-action-group'
    groupShortName: 'PIM Entra'
    logicAppResourceId: workflow.id
    receiverName: 'PIM activation Teams workflow'
  }
}

module alert '../../../../components/bicep/azure-monitor-scheduled-query-notifications/scheduled-query-alert.bicep' = {
  name: 'pim-alert-fixture'
  params: {
    alertRuleName: 'pim-fixture-alert'
    location: location
    workspaceResourceId: workspace.id
    actionGroupResourceId: actionGroup.outputs.actionGroupResourceId
    displayName: 'Microsoft Entra PIM activation completed'
    alertDescription: 'Representative PIM activation alert.'
    query: '''
AuditLogs
| where LoggedByService == "PIM"
| project TimeGenerated, ActivationEventId, CorrelationId, Actor, Role
'''
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    autoMitigate: true
    dimensions: [
      {
        name: 'ActivationEventId'
        operator: 'Include'
        values: [
          '*'
        ]
      }
      {
        name: 'CorrelationId'
        operator: 'Include'
        values: [
          '*'
        ]
      }
      {
        name: 'Actor'
        operator: 'Include'
        values: [
          '*'
        ]
      }
      {
        name: 'Role'
        operator: 'Include'
        values: [
          '*'
        ]
      }
    ]
  }
}
