#Requires -Version 7.6
BeforeAll {
    $root = Split-Path $PSScriptRoot
    $script:fixture = Join-Path $root 'examples/cost-pilot'
    $script:cli = Join-Path $root 'tooling/Get-AzdCostEstimate.ps1'
    $script:schema = Join-Path $root 'schemas/cost-result.schema.json'
    $script:sourcePaths = @(Get-ChildItem (Join-Path $script:fixture 'profiles') -Filter '*.json' | ForEach-Object FullName)
    $script:defaultPricePath = Join-Path $script:fixture 'prices.json'
    $script:defaultRequestPath = Join-Path $script:fixture 'request.json'

    function Invoke-CostFixture {
        param([hashtable]$Override, [string[]]$Profiles = $script:sourcePaths, [string]$PricePath = $script:defaultPricePath, [string]$MeasurementPath)
        $requestPath = $script:defaultRequestPath
        if ($Override) {
            $request = Get-Content $requestPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
            foreach ($key in $Override.Keys) { $request[$key] = $Override[$key] }
            $requestPath = Join-Path $TestDrive 'request.json'
            $request | ConvertTo-Json -Depth 12 | Set-Content $requestPath -Encoding utf8
        }
        & $script:cli -ProfilePath $Profiles -PricePath $PricePath -RequestPath $requestPath -MeasurementPath $MeasurementPath
    }
}

Describe 'Offline cost pilot' {
    It 'conforms to the versioned result and renders the exact CLI amounts in the GUI' {
        $json = Invoke-CostFixture
        Test-Json -Json $json -SchemaFile $script:schema -ErrorAction Stop | Should -BeTrue
        $result = $json | ConvertFrom-Json
        $result.periodDays | Should -Be 31
        $result.profiles.id | Should -Be @('auth-notifications', 'maester-functionapp', 'sysmon')
        $result.profiles.runs | Should -Be @(8928, 4, 0)
        $result.portfolio.knownTotal.low | Should -BeExactly '1324.21'
        $result.portfolio.knownTotal.base | Should -BeExactly '3916.65'
        $result.portfolio.knownTotal.high | Should -BeExactly '11677.07'
        $result.complete | Should -BeTrue
        $reversed = $script:sourcePaths[2..0]
        Invoke-CostFixture -Profiles $reversed | Should -BeExactly $json
        $json | & node (Join-Path $script:fixture 'gui/check-view.cjs')
        $LASTEXITCODE | Should -Be 0
    }

    It 'varies the users and devices independently and grows retained usage up to the selected window' {
        $result = Invoke-CostFixture -Override @{users = 0; devices = 200; priorRetentionDays = 80} | ConvertFrom-Json
        $collection = $result.profiles[0].lines | Where-Object id -EQ 'collection'
        $retention = $result.profiles[2].lines | Where-Object id -EQ 'retention'
        $collection.quantity.base | Should -Be 0
        $retention.quantity.base | Should -Be 540
        $younger = Invoke-CostFixture -Override @{users = 1000; devices = 200; priorRetentionDays = 0} | ConvertFrom-Json
        ($younger.profiles[0].lines | Where-Object id -EQ 'collection').quantity.base | Should -Be 20
        ($younger.profiles[2].lines | Where-Object id -EQ 'retention').quantity.base | Should -Be 186
    }

    It 'reports stale and missing prices explicitly and refuses regional substitutions' {
        $stale = Invoke-CostFixture -Override @{asOf = '2026-05-01'; includeOneTime = $false} | ConvertFrom-Json
        $stale.complete | Should -BeFalse
        ($stale.profiles[0].lines | Where-Object id -EQ 'duration').status | Should -BeExactly 'stale'
        ($stale.profiles[0].lines | Where-Object id -EQ 'deploy-storage').status | Should -BeExactly 'excluded'
        ($stale.profiles[2].lines | Where-Object id -EQ 'analytics').status | Should -BeExactly 'stale'
        $otherRegion = Invoke-CostFixture -Override @{region = 'westus2'} | ConvertFrom-Json
        ($otherRegion.profiles[0].lines | Where-Object id -EQ 'duration').incremental | Should -BeNullOrEmpty
        $otherRegion.complete | Should -BeFalse
        $prices = Get-Content $script:defaultPricePath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
        ($prices.observations | Where-Object service -EQ 'sentinel').sku = 'different-sku'
        $testPricePath = Join-Path $TestDrive 'mismatched-price.json'
        $prices | ConvertTo-Json -Depth 12 | Set-Content $testPricePath
        $differentSku = Invoke-CostFixture -PricePath $testPricePath | ConvertFrom-Json
        ($differentSku.profiles[2].lines | Where-Object id -EQ 'analytics').status | Should -BeExactly 'missing'
        $differentSku.portfolio.knownTotal.base | Should -BeExactly '2521.65'
    }

    It 'uses only reviewed options and labels a genuinely zero-priced local configuration' {
        $selection = @(@{profile = 'sysmon'; configuration = 'local-only'})
        $result = Invoke-CostFixture -Override @{selections = $selection} | ConvertFrom-Json
        $result.complete | Should -BeTrue
        $result.profiles[0].options.workspace | Should -BeFalse
        $result.portfolio.knownTotal.base | Should -BeExactly '0.00'
        { Invoke-CostFixture -Override @{selections = @(@{profile = 'sysmon'; configuration = 'data-lake'})} } |
            Should -Throw '*Unknown or ambiguous configuration*'
    }

    It 'allocates a shared grant once across profiles and an explicitly scoped shared resource once' {
        $current = Invoke-CostFixture | ConvertFrom-Json
        ($current.profiles[0].lines | Where-Object id -EQ 'executions').grantApplied.base | Should -Be 8900
        $maester = $current.profiles[1].lines | Where-Object id -EQ 'executions'
        $maester.grantApplied.base | Should -Be 0
        $maester.standalone.base | Should -BeExactly '0.00'
        $maester.incremental.base | Should -BeExactly '0.01'
        $profiles = @(foreach ($source in $script:sourcePaths) {
            $profile = Get-Content $source -Raw | ConvertFrom-Json -AsHashtable
            foreach ($configuration in $profile.configurations) {
                foreach ($line in $configuration.lines | Where-Object id -In 'state', 'reports') {
                    $line.sharedResource = 'existing-test-storage'
                    $line.allowedScope = 'pilot-shared-subscription'
                    $line.factors = @{low = 1; base = 1; high = 1}
                }
            }
            $path = Join-Path $TestDrive "$($profile.id).json"
            $profile | ConvertTo-Json -Depth 12 | Set-Content $path
            $path
        })
        $shared = Invoke-CostFixture -Profiles $profiles | ConvertFrom-Json
        $shared.portfolio.fixed.base | Should -BeExactly '0.20'
        ($shared.profiles[1].lines | Where-Object id -EQ 'reports').allocatedElsewhere | Should -BeTrue
        $shared.profiles[1].standalone.fixed.base | Should -BeExactly '0.20'
    }

    It 'binds optional partial measured usage without changing any estimate' {
        $measurementPath = Join-Path $TestDrive 'measurement.json'
        @{schemaVersion = '1.0'; observations = @(@{
            profile = 'sysmon'; line = 'ingestion'; revision = '30fe2bc87be0d417151990a8714f81eb3ec5b84d'
            configuration = 'existing-sentinel'; periodStart = '2026-01-01'; observedOn = '2026-02-01'
            unit = 'gb'; quantity = 12; coverage = 'partial'; source = 'Synthetic observation'
        })} | ConvertTo-Json -Depth 8 | Set-Content $measurementPath
        $measured = Invoke-CostFixture -MeasurementPath $measurementPath | ConvertFrom-Json
        $measured.portfolio.knownTotal.base | Should -BeExactly '3916.65'
        ($measured.profiles[2].lines | Where-Object id -EQ 'ingestion').measurement.coverage | Should -BeExactly 'partial'
        ($measured.profiles[2].lines | Where-Object id -EQ 'analytics').measurement | Should -BeNullOrEmpty
    }
}
