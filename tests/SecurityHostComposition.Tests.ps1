BeforeAll {
    $source = Get-Content (Join-Path $PSScriptRoot '../components/bicep/security-automation-host/security-automation-host.bicep') -Raw
    $manifest = Get-Content (Join-Path $PSScriptRoot '../components/bicep/security-automation-host/component.json') -Raw | ConvertFrom-Json
}
Describe 'Additive security host composition source contract' {
    It 'versions the pilot and preserves existing consumer defaults' {
        $manifest.version | Should -BeExactly '0.2.0'
        $source | Should -Match "param automationRunbookName string = 'Invoke-SecurityReview'"
        $source | Should -Match "param automationRuntimeName string = 'SecurityPowerShell76'"
        $source | Should -Match "param automationScheduleName string = 'SecurityReviewSixHourly'"
        $source | Should -Match 'param scheduleIntervalHours int = 6'
        $source | Should -Match 'param scheduleEnabled bool = false'
        $source | Should -Match "param computeMode string = 'none'"
    }
    It 'wires solution-owned names and shared interval while protecting package and host settings' {
        $source | Should -Match 'name: automationRunbookName'
        $source | Should -Match 'name: automationRuntimeName'
        $source | Should -Match 'name: automationScheduleName'
        ([regex]::Matches($source, 'interval: scheduleIntervalHours')).Count | Should -Be 2
        ([regex]::Matches($source, 'parameters: union\(customJobParameters,')).Count | Should -Be 2
        $source | Should -Match "toLower\(item.key\)"
        $source | Should -Match "\['storageaccount', 'bundleblob', 'bundlesha256'\]"
        $source | Should -Match "'azurewebjobs.securityreview.disabled'"
        $source | Should -Match "'azurewebjobsstorage__credential'"
        $source | Should -Match 'appSettings: concat'
    }
    It 'does not infer adoption, permission unions or a shared security boundary' {
        $source | Should -Not -Match 'existingAutomation|Exchange.ManageAsApp|Organization Management|Microsoft.Graph'
        $source | Should -Match "identity: \{ type: 'SystemAssigned' \}"
        $source | Should -Match 'scheduleEnabled && bundleHashValid'
    }
}
