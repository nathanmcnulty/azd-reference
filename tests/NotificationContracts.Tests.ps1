BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:envelopeSchema = Join-Path $script:repositoryRoot 'schemas/notification-envelope.schema.json'
    $script:resultSchema = Join-Path $script:repositoryRoot 'schemas/notification-delivery-result.schema.json'
    $script:envelopeFixture = Join-Path $PSScriptRoot 'fixtures/valid/notification-envelope.json'
    $script:resultFixture = Join-Path $PSScriptRoot 'fixtures/valid/notification-delivery-result.json'
    $script:safetyTool = Join-Path $script:repositoryRoot 'tooling/Test-AzdNotificationContractSafety.ps1'

    function Get-PropertyNameRecursive {
        param([AllowNull()][object] $Value)

        if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return @() }
        $names = [System.Collections.Generic.List[string]]::new()
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($key in $Value.Keys) {
                $names.Add([string] $key)
                foreach ($child in @(Get-PropertyNameRecursive -Value $Value[$key])) { $names.Add($child) }
            }
        }
        elseif ($Value -is [System.Collections.IEnumerable]) {
            foreach ($item in $Value) {
                foreach ($child in @(Get-PropertyNameRecursive -Value $item)) { $names.Add($child) }
            }
        }
        else {
            foreach ($property in $Value.PSObject.Properties) {
                $names.Add($property.Name)
                foreach ($child in @(Get-PropertyNameRecursive -Value $property.Value)) { $names.Add($child) }
            }
        }
        return @($names)
    }
}

Describe 'Notification contracts' {
    It 'accepts registered source families with solution-owned normalized data' -ForEach @(
        @{ Source = 'microsoftGraph.directoryAudit'; EventType = 'entra.pim.roleActivated' },
        @{ Source = 'microsoftGraph.identityProtection'; EventType = 'entra.identityProtection.riskDetected' },
        @{ Source = 'microsoftGraph.deviceManagement'; EventType = 'intune.device.noncompliant' },
        @{ Source = 'microsoftSentinel.incident'; EventType = 'sentinel.incident.created' }
    ) {
        $envelope = Get-Content -LiteralPath $script:envelopeFixture -Raw | ConvertFrom-Json
        $envelope.source = $Source
        $envelope.eventType = $EventType
        $envelope.data = [pscustomobject]@{ fixture = $EventType }

        ($envelope | ConvertTo-Json -Depth 10 |
            Test-Json -SchemaFile $script:envelopeSchema -ErrorAction Stop) | Should -BeTrue
    }

    It 'keeps every registered transport visibly distinct' -ForEach @(
        'teams.workflowWebhook',
        'teams.logicAppsConnector',
        'teams.bot',
        'email.graph',
        'email.logicAppsConnector',
        'azureMonitor.email'
    ) {
        $result = Get-Content -LiteralPath $script:resultFixture -Raw | ConvertFrom-Json
        $result.route.transport = $_

        ($result | ConvertTo-Json -Depth 10 |
            Test-Json -SchemaFile $script:resultSchema -ErrorAction Stop) | Should -BeTrue
    }

    It 'rejects a collapsed transport name' {
        $result = Get-Content -LiteralPath $script:resultFixture -Raw | ConvertFrom-Json
        $result.route.transport = 'teams'

        { $result | ConvertTo-Json -Depth 10 |
            Test-Json -SchemaFile $script:resultSchema -ErrorAction Stop } | Should -Throw
    }

    It 'requires failure details only for failed results' {
        $result = Get-Content -LiteralPath $script:resultFixture -Raw | ConvertFrom-Json
        $result.status = 'failed'
        { $result | ConvertTo-Json -Depth 10 |
            Test-Json -SchemaFile $script:resultSchema -ErrorAction Stop } | Should -Throw

        $result | Add-Member -NotePropertyName failure -NotePropertyValue ([pscustomobject]@{
            category = 'throttled'; retryable = $true; code = 'TooManyRequests'
        })
        ($result | ConvertTo-Json -Depth 10 |
            Test-Json -SchemaFile $script:resultSchema -ErrorAction Stop) | Should -BeTrue

        $result.status = 'succeeded'
        { $result | ConvertTo-Json -Depth 10 |
            Test-Json -SchemaFile $script:resultSchema -ErrorAction Stop } | Should -Throw
    }

    It 'requires a registered reason only for skipped results' {
        $result = Get-Content -LiteralPath $script:resultFixture -Raw | ConvertFrom-Json
        $result.status = 'skipped'
        { $result | ConvertTo-Json -Depth 10 |
            Test-Json -SchemaFile $script:resultSchema -ErrorAction Stop } | Should -Throw

        $result | Add-Member -NotePropertyName skipReason -NotePropertyValue 'initialBaseline'
        ($result | ConvertTo-Json -Depth 10 |
            Test-Json -SchemaFile $script:resultSchema -ErrorAction Stop) | Should -BeTrue
    }

    It 'matches the cross-language idempotency test vector' {
        $result = Get-Content -LiteralPath $script:resultFixture -Raw | ConvertFrom-Json
        $input = $result.environment.tenantId + "`n" + $result.eventType + "`n" + $result.eventId + "`n" + $result.route.id
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($input)
        $actual = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()

        $actual | Should -Be $result.idempotencyKey
    }

    It 'rejects each missing required result property independently' {
        $required = @(
            'schemaVersion', 'eventId', 'eventType', 'correlationId', 'idempotencyKey',
            'route', 'status', 'attempt', 'recordedAt', 'isTest', 'environment', 'evidence'
        )
        foreach ($propertyName in $required) {
            $result = Get-Content -LiteralPath $script:resultFixture -Raw | ConvertFrom-Json
            $result.PSObject.Properties.Remove($propertyName)
            { $result | ConvertTo-Json -Depth 10 |
                Test-Json -SchemaFile $script:resultSchema -ErrorAction Stop } |
                Should -Throw -Because "$propertyName is required"
        }
    }

    It 'rejects unsafe result identifiers and encoded callbacks independently' {
        foreach ($case in @(
            @{ Property = 'eventId'; Value = 'https://example.invalid/callback?sig=secret' },
            @{ Property = 'correlationId'; Value = 'Bearer secret' }
        )) {
            $result = Get-Content -LiteralPath $script:resultFixture -Raw | ConvertFrom-Json
            $result.($case.Property) = $case.Value
            { $result | ConvertTo-Json -Depth 10 |
                Test-Json -SchemaFile $script:resultSchema -ErrorAction Stop } |
                Should -Throw -Because "$($case.Property) must be opaque"
        }

        $result = Get-Content -LiteralPath $script:resultFixture -Raw | ConvertFrom-Json
        $result.evidence | Add-Member -NotePropertyName operationId -NotePropertyValue 'https:%2F%2Fexample.invalid%2Fcallback%3Fsig%3Dsecret'
        { $result | ConvertTo-Json -Depth 10 |
            Test-Json -SchemaFile $script:resultSchema -ErrorAction Stop } |
            Should -Throw -Because 'evidence identifiers must be opaque'
    }

    It 'rejects invalid audience, idempotency, and unexpected result properties independently' {
        $mutations = @(
            { param($result) $result.route.audience = 'administrator' },
            { param($result) $result.idempotencyKey = 'event-42|admin' },
            { param($result) $result | Add-Member -NotePropertyName recipient -NotePropertyValue 'admin@example.com' }
        )
        foreach ($mutation in $mutations) {
            $result = Get-Content -LiteralPath $script:resultFixture -Raw | ConvertFrom-Json
            & $mutation $result
            { $result | ConvertTo-Json -Depth 10 |
                Test-Json -SchemaFile $script:resultSchema -ErrorAction Stop } | Should -Throw
        }
    }

    It 'keeps checked-in fixtures free of credential shapes' {
        foreach ($path in $script:envelopeFixture, $script:resultFixture) {
            $result = & $script:safetyTool -Path $path
            $result.safe | Should -BeTrue
        }
    }

    It 'rejects the complete credential property-name matrix' -ForEach @(
        'authorization', 'authorizationHeader', 'accessToken', 'refreshToken', 'token',
        'identityHeader', 'password', 'secret', 'credential', 'cookie', 'assertion',
        'certificate', 'privateKey', 'apiKey', 'accountKey', 'subscriptionKey',
        'hostKey', 'functionKey', 'callback', 'callbackUrl', 'callbackUri',
        'webhookUrl', 'connectionString', 'clientSecret', 'sas', 'signature'
    ) {
        $fixturePath = Join-Path $TestDrive "$_.json"
        $json = @{ schemaVersion = '1.0'; data = @{ $_ = 'do-not-write' } } | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($fixturePath, $json, [System.Text.UTF8Encoding]::new($false))

        { & $script:safetyTool -Path $fixturePath } | Should -Throw '*credential-bearing property name*'
    }

    It 'rejects credential-bearing value shapes' -ForEach @(
        'Bearer do-not-write',
        'https://example.invalid/hook?sig=do-not-write',
        'https:%2F%2Fexample.invalid%2Fhook%3Fsig%3Ddo-not-write',
        'AccountKey=do-not-write',
        '-----BEGIN PRIVATE KEY-----'
    ) {
        $fixturePath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
        $json = @{ schemaVersion = '1.0'; data = @{ note = $_ } } | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($fixturePath, $json, [System.Text.UTF8Encoding]::new($false))

        { & $script:safetyTool -Path $fixturePath } | Should -Throw '*credential-bearing value shape*'
    }

    It 'keeps delivery results free of recipients and rendered content' {
        $result = Get-Content -LiteralPath $script:resultFixture -Raw | ConvertFrom-Json
        $names = @(Get-PropertyNameRecursive -Value $result)

        foreach ($forbidden in 'data', 'recipient', 'userPrincipalName', 'email', 'teamId', 'channelId', 'card', 'html', 'body') {
            $names | Should -Not -Contain $forbidden
        }
    }
}
