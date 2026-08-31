targetScope = 'resourceGroup'

param location string = 'eastus2'

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'risk-fixture-workflow'
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
  name: 'risk-action-group-fixture'
  params: {
    actionGroupName: 'risk-fixture-action-group'
    groupShortName: 'Entra risk'
    logicAppResourceId: workflow.id
    receiverName: 'Risk notification workflow'
  }
}

module alert '../../../../components/bicep/azure-monitor-scheduled-query-notifications/scheduled-query-alert.bicep' = {
  name: 'risk-alert-fixture'
  params: {
    alertRuleName: 'risk-fixture-alert'
    location: location
    workspaceResourceId: workspace.id
    actionGroupResourceId: actionGroup.outputs.actionGroupResourceId
    displayName: 'Microsoft Entra risk detection'
    alertDescription: 'Representative Microsoft Entra risk alert.'
    query: '''
union withsource=SourceTable isfuzzy=true AADRiskyUsers, AADUserRiskEvents
| project TimeGenerated, Envelope
'''
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    autoMitigate: false
    dimensions: [
      {
        name: 'Envelope'
        operator: 'Include'
        values: [
          '*'
        ]
      }
    ]
  }
}
