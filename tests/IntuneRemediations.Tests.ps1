BeforeAll {
    $script:componentRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'components/powershell/intune-remediations'
    Import-Module (Join-Path $script:componentRoot 'Intune.DeviceHealthScripts.psm1') -Force
    function New-TestRemediationPackage([string]$Directory) {
        $null=New-Item -ItemType Directory -Path $Directory -Force
        $detectionBytes=[Text.UTF8Encoding]::new($false).GetBytes("Write-Output 'collector-test'; exit 1`n")
        $remediationBytes=[IO.File]::ReadAllBytes((Join-Path $script:componentRoot 'reviewed-noops/Av.ps1'))
        [IO.File]::WriteAllBytes((Join-Path $Directory 'detection.ps1'),$detectionBytes)
        [IO.File]::WriteAllBytes((Join-Path $Directory 'remediation.ps1'),$remediationBytes)
        $manifest=[ordered]@{
            schemaVersion='1.0';packageType='intuneDeviceHealthScript';identityKey='test/collector/v1'
            displayName='Test collector';description='Offline test package';publisher='Test';version='1.0'
            detectionScript=@{path='detection.ps1';sha256=(Get-FileHash "$Directory/detection.ps1").Hash.ToLowerInvariant();byteLength=(Get-Item "$Directory/detection.ps1").Length}
            remediationScript=@{path='remediation.ps1';sha256=(Get-FileHash "$Directory/remediation.ps1").Hash.ToLowerInvariant();byteLength=(Get-Item "$Directory/remediation.ps1").Length;behavior='noop'}
            execution=@{runAsAccount='system';runAs32Bit=$false;enforceSignatureCheck=$false;minimumPowerShell='5.1'}
            assignment=@{runRemediationScript=$false;schedule=@{type='daily';interval=1;useUtc=$true;time='03:00:00'}}
            evidenceBoundary='Test only; no endpoint acceptance claim.'
        }
        [IO.File]::WriteAllText("$Directory/package.json",($manifest|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
        "$Directory/package.json"
    }
    function New-TestRemoteDeviceHealthScript([string]$PackagePath,[string]$Id='33333333-3333-4333-8333-333333333333',[string]$ServiceVersion='1') {
        $manifest=Get-Content $PackagePath -Raw|ConvertFrom-Json
        $root=Split-Path $PackagePath
        [pscustomobject]@{
            id=$Id;displayName=$manifest.displayName;description=('{0} [azd-managed-id:{1}]' -f $manifest.description,$manifest.identityKey)
            publisher=$manifest.publisher;version=$ServiceVersion;isGlobalScript=$false;enforceSignatureCheck=$false
            deviceHealthScriptType='deviceHealthScript';roleScopeTagIds=@('0');runAsAccount='system';runAs32Bit=$false
            detectionScriptContent=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root $manifest.detectionScript.path)))
            remediationScriptContent=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root $manifest.remediationScript.path)))
            detectionScriptParameters=@();remediationScriptParameters=@()
        }
    }
    function New-TestRemoteAssignment([string]$Time='03:00:00',[int]$Interval=1,[bool]$UseUtc=$true) {
        [pscustomobject]@{
            id='77777777-7777-4777-8777-777777777777'
            target=[pscustomobject]@{'@odata.type'='#microsoft.graph.allDevicesAssignmentTarget'}
            runRemediationScript=$false
            runSchedule=[pscustomobject]@{'@odata.type'='microsoft.graph.deviceHealthScriptDailySchedule';interval=$Interval;useUtc=$UseUtc;time=$Time}
        }
    }
}

Describe 'Optional on-demand collector validation' {
    BeforeEach {
        $script:packagePath=New-TestRemediationPackage (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $script:requestPath=Join-Path $script:componentRoot 'Request-IntuneCollectorRun.ps1'
        $script:requestArguments=@{TargetTenantId='11111111-1111-4111-8111-111111111111';CallerTenantId='11111111-1111-4111-8111-111111111111';DeviceHealthScriptId='33333333-3333-4333-8333-333333333333';ManagedDeviceId='44444444-4444-4444-8444-444444444444';ExpectedEntraDeviceId='55555555-5555-4555-8555-555555555555';PackageManifestPath=$script:packagePath;ReceiptPath="$TestDrive/request-$([guid]::NewGuid().ToString('N')).json"}
        $script:requestCalls=[Collections.Generic.List[object]]::new()
        $script:requestTestState=@{signature=$false;race=$false;throwPost=$false;version='1';scheduleInterval=1;scheduleUseUtc=$true;scheduleTime='03:00:00';detectionContent=$null;remediationContent=$null}
        $calls=$script:requestCalls;$state=$script:requestTestState;$receiptPath=$script:requestArguments.ReceiptPath
        $manifest=Get-Content $script:packagePath -Raw|ConvertFrom-Json
        $script:requestTestState.detectionContent=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path (Split-Path $script:packagePath) 'detection.ps1')))
        $script:requestTestState.remediationContent=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path (Split-Path $script:packagePath) 'remediation.ps1')))
        $script:requestTransport={
            param($Method,$Uri,$Body)
            $calls.Add([pscustomobject]@{method=$Method;uri=$Uri;body=$Body})
            if($Method -eq 'POST'){if($state.throwPost){throw 'Simulated transport timeout'};return}
            if($Uri.EndsWith('/assignments')){return [pscustomobject]@{value=@([pscustomobject]@{target=[pscustomobject]@{'@odata.type'='#microsoft.graph.allDevicesAssignmentTarget'};runRemediationScript=$false;runSchedule=[pscustomobject]@{'@odata.type'='microsoft.graph.deviceHealthScriptDailySchedule';interval=$state.scheduleInterval;useUtc=$state.scheduleUseUtc;time=$state.scheduleTime}})}}
            if($Uri -match '/managedDevices/'){
                if($state.race){Set-Content $receiptPath 'preserve-racing-receipt'}
                return [pscustomobject]@{id='44444444-4444-4444-8444-444444444444';azureADDeviceId='55555555-5555-4555-8555-555555555555';operatingSystem='Windows';managementAgent='mdm'}
            }
            [pscustomobject]@{id='33333333-3333-4333-8333-333333333333';displayName=$manifest.displayName;description=('{0} [azd-managed-id:{1}]' -f $manifest.description,$manifest.identityKey);publisher=$manifest.publisher;version=$state.version;isGlobalScript=$false;enforceSignatureCheck=$state.signature;deviceHealthScriptType='deviceHealthScript';roleScopeTagIds=@('0');runAsAccount='system';runAs32Bit=$false;detectionScriptContent=$state.detectionContent;remediationScriptContent=$state.remediationContent;detectionScriptParameters=@();remediationScriptParameters=@()}
        }.GetNewClosure()
    }
    It 'rejects a context tenant mismatch before any request' {
        $script:requestArguments.CallerTenantId='22222222-2222-4222-8222-222222222222'
        $script:requestArguments.GraphRequest={throw 'Transport must not run'}
        {& $script:requestPath @script:requestArguments -Execute}|Should -Throw '*identities are required*'
    }
    It 'rejects remote script drift before requesting execution' {
        $calls=[Collections.Generic.List[string]]::new()
        $script:requestArguments.GraphRequest={param($Method,$Uri,$Body) $calls.Add($Method);[pscustomobject]@{id='33333333-3333-4333-8333-333333333333';displayName='Other collector';description='Other';runAsAccount='system';runAs32Bit=$false}}.GetNewClosure()
        {& $script:requestPath @script:requestArguments -Execute}|Should -Throw '*differs*'
        @($calls|Where-Object {$_ -ne 'GET'}).Count|Should -Be 0
    }
    It 'preserves an existing request receipt without replaying' {
        Set-Content $script:requestArguments.ReceiptPath 'preserved'
        $script:requestArguments.GraphRequest={throw 'Transport must not run'}
        {& $script:requestPath @script:requestArguments -Execute}|Should -Throw '*already exists*'
        (Get-Content $script:requestArguments.ReceiptPath -Raw).Trim()|Should -Be 'preserved'
    }
    It 'accepts an exit-1 detector only with the exact reviewed no-op companion and retains the endpoint evidence limit' {
        $script:requestArguments.GraphRequest=$script:requestTransport
        $receipt=& $script:requestPath @script:requestArguments -Execute -Confirm:$false
        $receipt.status|Should -Be 'Accepted'
        $receipt.endpointExecutionProven|Should -BeFalse
        (Get-Content (Join-Path (Split-Path $script:packagePath) 'detection.ps1') -Raw)|Should -Match 'exit 1'
        $receipt.onDemandRemediationSha256|Should -Be '1fd8fe911e793b6f04c571855596bcf51d63ff407bc2e886286626b49f3c698a'
        $posts=@($script:requestCalls|Where-Object method -eq 'POST')
        $posts.Count|Should -Be 1
        $posts[0].uri|Should -Be 'https://graph.microsoft.com/beta/deviceManagement/managedDevices/44444444-4444-4444-8444-444444444444/initiateOnDemandProactiveRemediation'
        $posts[0].body.scriptPolicyId|Should -Be '33333333-3333-4333-8333-333333333333'
        @($posts[0].body.Keys)|Should -HaveCount 1
    }
    It 'rejects an arbitrary remediation companion even when its manifest labels it noop' {
        $packageRoot=Split-Path $script:packagePath
        $arbitraryBytes=[Text.UTF8Encoding]::new($false).GetBytes("Write-Output 'not-reviewed'; exit 0`n")
        $remediationPath=Join-Path $packageRoot 'remediation.ps1'
        [IO.File]::WriteAllBytes($remediationPath,$arbitraryBytes)
        $manifest=Get-Content $script:packagePath -Raw|ConvertFrom-Json
        $manifest.remediationScript.sha256=(Get-FileHash $remediationPath).Hash.ToLowerInvariant()
        $manifest.remediationScript.byteLength=$arbitraryBytes.Length
        $manifest.remediationScript.behavior='noop'
        [IO.File]::WriteAllText($script:packagePath,($manifest|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
        $script:requestTestState.remediationContent=[Convert]::ToBase64String($arbitraryBytes)
        $script:requestArguments.GraphRequest=$script:requestTransport
        {& $script:requestPath @script:requestArguments -Execute -Confirm:$false}|Should -Throw '*hash-locked no-op*'
        @($script:requestCalls|Where-Object method -eq 'POST').Count|Should -Be 0
    }
    It 'rejects changed signature enforcement before requesting a run' {
        $script:requestTestState.signature=$true
        $script:requestArguments.GraphRequest=$script:requestTransport
        {& $script:requestPath @script:requestArguments -Execute}|Should -Throw '*differs*'
        @($script:requestCalls|Where-Object method -eq 'POST').Count|Should -Be 0
    }
    It 'rejects a noncanonical service version before requesting a run' {
        $script:requestTestState.version='1.0'
        $script:requestArguments.GraphRequest=$script:requestTransport
        {& $script:requestPath @script:requestArguments -Execute}|Should -Throw '*differs from the reviewed package*'
        @($script:requestCalls|Where-Object method -eq 'POST').Count|Should -Be 0
    }
    It 'rejects assignment schedule drift before requesting a run' {
        $script:requestTestState.scheduleInterval=7
        $script:requestArguments.GraphRequest=$script:requestTransport
        {& $script:requestPath @script:requestArguments -Execute}|Should -Throw '*schedule*'
        @($script:requestCalls|Where-Object method -eq 'POST').Count|Should -Be 0
    }
    It 'rejects a managed-device to Entra-device mismatch before requesting a run' {
        $script:requestArguments.ExpectedEntraDeviceId='66666666-6666-4666-8666-666666666666'
        $script:requestArguments.GraphRequest=$script:requestTransport
        {& $script:requestPath @script:requestArguments -Execute}|Should -Throw '*reviewed Entra device identity*'
        @($script:requestCalls|Where-Object method -eq 'POST').Count|Should -Be 0
    }
    It 'preserves a receipt created during preflight and sends no request' {
        $script:requestTestState.race=$true
        $script:requestArguments.GraphRequest=$script:requestTransport
        {& $script:requestPath @script:requestArguments -Execute}|Should -Throw
        (Get-Content $script:requestArguments.ReceiptPath -Raw).Trim()|Should -Be 'preserve-racing-receipt'
        @($script:requestCalls|Where-Object method -eq 'POST').Count|Should -Be 0
    }
    It 'retains an unknown POST outcome with the exact operation for reconciliation' {
        $script:requestTestState.throwPost=$true
        $script:requestArguments.GraphRequest=$script:requestTransport
        {& $script:requestPath @script:requestArguments -Execute -Confirm:$false}|Should -Throw '*transport timeout*'
        $receipt=Get-Content $script:requestArguments.ReceiptPath -Raw|ConvertFrom-Json
        $receipt.status|Should -Be 'AttemptedUnknownOutcome'
        $receipt.accepted|Should -BeFalse
        $receipt.method|Should -Be 'POST'
        $receipt.body.scriptPolicyId|Should -Be '33333333-3333-4333-8333-333333333333'
        $receipt.endpointExecutionProven|Should -BeFalse
    }
}

Describe 'Canonical Intune Remediations component' {
    BeforeEach {$script:packagePath=New-TestRemediationPackage (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))}
    It 'accepts a schema-valid package with exact script hashes' {
        (Get-Content $script:packagePath -Raw|Test-Json -SchemaFile "$script:componentRoot/remediation-package.schema.json")|Should -BeTrue
        (Import-IntuneDeviceHealthScriptPackage -ManifestPath $script:packagePath).Manifest.identityKey|Should -Be 'test/collector/v1'
    }
    It 'rejects changed script bytes before any Graph request' {
        Add-Content (Join-Path (Split-Path $script:packagePath) 'detection.ps1') 'changed'
        {Import-IntuneDeviceHealthScriptPackage -ManifestPath $script:packagePath}|Should -Throw '*hash mismatch*'
    }
    It 'rejects a tenant mismatch before invoking the transport' {
        $calls=[Collections.Generic.List[string]]::new()
        $caller={param($Method,$Uri,$Body) $calls.Add($Uri)}.GetNewClosure()
        {Invoke-IntuneDeviceHealthScriptPublication -PackageManifestPath $script:packagePath -TargetTenantId '11111111-1111-4111-8111-111111111111' -CallerTenantId '22222222-2222-4222-8222-222222222222' -AssignmentScope AllDevices -GraphRequest $caller -ReviewOutputPath "$TestDrive/wrong-tenant.json"}|Should -Throw '*does not match*'
        $calls.Count|Should -Be 0
    }
    It 'prepares a plan without any mutation' {
        $calls=[Collections.Generic.List[string]]::new()
        $caller={param($Method,$Uri,$Body) $calls.Add($Method);[pscustomobject]@{value=@()}}.GetNewClosure()
        $plan=Invoke-IntuneDeviceHealthScriptPublication -PackageManifestPath $script:packagePath -TargetTenantId '11111111-1111-4111-8111-111111111111' -CallerTenantId '11111111-1111-4111-8111-111111111111' -AssignmentScope AllDevices -GraphRequest $caller -ReviewOutputPath "$TestDrive/plan.json"
        $plan.status|Should -Be 'planned'
        @($calls|Where-Object {$_ -ne 'GET'}).Count|Should -Be 0
    }
    It 'publishes without sending local package version and accepts native service version 1' {
        $remote=New-TestRemoteDeviceHealthScript -PackagePath $script:packagePath
        $assignment=New-TestRemoteAssignment
        $state=@{scriptCreated=$false;assignmentCreated=$false;createBody=$null;calls=[Collections.Generic.List[object]]::new()}
        $caller={
            param($Method,$Uri,$Body)
            $state.calls.Add([pscustomobject]@{method=$Method;uri=$Uri;body=$Body})
            if($Method -eq 'GET' -and $Uri -eq 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'){return [pscustomobject]@{value=@()}}
            if($Method -eq 'POST' -and $Uri -eq 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'){$state.scriptCreated=$true;$state.createBody=$Body;return [pscustomobject]@{id=$remote.id}}
            if($Method -eq 'GET' -and $Uri.EndsWith('/assignments')){return [pscustomobject]@{value=if($state.assignmentCreated){@($assignment)}else{@()}}}
            if($Method -eq 'POST' -and $Uri.EndsWith('/assignments')){$state.assignmentCreated=$true;return [pscustomobject]@{id=$assignment.id}}
            if($Method -eq 'GET' -and $Uri.EndsWith('/'+$remote.id)){return $remote}
            throw "Unexpected request $Method $Uri"
        }.GetNewClosure()
        $review=Invoke-IntuneDeviceHealthScriptPublication -PackageManifestPath $script:packagePath -TargetTenantId '11111111-1111-4111-8111-111111111111' -CallerTenantId '11111111-1111-4111-8111-111111111111' -AssignmentScope AllDevices -GraphRequest $caller -ReviewOutputPath "$TestDrive/native-version-execute.json" -Execute
        $review.status|Should -Be 'validated'
        $review.packageVersion|Should -Be '1.0'
        $review.serviceVersion|Should -Be '1'
        $state.createBody.PSObject.Properties['version']|Should -BeNullOrEmpty
    }
    It 'rejects a noncanonical remote service version without mutation' {
        $remote=New-TestRemoteDeviceHealthScript -PackagePath $script:packagePath -ServiceVersion '1.0'
        $calls=[Collections.Generic.List[string]]::new()
        $caller={
            param($Method,$Uri,$Body)
            $calls.Add($Method)
            if($Uri -eq 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'){return [pscustomobject]@{value=@([pscustomobject]@{id=$remote.id;displayName=$remote.displayName;description=$remote.description})}}
            if($Uri.EndsWith('/assignments')){return [pscustomobject]@{value=@()}}
            return $remote
        }.GetNewClosure()
        {Invoke-IntuneDeviceHealthScriptPublication -PackageManifestPath $script:packagePath -TargetTenantId '11111111-1111-4111-8111-111111111111' -CallerTenantId '11111111-1111-4111-8111-111111111111' -AssignmentScope AllDevices -GraphRequest $caller -ReviewOutputPath "$TestDrive/invalid-service-version.json"}|Should -Throw '*canonical positive integer*'
        @($calls|Where-Object {$_ -ne 'GET'}).Count|Should -Be 0
    }
    It 'rejects remote script content drift before assignment' {
        $remote=New-TestRemoteDeviceHealthScript -PackagePath $script:packagePath
        $remote.detectionScriptContent=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('changed remote collector'))
        $state=@{calls=[Collections.Generic.List[object]]::new()}
        $caller={
            param($Method,$Uri,$Body)
            $state.calls.Add([pscustomobject]@{method=$Method;uri=$Uri})
            if($Method -eq 'GET' -and $Uri -eq 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'){return [pscustomobject]@{value=@()}}
            if($Method -eq 'POST' -and $Uri -eq 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'){return [pscustomobject]@{id=$remote.id}}
            if($Method -eq 'GET' -and $Uri.EndsWith('/'+$remote.id)){return $remote}
            throw "Unexpected request $Method $Uri"
        }.GetNewClosure()
        {Invoke-IntuneDeviceHealthScriptPublication -PackageManifestPath $script:packagePath -TargetTenantId '11111111-1111-4111-8111-111111111111' -CallerTenantId '11111111-1111-4111-8111-111111111111' -AssignmentScope AllDevices -GraphRequest $caller -ReviewOutputPath "$TestDrive/content-drift-execute.json" -Execute}|Should -Throw '*readback did not match*'
        @($state.calls|Where-Object {$_.method -eq 'POST' -and $_.uri.EndsWith('/assignments')}).Count|Should -Be 0
    }
    It 'reports local package and native service versions in readback' {
        $remote=New-TestRemoteDeviceHealthScript -PackagePath $script:packagePath
        $assignment=New-TestRemoteAssignment
        $caller={
            param($Method,$Uri,$Body)
            if($Uri.EndsWith('/assignments')){return [pscustomobject]@{value=@($assignment)}}
            if($Uri.EndsWith('/deviceRunStates')){return [pscustomobject]@{value=@()}}
            return $remote
        }.GetNewClosure()
        $readback=Get-IntuneDeviceHealthScriptReadback -TargetTenantId '11111111-1111-4111-8111-111111111111' -CallerTenantId '11111111-1111-4111-8111-111111111111' -DeviceHealthScriptId $remote.id -PackageManifestPath $script:packagePath -AssignmentScope AllDevices -GraphRequest $caller -OutputProjector {param($Output,$State,$StateTime,$Now,$MaximumStateAgeHours)} -OutputPath "$TestDrive/service-version-readback.json"
        $readback.package.version|Should -Be '1.0'
        $readback.deviceHealthScript.serviceVersion|Should -Be '1'
    }
    It 'rejects a same-host continuation into another Graph resource' {
        $caller={param($Method,$Uri,$Body) [pscustomobject]@{value=@();'@odata.nextLink'='https://graph.microsoft.com/beta/users'}}
        {Invoke-IntuneDeviceHealthScriptPublication -PackageManifestPath $script:packagePath -TargetTenantId '11111111-1111-4111-8111-111111111111' -CallerTenantId '11111111-1111-4111-8111-111111111111' -AssignmentScope AllDevices -GraphRequest $caller -ReviewOutputPath "$TestDrive/unsafe-page.json"}|Should -Throw '*Unsafe Graph paging URI*'
    }
}
