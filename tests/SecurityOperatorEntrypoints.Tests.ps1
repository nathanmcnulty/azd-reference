BeforeAll {
    $component=Join-Path $PSScriptRoot '../components/powershell/security-automation-runtime'
    . (Join-Path $PSScriptRoot 'fixtures/SecurityOperatorHarness.ps1')
}
AfterAll { Remove-SecurityOperatorHarness }
Describe 'Actual security operator entrypoint Azure boundaries' {
    BeforeEach { New-SecurityOperatorFixture -Component $component -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) }
    It '<Entry> rejects <Fault> before any downstream mutation' -ForEach @(
        foreach ($entry in @('Publisher','Schedule','Deploy','Initialize')) {
            foreach ($fault in @('missing-subscription','missing-tenant','malformed-subscription','malformed-tenant','wrong-subscription','wrong-tenant','Disabled','missing-state','malformed-state','failed-metadata','wrong-resource','missing-resource')) { @{Entry=$entry;Fault=$fault} }
        }
    ) {
        $f=$global:SecurityOperator
        switch ($Fault) {
            missing-subscription { $f.Environment.Remove('AZURE_SUBSCRIPTION_ID') }
            missing-tenant { $f.Environment.Remove('AZURE_TENANT_ID') }
            malformed-subscription { $f.Environment.AZURE_SUBSCRIPTION_ID='not-a-guid' }
            malformed-tenant { $f.Environment.AZURE_TENANT_ID='not-a-guid' }
            Disabled { $f.State='Disabled' }
            default { $f.Fault=$Fault }
        }
        # Force initialization to have pending persistent defaults, so early ordering is observable.
        if ($Entry -eq 'Initialize') { $f.Environment.Remove('SECURITY_PUBLISHER_PRINCIPAL_ID') }
        { Invoke-SecurityOperatorEntry $Entry } | Should -Throw
        $f.Writes.Count | Should -Be 0
        @($f.Events | Where-Object { $_ -eq 'Package' }).Count | Should -Be 0
    }
    It 'preflights both storage and compute before upload: <_>' -ForEach @('wrong-storage','wrong-compute') {
        $global:SecurityOperator.Fault=$_
        { Invoke-SecurityOperatorEntry Publisher } | Should -Throw
        $global:SecurityOperator.Writes.Count | Should -Be 0
    }
    It '<_> leaves an unrelated CLI default untouched with explicit target selectors' -ForEach @('Publisher','Schedule','Deploy','Initialize') {
        $f=$global:SecurityOperator
        $default=$f.DefaultSubscription
        $result=Invoke-SecurityOperatorEntry $_
        $f.DefaultSubscription | Should -Be $default
        $f.Writes.Count | Should -BeGreaterThan 0
        @($f.Native | Where-Object { $_ -match '^az account set' }).Count | Should -Be 0
        if ($_ -in @('Publisher','Deploy')) { $result.sourcePublished | Should -BeTrue }
        if ($_ -in @('Schedule','Initialize')) { $f.ScheduleEnabled | Should -BeFalse }
    }
    It 'publishes the default runbook for <_> and checks fresh Enabled state immediately before each write' -ForEach @('automation','logic-app','function') {
        $f=$global:SecurityOperator
        $f.Environment.SECURITY_COMPUTE_MODE=$_
        $result=Invoke-SecurityOperatorEntry Publisher
        $result.sourcePublished | Should -BeTrue
        $result.scheduleEnabled | Should -BeFalse
        ($f.Writes -join ',') | Should -Be $(if($_ -eq 'function'){'Blob,Function'}else{'Blob,Content,Publish'})
        for ($index=0;$index -lt $f.Events.Count;$index++) {
            if ($f.Events[$index] -in @('Blob','Function','Content','Publish')) { $f.Events[$index-1] | Should -Be 'Subscription:Enabled' }
        }
    }
    It 'stops Function deployment when the subscription becomes Disabled after upload' {
        $f=$global:SecurityOperator
        $f.Environment.SECURITY_COMPUTE_MODE='function';$f.DisableAfter='Blob'
        $receipt=@()
        { $receipt=@(Invoke-SecurityOperatorEntry Publisher) } | Should -Throw
        ($f.Writes -join ',') | Should -Be 'Blob'
        $receipt.Count | Should -Be 0
    }
    It 'stops remaining Automation publication when disabled after <_>' -ForEach @('Blob','Content') {
        $f=$global:SecurityOperator;$f.DisableAfter=$_
        { Invoke-SecurityOperatorEntry Publisher } | Should -Throw
        ($f.Writes -join ',') | Should -Be $(if($_ -eq 'Blob'){'Blob'}else{'Blob,Content'})
    }
    It 'rechecks after package creation before uploading or persisting state' {
        $f=$global:SecurityOperator;$f.DisableAfter='Package'
        { Invoke-SecurityOperatorEntry Deploy } | Should -Throw
        @($f.Events | Where-Object { $_ -eq 'Package' }).Count | Should -Be 1
        $f.Writes.Count | Should -Be 0
    }
    It 'stops persistent deployment metadata if disabled after publication' {
        $f=$global:SecurityOperator;$f.DisableAfter='Publish'
        $receipt=@()
        { $receipt=@(Invoke-SecurityOperatorEntry Deploy) } | Should -Throw
        ($f.Writes -join ',') | Should -Be 'Blob,Content,Publish'
        $receipt.Count | Should -Be 0
    }
    It 'stops provision or later metadata writes if disabled at <_>' -ForEach @('EnvSet:SECURITY_BUNDLE_BLOB','EnvSet:SECURITY_BUNDLE_SHA256','Provision') {
        $f=$global:SecurityOperator;$f.DisableAfter=$_
        $receipt=@()
        { $receipt=@(Invoke-SecurityOperatorEntry Deploy) } | Should -Throw
        $f.Writes[$f.Writes.Count-1] | Should -Be $_
        $f.Writes | Should -Not -Contain 'EnvSet:SECURITY_DEPLOYED_COMPUTE_MODE'
        $receipt.Count | Should -Be 0
    }
    It 'keeps azd writes bound to the captured environment after the global selection changes' {
        $f=$global:SecurityOperator;$f.ChangeSelectedOnPackage=$true
        $result=Invoke-SecurityOperatorEntry Deploy
        $result.sourcePublished | Should -BeTrue
        $f.SelectedEnvironment | Should -Be 'unrelated-environment'
        @($f.Native | Where-Object { $_ -match '^azd (env set|provision)' -and $_ -notlike '*--environment approved-environment*' }).Count | Should -Be 0
        $f.ProvisionedHash | Should -Be $result.bundleSha256
    }
    It 'rejects changed persisted target selectors before deployment metadata or provision' {
        $f=$global:SecurityOperator;$f.ChangeTargetOnPackage=$true
        { Invoke-SecurityOperatorEntry Deploy } | Should -Throw '*target changed*'
        $f.Writes.Count | Should -Be 0
    }
    It 'requires an explicit captured azd environment before packaging' {
        $f=$global:SecurityOperator;$f.Environment.Remove('AZURE_ENV_NAME')
        { Invoke-SecurityOperatorEntry Deploy } | Should -Throw '*AZURE_ENV_NAME*'
        $f.Writes.Count | Should -Be 0
        @($f.Events | Where-Object { $_ -eq 'Package' }).Count | Should -Be 0
    }
    It '<_> preserves WhatIf without reads, tokens or writes' -ForEach @('Publisher','Schedule') {
        Invoke-SecurityOperatorEntry $_ -WhatIf
        $global:SecurityOperator.Writes.Count | Should -Be 0
        $global:SecurityOperator.Native.Count | Should -Be 0
        $global:SecurityOperator.Http.Count | Should -Be 0
    }
    It 'refreshes the schedule guard at the PATCH boundary after a successful preflight' {
        $f=$global:SecurityOperator;$f.DisableOnSubscriptionRead=4
        { Invoke-SecurityOperatorEntry Schedule } | Should -Throw
        $f.SubscriptionReads | Should -Be 4
        $f.Writes.Count | Should -Be 0
    }
    It 'does not hide an invalid account behind AllowMissing on the real pause caller' {
        $f=$global:SecurityOperator;$f.Fault='wrong-resource';$f.ScheduleMissing=$true
        { Invoke-SecurityOperatorEntry Initialize } | Should -Throw
        $f.Writes.Count | Should -Be 0
    }
    It 'allows only a verified missing schedule during initial pause' {
        $f=$global:SecurityOperator;$f.ScheduleMissing=$true
        { Invoke-SecurityOperatorEntry Initialize } | Should -Not -Throw
        ($f.Writes -join ',') | Should -Be 'Patch'
    }
    It 'fails closed on a missing post-PATCH readback even with AllowMissing' {
        $f=$global:SecurityOperator;$f.ScheduleReadMissing=$true
        { Invoke-SecurityOperatorEntry Initialize } | Should -Throw '*verify*schedule*'
        ($f.Writes -join ',') | Should -Be 'Patch'
    }
    It 'stops initialization defaults and pause after the first persistent write disables the subscription' {
        $f=$global:SecurityOperator
        $f.Environment.Remove('SECURITY_PUBLISHER_PRINCIPAL_ID')
        $f.DisableAfter='EnvSet:SECURITY_PUBLISHER_PRINCIPAL_ID'
        { Invoke-SecurityOperatorEntry Initialize } | Should -Throw
        ($f.Writes -join ',') | Should -Be 'EnvSet:SECURITY_PUBLISHER_PRINCIPAL_ID'
    }
}
