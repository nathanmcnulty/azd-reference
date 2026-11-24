targetScope = 'resourceGroup'

param location string = 'eastus2'
param workspaceName string = 'fixture-workspace'
param actionGroupName string = 'fixture-action-group'
param alertRuleName string = 'automation-fixture-alert'
param query string = 'AzureDiagnostics | where Category == "JobLogs" and ResultType == "Failed"'
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' existing = {
  name: actionGroupName
}

module alert '../../../../components/bicep/azure-monitor-scheduled-query-notifications/scheduled-query-alert.bicep' = {
  name: 'automation-alert-fixture'
  params: {
    alertRuleName: alertRuleName
    location: location
    workspaceResourceId: workspace.id
    actionGroupResourceId: actionGroup.id
    displayName: 'Automation diagnostic failure'
    alertDescription: 'Delayed-ingestion window fixture; delivery is separately qualified.'
    query: query
    evaluationFrequency: 'PT5M'
    windowSize: 'PT30M'
    autoMitigate: false
    tags: tags
  }
}

output alertRuleResourceId string = alert.outputs.alertRuleResourceId
