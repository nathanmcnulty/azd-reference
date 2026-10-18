BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../components/powershell/foundry-stateless-agent/Azd.FoundryStateless.psd1') -Force
}
Describe 'Stateless Foundry boundaries' {
    BeforeEach {
        $script:endpoint = 'https://fixture.services.ai.azure.com/api/projects/review'
        $script:token = ConvertTo-SecureString 'synthetic-token' -AsPlainText -Force
        $script:schema = @{ type = 'object'; additionalProperties = $false; properties = @{ summary = @{ type = 'string' } }; required = @('summary') }
        $script:definition = New-AzdFoundryAgentDefinition -ModelDeployment 'gpt-6-luna' -Instructions 'Summarize supplied facts only.' -OutputSchema $script:schema
        $script:readback = @{ name = 'test-review'; version = '7'; definition = $script:definition }
        $script:response = @{ status = 'completed'; store = $false; output = @(@{ type = 'reasoning'; summary = @() }, @{ type = 'message'; role = 'assistant'; status = 'completed'; content = @(@{ type = 'output_text'; text = '{"summary":"review required"}' }) }) }
        Mock -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp {
            if ($Method -eq 'GET') { return $script:readback }
            return $script:response
        }
        $script:receipt = Test-AzdFoundryAgentVersion -ProjectEndpoint $script:endpoint -AgentName 'test-review' -AgentVersion '7' -Definition $script:definition -AccessToken $script:token
    }
    It 'sends exactly one version-bound synchronous unstored response without conversation state' {
        $result = Invoke-AzdFoundryStatelessResponse -ProjectEndpoint $script:endpoint -AgentName 'test-review' -AgentVersion '7' -Definition $script:definition -AccessToken $script:token -VerificationReceipt $script:receipt -InputText 'sanitized facts'
        $result.result.summary | Should -BeExactly 'review required'
        $result.receipt.definitionSha256 | Should -Match '^[a-f0-9]{64}$'
        $result.receipt.store | Should -BeFalse
        ($result.receipt | ConvertTo-Json) | Should -Not -Match 'synthetic-token|sanitized facts|review required|instructions'
        Should -Invoke -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp -Times 1 -Exactly -ParameterFilter {
            if ($Method -ne 'POST') { return $false }; $request = $BodyJson | ConvertFrom-Json -AsHashtable
            $Method -eq 'POST' -and $Uri -eq 'https://fixture.services.ai.azure.com/api/projects/review/openai/v1/responses' -and
            $request.agent_reference.version -ceq '7' -and $request.agent_reference.name -ceq 'test-review' -and
            $request.store -eq $false -and $request.background -eq $false -and $request.stream -eq $false -and
            $request.tools.Count -eq 0 -and $request.tool_choice -ceq 'none' -and $request.max_output_tokens -eq 2048 -and
            -not $request.Contains('conversation') -and -not $request.Contains('previous_response_id')
        }
    }
    It 'rejects decorated, non-Azure and ambiguous endpoints before transport: <Endpoint>' -ForEach @(
        @{ Endpoint = 'http://fixture.services.ai.azure.com/api/projects/review' }
        @{ Endpoint = 'https://fixture.services.ai.azure.com.evil.example/api/projects/review' }
        @{ Endpoint = 'https://user@fixture.services.ai.azure.com/api/projects/review' }
        @{ Endpoint = 'https://fixture.services.ai.azure.com:444/api/projects/review' }
        @{ Endpoint = 'https://fixture.services.ai.azure.com/api/projects/review?next=evil' }
        @{ Endpoint = 'https://fixture.services.ai.azure.com/api/projects/review%2fother' }
        @{ Endpoint = 'https://fixture.services.ai.azure.com/api/projects/review/../other' }
        @{ Endpoint = "https://fixture.services.ai.azure.com/api/projects/review`n" }
    ) {
        { Invoke-AzdFoundryStatelessResponse -ProjectEndpoint $Endpoint -AgentName 'test-review' -AgentVersion '7' -Definition $script:definition -AccessToken $script:token -VerificationReceipt $script:receipt -InputText 'facts' } | Should -Throw
        Should -Invoke -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }
    It 'rejects mismatched verification receipt before inference' {
        foreach ($key in @('agentName', 'agentVersion', 'projectEndpoint', 'definitionSha256', 'modelDeployment', 'status')) {
            $saved = $script:receipt[$key]
            $script:receipt[$key] = 'other'
            { Invoke-AzdFoundryStatelessResponse -ProjectEndpoint $script:endpoint -AgentName 'test-review' -AgentVersion '7' -Definition $script:definition -AccessToken $script:token -VerificationReceipt $script:receipt -InputText 'facts' } | Should -Throw '*receipt does not match*'
            $script:receipt[$key] = $saved
        }
        Should -Invoke -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }
    It 'rejects changed persisted tools, instructions or schemas before inference' {
        foreach ($key in @('tools', 'instructions', 'text')) {
            $remote = $script:definition | ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable
            $remote[$key] = if ($key -eq 'tools') { @(@{type='web_search'}) } else { 'changed' }
            $script:readback.definition = $remote
            { Test-AzdFoundryAgentVersion -ProjectEndpoint $script:endpoint -AgentName 'test-review' -AgentVersion '7' -Definition $script:definition -AccessToken $script:token } | Should -Throw '*differs*'
        }
        Should -Invoke -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }
    It 'rejects incomplete, stored or conversation-linked responses' {
        foreach ($case in @(@{key='status';value='incomplete'}, @{key='store';value=$true}, @{key='conversation';value='conv_123'}, @{key='previous_response_id';value='resp_123'})) {
            $original = $script:response[$case.key]
            $script:response[$case.key] = $case.value
            { Invoke-AzdFoundryStatelessResponse -ProjectEndpoint $script:endpoint -AgentName 'test-review' -AgentVersion '7' -Definition $script:definition -AccessToken $script:token -VerificationReceipt $script:receipt -InputText 'facts' } | Should -Throw '*cannot be used*'
            $script:response[$case.key] = $original
        }
    }
    It 'rejects tool output and refusal even when status is completed' {
        $script:response.output = @(@{ type = 'function_call'; name = 'mutate' })
        { Invoke-AzdFoundryStatelessResponse -ProjectEndpoint $script:endpoint -AgentName 'test-review' -AgentVersion '7' -Definition $script:definition -AccessToken $script:token -VerificationReceipt $script:receipt -InputText 'facts' } | Should -Throw '*tool call*'
        $script:response.output = @(@{ type = 'message'; role = 'assistant'; status = 'completed'; content = @(@{type='refusal';refusal='no'}) })
        { Invoke-AzdFoundryStatelessResponse -ProjectEndpoint $script:endpoint -AgentName 'test-review' -AgentVersion '7' -Definition $script:definition -AccessToken $script:token -VerificationReceipt $script:receipt -InputText 'facts' } | Should -Throw '*refusal*'
    }
    It 'requires exact schema validity and never exposes invalid output' {
        $script:response.output[1].content[0].text = '{"summary":"ok","approved":true}'
        { Invoke-AzdFoundryStatelessResponse -ProjectEndpoint $script:endpoint -AgentName 'test-review' -AgentVersion '7' -Definition $script:definition -AccessToken $script:token -VerificationReceipt $script:receipt -InputText 'facts' } | Should -Throw '*reviewed JSON schema*'
    }
    It 'bounds UTF-8 input before sending any request' {
        { Invoke-AzdFoundryStatelessResponse -ProjectEndpoint $script:endpoint -AgentName 'test-review' -AgentVersion '7' -Definition $script:definition -AccessToken $script:token -VerificationReceipt $script:receipt -InputText ('é' * 40000) } | Should -Throw '*UTF-8 bytes*'
        Should -Invoke -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }
    It 'rejects external schema references and unexpected definition properties' {
        $script:schema.properties.summary = @{ '$ref' = 'https://evil.example/schema' }
        { New-AzdFoundryAgentDefinition -ModelDeployment 'gpt-6-luna' -Instructions 'safe' -OutputSchema $script:schema } | Should -Throw '*local*'
        $script:definition['connections'] = @('external')
        { Test-AzdFoundryAgentVersion -ProjectEndpoint $script:endpoint -AgentName 'test-review' -AgentVersion '7' -Definition $script:definition -AccessToken $script:token } | Should -Throw '*minimal*'
    }
    It 'creates a version once and verifies exact readback' {
        Mock -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp { return $script:readback }
        $receipt = Publish-AzdFoundryAgentVersion -ProjectEndpoint $script:endpoint -AgentName 'test-review' -Definition $script:definition -AccessToken $script:token -Confirm:$false
        $receipt.status | Should -BeExactly 'verified'
        Should -Invoke -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        Should -Invoke -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp -Times 2 -Exactly -ParameterFilter { $Method -eq 'GET' }
    }
    It 'does not retry an uncertain creation or write during WhatIf' {
        Publish-AzdFoundryAgentVersion -ProjectEndpoint $script:endpoint -AgentName 'test-review' -Definition $script:definition -AccessToken $script:token -WhatIf
        Should -Invoke -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp { throw 'uncertain outcome' }
        { Publish-AzdFoundryAgentVersion -ProjectEndpoint $script:endpoint -AgentName 'test-review' -Definition $script:definition -AccessToken $script:token -Confirm:$false } | Should -Throw '*uncertain*'
        Should -Invoke -ModuleName Azd.FoundryStateless Invoke-AzdFoundryHttp -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }
}
Describe 'Foundry provenance and transport invariants' {
    It 'uses ordinal schema-key hashing across cultures' {
        InModuleScope Azd.FoundryStateless {
            $old = [Threading.Thread]::CurrentThread.CurrentCulture
            try {
                $value = '{"z":1,"a":2,"A":3,"é":4}' | ConvertFrom-Json -AsHashtable
                $observed = foreach ($culture in @('en-US', 'sv-SE', 'tr-TR')) {
                    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::new($culture)
                    ConvertTo-AzdFoundryCanonicalJson $value
                }
                @($observed | Select-Object -Unique).Count | Should -Be 1
                $observed[0] | Should -BeExactly '{"A":3,"a":2,"z":1,"é":4}'
            }
            finally { [Threading.Thread]::CurrentThread.CurrentCulture = $old }
        }
    }
    It 'disables HTTP redirects and bounds both headers and body reads' {
        $source = Get-Content (Join-Path $PSScriptRoot '../components/powershell/foundry-stateless-agent/Azd.FoundryStateless.psm1') -Raw
        $source | Should -Match 'AllowAutoRedirect = \$false'
        $source | Should -Match 'ResponseHeadersRead'
        $source | Should -Match 'ContentLength -gt 1048576'
        $source | Should -Match '\$memory.Length \+ \$count -gt 1048576'
        $source | Should -Match 'CancellationTokenSource.*FromSeconds\(120\)'
        $source | Should -Not -Match 'Write-(Host|Output|Verbose|Debug).*\$(AccessToken|tokenText|BodyJson)'
    }
    It 'fails closed on unknown non-null persisted agent behavior' {
        InModuleScope Azd.FoundryStateless {
            $definition = New-AzdFoundryAgentDefinition -ModelDeployment 'model' -Instructions 'review' -OutputSchema @{type='object';additionalProperties=$false;properties=@{};required=@()}
            $remote = $definition | ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable
            $remote['new_tool_binding'] = 'unexpected'
            Mock Invoke-AzdFoundryHttp { @{name='agent';version='1';definition=$remote} }
            { Test-AzdFoundryAgentVersion -ProjectEndpoint 'https://fixture.services.ai.azure.com/api/projects/review' -AgentName agent -AgentVersion 1 -Definition $definition -AccessToken (ConvertTo-SecureString synthetic -AsPlainText -Force) } | Should -Throw '*unreviewed*'
        }
    }
}
