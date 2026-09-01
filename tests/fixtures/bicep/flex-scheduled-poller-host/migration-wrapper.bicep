targetScope = 'resourceGroup'

module poller '../../../../components/bicep/flex-scheduled-poller-host/flex-scheduled-poller-host.bicep' = {
  name: 'poller-migration-fixture'
  params: {
    storageAccountName: 'stpollerfixture'
    functionPlanName: 'plan-poller-fixture'
    functionAppName: 'func-poller-fixture'
    location: resourceGroup().location
    environmentName: 'fixture'
    serviceName: 'fixture-poller'
    deploymentContainerName: 'existing-releases'
    stateContainerName: 'existing-state'
    deadLetterContainerName: 'existing-dead-letter'
    applicationSettings: {
      POLLER_SCHEDULE: '0 */5 * * * *'
      AZD_POLLER_STATE_CONTAINER: 'must-be-overridden'
    }
    storageAccountSettingAliases: [
      'LEGACY_STORAGE'
      'AZD_POLLER_STORAGE_ACCOUNT_NAME'
    ]
    stateContainerSettingAliases: [
      'LEGACY_STATE'
      'LEGACY_STORAGE'
    ]
    deadLetterContainerSettingAliases: [
      'LEGACY_DEAD_LETTER'
      'LEGACY_STATE'
    ]
    instanceMemoryMB: 512
    maximumInstanceCount: 1
    blobDeleteRetentionDays: 14
    tags: {
      fixture: 'true'
    }
  }
}

output functionAppName string = poller.outputs.functionAppName
