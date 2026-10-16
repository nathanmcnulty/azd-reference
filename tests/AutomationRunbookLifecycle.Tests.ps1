BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../components/powershell/automation-runbook-lifecycle/Azd.AutomationRunbookLifecycle.psd1'
    Import-Module $modulePath -Force

    function New-TestAutomationRunbookFixture {
        param([string] $Version = '7.4', [switch] $AsDictionary)

        $accountId = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Automation/automationAccounts/aa-test'
        $runbookName = 'locally-maintained-runbook'
        $runtimeName = "PowerShell-$($Version.Replace('.', ''))-Shared"
        # Real deserialized JSON preserves absent/null/false/zero fields and
        # response-only properties that must never be replayed in a PATCH.
        $runbook = @'
{
  "name": "locally-maintained-runbook",
  "type": "Microsoft.Automation/automationAccounts/runbooks",
  "location": "West US 2",
  "tags": { "Owner": "Custom 'quoted' Δ", "Interpolation": "${MUST_STAY_LITERAL}", "Empty": "" },
  "properties": {
    "state": "Published", "runbookType": "PowerShell", "runtimeEnvironment": "PowerShell-72-Existing",
    "description": "Preserve \"quotes\", 'apostrophes', Δ, a newline\nand ${MUST_STAY_LITERAL}",
    "logProgress": false, "logVerbose": true, "logActivityTrace": 0,
    "publishContentLink": { "uri": "https://example.invalid/never-replay" },
    "draft": { "inEdit": false }, "parameters": { "ExistingParameter": { "type": "String", "isMandatory": false } },
    "outputTypes": ["String"], "creationTime": "2020-01-01T00:00:00Z", "lastModifiedTime": "2020-02-01T00:00:00Z",
    "jobCount": 3, "provisioningState": "Succeeded"
  },
  "etag": "response-only", "systemData": { "createdBy": "response-only" }
}
'@ | ConvertFrom-Json
        $runbook | Add-Member -NotePropertyName id -NotePropertyValue "$accountId/runbooks/$runbookName"
        $runtime = [pscustomobject]@{
            id = "$accountId/runtimeEnvironments/$runtimeName"
            name = $runtimeName
            type = 'Microsoft.Automation/automationAccounts/runtimeEnvironments'
            location = 'westus2'
            properties = [pscustomobject]@{
                runtime = [pscustomobject]@{ language = 'PowerShell'; version = $Version }
                provisioningState = 'Succeeded'
            }
        }
        $content = "# locally maintained runbook`nWrite-Output 'local Δ'`n"
        $global:azdAutomationRunbookTestFixture = @{
            AccountId = $accountId; RunbookName = $runbookName
            RuntimeName = $runtimeName; RuntimeVersion = $Version
            Runbook = $runbook; Runtime = $runtime
            ExpectedContent = $content; PublishedContent = $content
            OwnershipResult = { $true }; OwnershipAttempts = 0
            FailAt = ''; AfterPatch = $null; AsDictionary = [bool] $AsDictionary
            Calls = [Collections.Generic.List[string]]::new()
            Bodies = [Collections.Generic.List[string]]::new()
            PatchAttempts = 0; RuntimeGets = 0; RunbookGets = 0; ContentGets = 0
        }
    }

    function Invoke-TestAutomationRunbookFixture {
        $fixture = $global:azdAutomationRunbookTestFixture
        $arguments = @{
            ExpectedAccountId = $fixture.AccountId
            RunbookName = $fixture.RunbookName
            ExpectedRuntimeName = $fixture.RuntimeName
            ExpectedRuntimeVersion = $fixture.RuntimeVersion
            ExpectedContent = $fixture.ExpectedContent
            AssertOwnership = {
                param($accountId, $runbookName)
                $fixture = $global:azdAutomationRunbookTestFixture
                $fixture.Calls.Add('OWNERSHIP')
                $fixture.OwnershipAttempts++
                $accountId | Should -BeExactly $fixture.AccountId
                $runbookName | Should -BeExactly $fixture.RunbookName
                if ($fixture.FailAt -eq 'ownership') { throw 'simulated ownership failure' }
                & $fixture.OwnershipResult
            }
            GetResource = {
                param($path)
                $fixture = $global:azdAutomationRunbookTestFixture
                $fixture.Calls.Add("GET $path")
                $path | Should -Match '\?api-version=2024-10-23$'
                switch ($path -replace '\?.*$', '') {
                    "$($fixture.AccountId)/runtimeEnvironments/$($fixture.RuntimeName)" {
                        $fixture.RuntimeGets++
                        if ($fixture.FailAt -eq 'runtime GET') { throw 'simulated runtime GET failure' }
                        return ($fixture.Runtime | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable:$fixture.AsDictionary)
                    }
                    "$($fixture.AccountId)/runbooks/$($fixture.RunbookName)" {
                        $fixture.RunbookGets++
                        if (($fixture.FailAt -eq 'runbook GET' -and $fixture.RunbookGets -eq 1) -or
                            ($fixture.FailAt -eq 'readback GET' -and $fixture.RunbookGets -gt 1)) {
                            throw 'simulated runbook GET failure'
                        }
                        return ($fixture.Runbook | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable:$fixture.AsDictionary)
                    }
                    default { throw "Unexpected resource GET: $path" }
                }
            }
            GetContent = {
                param($path)
                $fixture = $global:azdAutomationRunbookTestFixture
                $fixture.Calls.Add("CONTENT GET $path")
                $fixture.ContentGets++
                $path | Should -BeExactly "$($fixture.AccountId)/runbooks/$($fixture.RunbookName)/content?api-version=2024-10-23"
                if (($fixture.FailAt -eq 'content GET' -and $fixture.ContentGets -eq 1) -or
                    ($fixture.FailAt -eq 'readback content GET' -and $fixture.ContentGets -gt 1)) {
                    throw 'simulated content GET failure'
                }
                return $fixture.PublishedContent
            }
            PatchResource = {
                param($path, $jsonBody)
                $fixture = $global:azdAutomationRunbookTestFixture
                $fixture.Calls.Add("PATCH $path")
                $fixture.Bodies.Add([string] $jsonBody)
                $fixture.PatchAttempts++
                $path | Should -BeExactly "$($fixture.AccountId)/runbooks/$($fixture.RunbookName)?api-version=2024-10-23"
                if ($fixture.FailAt -eq 'PATCH before apply') { throw 'simulated PATCH failure before apply' }
                $fixture.Runbook.properties.runtimeEnvironment = ($jsonBody | ConvertFrom-Json).properties.runtimeEnvironment
                if ($fixture.AfterPatch) { & $fixture.AfterPatch $fixture }
                if ($fixture.FailAt -eq 'PATCH after apply') { throw 'simulated PATCH failure after apply' }
                # The response is deliberately uninformative: verification must
                # read the resource and published content again.
                [pscustomobject]@{ accepted = $true }
            }
        }
        Update-AzdAutomationRunbookRuntime @arguments
    }

    function Assert-TestAutomationRunbookPatch {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture.Bodies.Count | Should -Be 1
        $body = $fixture.Bodies[0] | ConvertFrom-Json
        @($body.PSObject.Properties.Name) | Should -Be @('properties')
        @($body.properties.PSObject.Properties.Name) | Should -Be @('runtimeEnvironment')
        $body.properties.runtimeEnvironment | Should -BeExactly $fixture.RuntimeName
        $fixture.Bodies[0] | Should -Not -Match 'location|tags|description|logProgress|logVerbose|logActivityTrace|runbookType|publishContentLink|draft|parameters|outputTypes|creationTime|lastModifiedTime|jobCount|provisioningState|etag|systemData'
    }
}

AfterAll {
    Remove-Module Azd.AutomationRunbookLifecycle -Force -ErrorAction SilentlyContinue
    Remove-Variable azdAutomationRunbookTestFixture -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Update-AzdAutomationRunbookRuntime runtime-only coordination' {
    BeforeEach { New-TestAutomationRunbookFixture }

    It 'exports only the public coordinator' {
        @(Get-Command -Module Azd.AutomationRunbookLifecycle).Name | Should -Be @('Update-AzdAutomationRunbookRuntime')
    }

    It 'binds PowerShell <Version> through one exact PATCH and fresh verification' -ForEach @(
        @{ Version = '7.4' }, @{ Version = '7.6' }
    ) {
        New-TestAutomationRunbookFixture -Version $Version
        $fixture = $global:azdAutomationRunbookTestFixture
        $before = $fixture.Runbook | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $before.properties.runtimeEnvironment = $fixture.RuntimeName
        $content = $fixture.PublishedContent
        $runtime = $fixture.Runtime | ConvertTo-Json -Depth 30 -Compress

        $result = @(Invoke-TestAutomationRunbookFixture)

        $result.Count | Should -Be 1
        $result[0] | Should -BeOfType ([bool])
        $result[0] | Should -BeTrue
        Assert-TestAutomationRunbookPatch
        ($fixture.Runbook | ConvertTo-Json -Depth 30 -Compress) | Should -BeExactly ($before | ConvertTo-Json -Depth 30 -Compress)
        $fixture.PublishedContent | Should -BeExactly $content
        ($fixture.Runtime | ConvertTo-Json -Depth 30 -Compress) | Should -BeExactly $runtime
        $fixture.Calls[0] | Should -BeExactly 'OWNERSHIP'
        $fixture.OwnershipAttempts | Should -Be 1
        $fixture.RuntimeGets | Should -Be 1
        $fixture.RunbookGets | Should -Be 2
        $fixture.ContentGets | Should -Be 2
        ($fixture.Calls -join '|') | Should -Not -Match 'PUT |POST |DELETE |/draft|publish\?|/jobs|jobSchedules|roleAssignments|graph.microsoft.com'
    }

    It 'supports dictionary resource responses without weakening verification' {
        New-TestAutomationRunbookFixture -AsDictionary
        Invoke-TestAutomationRunbookFixture | Should -BeTrue
        Assert-TestAutomationRunbookPatch
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture.RunbookGets | Should -Be 2
        $fixture.ContentGets | Should -Be 2
    }

    It 'returns only false and skips writes after validating an already-bound runbook' {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture.Runbook.properties.runtimeEnvironment = $fixture.RuntimeName
        $before = $fixture.Runbook | ConvertTo-Json -Depth 30 -Compress

        foreach ($attempt in 1..2) {
            $result = @(Invoke-TestAutomationRunbookFixture)
            $result.Count | Should -Be 1
            $result[0] | Should -BeOfType ([bool])
            $result[0] | Should -BeFalse
        }

        $fixture.PatchAttempts | Should -Be 0
        $fixture.OwnershipAttempts | Should -Be 2
        $fixture.RuntimeGets | Should -Be 2
        $fixture.RunbookGets | Should -Be 2
        $fixture.ContentGets | Should -Be 2
        ($fixture.Runbook | ConvertTo-Json -Depth 30 -Compress) | Should -BeExactly $before
    }

    It 'still rejects <Problem> when the requested binding is already present' -ForEach @(
        @{ Problem = 'unowned runbook' }, @{ Problem = 'Edit state' },
        @{ Problem = 'content mismatch' }, @{ Problem = 'wrong runtime version' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture.Runbook.properties.runtimeEnvironment = $fixture.RuntimeName
        switch ($Problem) {
            'unowned runbook' { $fixture.OwnershipResult = { $false } }
            'Edit state' { $fixture.Runbook.properties.state = 'Edit' }
            'content mismatch' { $fixture.PublishedContent = '# changed' }
            'wrong runtime version' { $fixture.Runtime.properties.runtime.version = '7.6' }
        }
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.PatchAttempts | Should -Be 0
    }

    It 'requires one scalar Boolean true from ownership before reading anything: <Shape>' -ForEach @(
        @{ Shape = 'false'; Result = { $false } },
        @{ Shape = 'null'; Result = { $null } },
        @{ Shape = 'no output'; Result = {} },
        @{ Shape = 'string'; Result = { 'true' } },
        @{ Shape = 'number'; Result = { 1 } },
        @{ Shape = 'multiple values'; Result = { $true; $true } },
        @{ Shape = 'single-element array'; Result = { ,@($true) } },
        @{ Shape = 'mixed output'; Result = { 'diagnostic'; $true } }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture.OwnershipResult = $Result
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.OwnershipAttempts | Should -Be 1
        $fixture.Calls | Should -Be @('OWNERSHIP')
        $fixture.PatchAttempts | Should -Be 0
    }

    It 'rejects malformed account target <Problem> before invoking a callback' -ForEach @(
        @{ Problem = 'non-GUID subscription'; Account = '/subscriptions/sub-test/resourceGroups/rg-test/providers/Microsoft.Automation/automationAccounts/aa-test' },
        @{ Problem = 'trailing slash'; Account = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Automation/automationAccounts/aa-test/' },
        @{ Problem = 'query'; Account = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Automation/automationAccounts/aa-test?x=1' },
        @{ Problem = 'fragment'; Account = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Automation/automationAccounts/aa-test#x' },
        @{ Problem = 'other resource type'; Account = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Web/sites/aa-test' },
        @{ Problem = 'child resource'; Account = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Automation/automationAccounts/aa-test/runbooks/child' },
        @{ Problem = 'single-dot resource-group segment'; Account = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/./providers/Microsoft.Automation/automationAccounts/aa-test' },
        @{ Problem = 'double-dot resource-group segment'; Account = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/../providers/Microsoft.Automation/automationAccounts/aa-test' },
        @{ Problem = 'blank resource group'; Account = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups//providers/Microsoft.Automation/automationAccounts/aa-test' },
        @{ Problem = 'blank account'; Account = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Automation/automationAccounts/' },
        @{ Problem = 'leading whitespace'; Account = ' /subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Automation/automationAccounts/aa-test' },
        @{ Problem = 'absolute URI'; Account = 'https://management.azure.com/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Automation/automationAccounts/aa-test' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture.AccountId = $Account
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.Calls.Count | Should -Be 0
    }

    It 'rejects unsafe <Field> value <Problem> before invoking a callback' -ForEach @(
        foreach ($field in @('RunbookName', 'RuntimeName')) {
            foreach ($case in @(
                @{ Problem = 'blank'; Value = '' },
                @{ Problem = 'whitespace'; Value = ' ' },
                @{ Problem = 'leading whitespace'; Value = ' name' },
                @{ Problem = 'trailing whitespace'; Value = 'name ' },
                @{ Problem = 'path traversal'; Value = '../name' },
                @{ Problem = 'path separator'; Value = 'name/child' },
                @{ Problem = 'query injection'; Value = 'name?x=1' },
                @{ Problem = 'fragment'; Value = 'name#x' },
                @{ Problem = 'encoded slash'; Value = 'name%2fchild' },
                @{ Problem = 'Unicode'; Value = 'name-Δ' },
                @{ Problem = 'dot'; Value = 'name.ps1' },
                @{ Problem = 'over 64 characters'; Value = ('a' * 65) }
            )) {
                @{ Field = $field; Problem = $case.Problem; Value = $case.Value }
            }
        }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture[$Field] = $Value
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.Calls.Count | Should -Be 0
    }

    It 'accepts ASCII names at the 64-character boundary' {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture.RunbookName = 'R_-' + ('a' * 61)
        $fixture.RuntimeName = 'P_-' + ('b' * 61)
        $fixture.Runbook.name = $fixture.RunbookName
        $fixture.Runbook.id = "$($fixture.AccountId)/runbooks/$($fixture.RunbookName)"
        $fixture.Runtime.name = $fixture.RuntimeName
        $fixture.Runtime.id = "$($fixture.AccountId)/runtimeEnvironments/$($fixture.RuntimeName)"
        Invoke-TestAutomationRunbookFixture | Should -BeTrue
        Assert-TestAutomationRunbookPatch
    }

    It 'rejects trailing <Ending> on <Field> before ownership, reads, or PATCH' -ForEach @(
        foreach ($field in @('AccountId', 'RunbookName', 'RuntimeName', 'RuntimeVersion')) {
            @{ Field = $field; Ending = 'LF'; Suffix = "`n" }
            @{ Field = $field; Ending = 'CRLF'; Suffix = "`r`n" }
        }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture[$Field] += $Suffix
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.Calls.Count | Should -Be 0
        $fixture.OwnershipAttempts | Should -Be 0
        $fixture.PatchAttempts | Should -Be 0
    }

    It 'rejects malformed expected version <Version> without calling adapters' -ForEach @(
        @{ Version = '' }, @{ Version = '7.4 ' }, @{ Version = ' 7.4' },
        @{ Version = 'current' }, @{ Version = '7.4?x=1' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture.RuntimeVersion = $Version
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.Calls.Count | Should -Be 0
    }

    It 'rejects preexisting runbook <Problem> without a write or Edit recovery' -ForEach @(
        @{ Problem = 'Edit state' }, @{ Problem = 'missing state' },
        @{ Problem = 'wrong ID' }, @{ Problem = 'wrong name' }, @{ Problem = 'wrong type' },
        @{ Problem = 'wrong language' }, @{ Problem = 'missing location' },
        @{ Problem = 'null location' }, @{ Problem = 'blank location' },
        @{ Problem = 'array location' }, @{ Problem = 'array ID' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        switch ($Problem) {
            'Edit state' { $fixture.Runbook.properties.state = 'Edit' }
            'missing state' { $fixture.Runbook.properties.PSObject.Properties.Remove('state') }
            'wrong ID' { $fixture.Runbook.id = $fixture.Runbook.id.Replace('/aa-test/', '/other-account/') }
            'wrong name' { $fixture.Runbook.name = 'other-runbook' }
            'wrong type' { $fixture.Runbook.type = 'Microsoft.Web/sites' }
            'wrong language' { $fixture.Runbook.properties.runbookType = 'Python3' }
            'missing location' { $fixture.Runbook.PSObject.Properties.Remove('location') }
            'null location' { $fixture.Runbook.location = $null }
            'blank location' { $fixture.Runbook.location = ' ' }
            'array location' { $fixture.Runbook.location = @('West US 2') }
            'array ID' { $fixture.Runbook.id = @($fixture.Runbook.id) }
        }
        $before = $fixture.Runbook | ConvertTo-Json -Depth 30 -Compress
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.PatchAttempts | Should -Be 0
        ($fixture.Runbook | ConvertTo-Json -Depth 30 -Compress) | Should -BeExactly $before
    }

    It 'rejects a <Shape> current runtime binding before PATCH' -ForEach @(
        @{ Shape = 'missing' }, @{ Shape = 'null' }, @{ Shape = 'empty' },
        @{ Shape = 'whitespace' }, @{ Shape = 'array' }, @{ Shape = 'number' },
        @{ Shape = 'Boolean' }, @{ Shape = 'object' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        switch ($Shape) {
            'missing' { $fixture.Runbook.properties.PSObject.Properties.Remove('runtimeEnvironment') }
            'null' { $fixture.Runbook.properties.runtimeEnvironment = $null }
            'empty' { $fixture.Runbook.properties.runtimeEnvironment = '' }
            'whitespace' { $fixture.Runbook.properties.runtimeEnvironment = '   ' }
            'array' { $fixture.Runbook.properties.runtimeEnvironment = @('PowerShell-72-Existing') }
            'number' { $fixture.Runbook.properties.runtimeEnvironment = 74 }
            'Boolean' { $fixture.Runbook.properties.runtimeEnvironment = $true }
            'object' { $fixture.Runbook.properties.runtimeEnvironment = [pscustomobject]@{ name = 'PowerShell-72-Existing' } }
        }
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.PatchAttempts | Should -Be 0
    }

    It 'rejects a one-element array for runbook <Field> before mutation' -ForEach @(
        @{ Field = 'id'; InProperties = $false },
        @{ Field = 'name'; InProperties = $false },
        @{ Field = 'type'; InProperties = $false },
        @{ Field = 'state'; InProperties = $true },
        @{ Field = 'runbookType'; InProperties = $true }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        $record = if ($InProperties) { $fixture.Runbook.properties } else { $fixture.Runbook }
        $record.$Field = @($record.$Field)
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.PatchAttempts | Should -Be 0
    }

    It 'rejects a one-element array for runtime <Field> before mutation' -ForEach @(
        @{ Field = 'id' }, @{ Field = 'name' }, @{ Field = 'type' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture.Runtime.$Field = @($fixture.Runtime.$Field)
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.PatchAttempts | Should -Be 0
    }

    It 'rejects desired runtime <Problem> before PATCH' -ForEach @(
        @{ Problem = 'wrong ID' }, @{ Problem = 'wrong name' }, @{ Problem = 'wrong type' },
        @{ Problem = 'wrong language' }, @{ Problem = 'wrong version' },
        @{ Problem = 'numeric version' }, @{ Problem = 'array version' },
        @{ Problem = 'array language' }, @{ Problem = 'missing runtime' },
        @{ Problem = 'missing properties' }, @{ Problem = 'null resource' },
        @{ Problem = 'array ID' }, @{ Problem = 'null ID' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        switch ($Problem) {
            'wrong ID' { $fixture.Runtime.id = $fixture.Runtime.id.Replace('/aa-test/', '/other-account/') }
            'wrong name' { $fixture.Runtime.name = 'other-runtime' }
            'wrong type' { $fixture.Runtime.type = 'Microsoft.Automation/automationAccounts/runbooks' }
            'wrong language' { $fixture.Runtime.properties.runtime.language = 'Python' }
            'wrong version' { $fixture.Runtime.properties.runtime.version = '7.6' }
            'numeric version' { $fixture.Runtime.properties.runtime.version = 7.4 }
            'array version' { $fixture.Runtime.properties.runtime.version = @('7.4') }
            'array language' { $fixture.Runtime.properties.runtime.language = @('PowerShell') }
            'missing runtime' { $fixture.Runtime.properties.PSObject.Properties.Remove('runtime') }
            'missing properties' { $fixture.Runtime.PSObject.Properties.Remove('properties') }
            'null resource' { $fixture.Runtime = $null }
            'array ID' { $fixture.Runtime.id = @($fixture.Runtime.id) }
            'null ID' { $fixture.Runtime.id = $null }
        }
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.PatchAttempts | Should -Be 0
    }

    It 'normalizes <Shape> consistently without republishing content' -ForEach @(
        @{ Shape = 'published BOM and CRLF' }, @{ Shape = 'expected BOM and CRLF' },
        @{ Shape = 'readback BOM and CRLF' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        switch ($Shape) {
            'published BOM and CRLF' { $fixture.PublishedContent = [string][char]0xFEFF + $fixture.ExpectedContent.Replace("`n", "`r`n") }
            'expected BOM and CRLF' { $fixture.ExpectedContent = [string][char]0xFEFF + $fixture.PublishedContent.Replace("`n", "`r`n") }
            'readback BOM and CRLF' { $fixture.AfterPatch = { param($f) $f.PublishedContent = [string][char]0xFEFF + $f.PublishedContent.Replace("`n", "`r`n") } }
        }
        Invoke-TestAutomationRunbookFixture | Should -BeTrue
        Assert-TestAutomationRunbookPatch
    }

    It 'rejects published content <Problem> before PATCH' -ForEach @(
        @{ Problem = 'different text' }, @{ Problem = 'trailing whitespace' },
        @{ Problem = 'different case' }, @{ Problem = 'missing final newline' },
        @{ Problem = 'null' }, @{ Problem = 'array' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        switch ($Problem) {
            'different text' { $fixture.PublishedContent = '# edited' }
            'trailing whitespace' { $fixture.PublishedContent += ' ' }
            'different case' { $fixture.PublishedContent = $fixture.PublishedContent.Replace('Write-Output', 'write-output') }
            'missing final newline' { $fixture.PublishedContent = $fixture.PublishedContent.TrimEnd("`n") }
            'null' { $fixture.PublishedContent = $null }
            'array' { $fixture.PublishedContent = @($fixture.PublishedContent, '# other output') }
        }
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.PatchAttempts | Should -Be 0
    }

    It 'preserves <Shape> optional metadata without inventing defaults' -ForEach @(
        @{ Shape = 'missing optional fields' }, @{ Shape = 'null tags' },
        @{ Shape = 'empty tags' }, @{ Shape = 'empty description' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        switch ($Shape) {
            'missing optional fields' {
                foreach ($name in @('description', 'logProgress', 'logVerbose', 'logActivityTrace')) { $fixture.Runbook.properties.PSObject.Properties.Remove($name) }
                $fixture.Runbook.PSObject.Properties.Remove('tags')
            }
            'null tags' { $fixture.Runbook.tags = $null }
            'empty tags' { $fixture.Runbook.tags = [pscustomobject]@{} }
            'empty description' { $fixture.Runbook.properties.description = '' }
        }
        $before = $fixture.Runbook | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $before.properties.runtimeEnvironment = $fixture.RuntimeName
        Invoke-TestAutomationRunbookFixture | Should -BeTrue
        ($fixture.Runbook | ConvertTo-Json -Depth 30 -Compress) | Should -BeExactly ($before | ConvertTo-Json -Depth 30 -Compress)
        Assert-TestAutomationRunbookPatch
    }

    It 'rejects unsupported metadata <Problem> before mutation' -ForEach @(
        @{ Problem = 'null description' }, @{ Problem = 'array description' },
        @{ Problem = 'null logProgress' }, @{ Problem = 'string logProgress' },
        @{ Problem = 'null logVerbose' }, @{ Problem = 'numeric logVerbose' },
        @{ Problem = 'null logActivityTrace' }, @{ Problem = 'string logActivityTrace' },
        @{ Problem = 'fractional logActivityTrace' }, @{ Problem = 'array tags' },
        @{ Problem = 'null tag value' }, @{ Problem = 'numeric tag value' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        switch ($Problem) {
            'null description' { $fixture.Runbook.properties.description = $null }
            'array description' { $fixture.Runbook.properties.description = @('existing description') }
            'null logProgress' { $fixture.Runbook.properties.logProgress = $null }
            'string logProgress' { $fixture.Runbook.properties.logProgress = 'false' }
            'null logVerbose' { $fixture.Runbook.properties.logVerbose = $null }
            'numeric logVerbose' { $fixture.Runbook.properties.logVerbose = 1 }
            'null logActivityTrace' { $fixture.Runbook.properties.logActivityTrace = $null }
            'string logActivityTrace' { $fixture.Runbook.properties.logActivityTrace = '0' }
            'fractional logActivityTrace' { $fixture.Runbook.properties.logActivityTrace = 0.5 }
            'array tags' { $fixture.Runbook.tags = @($fixture.Runbook.tags) }
            'null tag value' { $fixture.Runbook.tags.Owner = $null }
            'numeric tag value' { $fixture.Runbook.tags.Owner = 123 }
        }
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.PatchAttempts | Should -Be 0
    }

    It 'fails readback after <Problem>, with no retry, recovery, or second PATCH' -ForEach @(
        @{ Problem = 'state drift' }, @{ Problem = 'binding drift' }, @{ Problem = 'array binding' },
        @{ Problem = 'content drift' }, @{ Problem = 'description drift' },
        @{ Problem = 'logProgress drift' }, @{ Problem = 'logVerbose drift' }, @{ Problem = 'logActivityTrace drift' },
        @{ Problem = 'tag value drift' }, @{ Problem = 'tag removal' }, @{ Problem = 'location drift' },
        @{ Problem = 'runbook ID drift' }, @{ Problem = 'runbook name drift' }, @{ Problem = 'runbook type drift' },
        @{ Problem = 'runbook language drift' }, @{ Problem = 'description removal' },
        @{ Problem = 'false converted to null' }, @{ Problem = 'zero converted to null' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture.AfterPatch = switch ($Problem) {
            'state drift' { { param($f) $f.Runbook.properties.state = 'Edit' } }
            'binding drift' { { param($f) $f.Runbook.properties.runtimeEnvironment = 'PowerShell-72-Existing' } }
            'array binding' { { param($f) $f.Runbook.properties.runtimeEnvironment = @($f.RuntimeName) } }
            'content drift' { { param($f) $f.PublishedContent = '# changed after PATCH' } }
            'description drift' { { param($f) $f.Runbook.properties.description = 'changed' } }
            'logProgress drift' { { param($f) $f.Runbook.properties.logProgress = $true } }
            'logVerbose drift' { { param($f) $f.Runbook.properties.logVerbose = $false } }
            'logActivityTrace drift' { { param($f) $f.Runbook.properties.logActivityTrace = 1 } }
            'tag value drift' { { param($f) $f.Runbook.tags.Owner = 'changed' } }
            'tag removal' { { param($f) $f.Runbook.PSObject.Properties.Remove('tags') } }
            'location drift' { { param($f) $f.Runbook.location = 'eastus' } }
            'runbook ID drift' { { param($f) $f.Runbook.id = $f.Runbook.id.Replace('/aa-test/', '/wrong-account/') } }
            'runbook name drift' { { param($f) $f.Runbook.name = 'other-runbook' } }
            'runbook type drift' { { param($f) $f.Runbook.type = 'Microsoft.Web/sites' } }
            'runbook language drift' { { param($f) $f.Runbook.properties.runbookType = 'Python3' } }
            'description removal' { { param($f) $f.Runbook.properties.PSObject.Properties.Remove('description') } }
            'false converted to null' { { param($f) $f.Runbook.properties.logProgress = $null } }
            'zero converted to null' { { param($f) $f.Runbook.properties.logActivityTrace = $null } }
        }
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.PatchAttempts | Should -Be 1
        Assert-TestAutomationRunbookPatch
        ($fixture.Calls -join '|') | Should -Not -Match 'PUT |POST |DELETE |/draft|publish\?'
    }

    It 'distinguishes <Problem> metadata shapes during readback' -ForEach @(
        @{ Problem = 'missing tags become null' }, @{ Problem = 'null tags become missing' },
        @{ Problem = 'null tags become empty' }, @{ Problem = 'missing description becomes null' }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        switch ($Problem) {
            'missing tags become null' {
                $fixture.Runbook.PSObject.Properties.Remove('tags')
                $fixture.AfterPatch = { param($f) $f.Runbook | Add-Member -NotePropertyName tags -NotePropertyValue $null }
            }
            'null tags become missing' {
                $fixture.Runbook.tags = $null
                $fixture.AfterPatch = { param($f) $f.Runbook.PSObject.Properties.Remove('tags') }
            }
            'null tags become empty' {
                $fixture.Runbook.tags = $null
                $fixture.AfterPatch = { param($f) $f.Runbook.tags = [pscustomobject]@{} }
            }
            'missing description becomes null' {
                $fixture.Runbook.properties.PSObject.Properties.Remove('description')
                $fixture.AfterPatch = { param($f) $f.Runbook.properties | Add-Member -NotePropertyName description -NotePropertyValue $null }
            }
        }
        { Invoke-TestAutomationRunbookFixture } | Should -Throw
        $fixture.PatchAttempts | Should -Be 1
    }

    It 'fails closed once when <Stage> throws' -ForEach @(
        @{ Stage = 'ownership'; ExpectedPatches = 0 },
        @{ Stage = 'runtime GET'; ExpectedPatches = 0 },
        @{ Stage = 'runbook GET'; ExpectedPatches = 0 },
        @{ Stage = 'content GET'; ExpectedPatches = 0 },
        @{ Stage = 'PATCH before apply'; ExpectedPatches = 1 },
        @{ Stage = 'PATCH after apply'; ExpectedPatches = 1 },
        @{ Stage = 'readback GET'; ExpectedPatches = 1 },
        @{ Stage = 'readback content GET'; ExpectedPatches = 1 }
    ) {
        $fixture = $global:azdAutomationRunbookTestFixture
        $fixture.FailAt = $Stage
        { Invoke-TestAutomationRunbookFixture } | Should -Throw '*simulated*'
        $fixture.PatchAttempts | Should -Be $ExpectedPatches
        $fixture.OwnershipAttempts | Should -Be 1
        $fixture.RuntimeGets | Should -BeLessOrEqual 1
        $fixture.RunbookGets | Should -BeLessOrEqual 2
        $fixture.ContentGets | Should -BeLessOrEqual 2
        if ($Stage -eq 'ownership') { $fixture.Calls | Should -Be @('OWNERSHIP') }
        if ($Stage -like 'PATCH*') {
            $fixture.RunbookGets | Should -Be 1
            $fixture.ContentGets | Should -Be 1
        }
    }
}
