BeforeAll {
    $component=Join-Path $PSScriptRoot '../components/powershell/security-automation-runtime'
    function global:azd {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
        $global:LASTEXITCODE=0
        $global:SecurityHookCalls.Add(($Arguments -join ' '))
        if ($Arguments[0] -eq 'env' -and $Arguments[1] -eq 'get-values') { return ($global:SecurityHookEnvironment | ConvertTo-Json) }
        if ($Arguments[0] -eq 'env' -and $Arguments[1] -eq 'set') { $global:SecurityHookEnvironment[$Arguments[2]]=$Arguments[3] }
        if ($Arguments[0] -eq 'provision') { $global:ProvisionedSecurityHash=$global:SecurityHookEnvironment.SECURITY_BUNDLE_SHA256 }
    }
}
AfterAll { Remove-Item Function:/global:azd -ErrorAction SilentlyContinue }
Describe 'Security azd hook transitions' {
BeforeEach {
    $global:SecurityHookCalls=[Collections.Generic.List[string]]::new()
    $global:SecurityHookEnvironment=@{
        SECURITY_COMPUTE_MODE='automation';SECURITY_SCHEDULE_ENABLED='false';SECURITY_BUNDLE_BLOB='unconfigured.zip';SECURITY_BUNDLE_SHA256=''
        SECURITY_AUTOMATION_START='2030-01-01T00:00:00Z';SECURITY_PUBLISHER_PRINCIPAL_ID='';SECURITY_PUBLISHER_PRINCIPAL_TYPE='User'
        SECURITY_AUTOMATION_ACCOUNT='test-automation';AZURE_RESOURCE_GROUP='test-group';AZURE_SUBSCRIPTION_ID='11111111-1111-4111-8111-111111111111';SECURITY_STORAGE_ACCOUNT='teststorage'
    }
}
    It 'explicitly pauses an existing Automation schedule when disabled' {
        $root=Join-Path $TestDrive 'pause'; New-Item -ItemType Directory $root | Out-Null
        Copy-Item "$component/Initialize-SecurityEnvironment.ps1" "$root/Initialize-SecurityEnvironment.ps1"
        Set-Content "$root/Set-SecuritySchedule.ps1" '[CmdletBinding(SupportsShouldProcess)] param($SubscriptionId,$ResourceGroup,$AutomationAccountName,$Enabled,[switch]$AllowMissing) if($Enabled){throw "unexpected enable"}; Set-Content (Join-Path $PSScriptRoot "paused.txt") $AutomationAccountName'
        & "$root/Initialize-SecurityEnvironment.ps1"
        Get-Content "$root/paused.txt" | Should -Be 'test-automation'
    }
    It 'rejects an enabled unconfigured package' {
        $global:SecurityHookEnvironment.SECURITY_SCHEDULE_ENABLED='true'
        { & "$component/Initialize-SecurityEnvironment.ps1" } | Should -Throw '*approved immutable*'
    }
    It 'rejects switching an existing environment to another compute kind' {
        $global:SecurityHookEnvironment.SECURITY_DEPLOYED_COMPUTE_MODE='function'
        { & "$component/Initialize-SecurityEnvironment.ps1" } | Should -Throw '*separate azd environment*'
    }
    It 'refreshes Automation parameters using the published package without republishing' {
        $root=Join-Path $TestDrive 'publish'; New-Item -ItemType Directory $root | Out-Null
        Copy-Item "$component/Deploy-SecuritySource.ps1" "$root/Deploy-SecuritySource.ps1"
        Set-Content "$root/Build-SecurityBundle.ps1" 'param($SolutionRoot,$OutputPath) [pscustomobject]@{path=$OutputPath}'
        Set-Content "$root/Publish-SecurityHost.ps1" '[CmdletBinding(SupportsShouldProcess)] param($ComputeMode,$SubscriptionId,$ResourceGroup,$StorageAccount,$PackagePath,$AutomationAccountName) $global:SecurityPublishCount++; [pscustomobject]@{bundleBlob=("a"*64)+".zip";bundleSha256=("a"*64)}'
        $global:SecurityPublishCount=0
        & "$root/Deploy-SecuritySource.ps1" -SolutionRoot $root | Out-Null
        $global:SecurityPublishCount | Should -Be 1
        $global:ProvisionedSecurityHash | Should -Be ('a'*64)
        @($global:SecurityHookCalls | Where-Object { $_ -eq 'provision --no-prompt' }).Count | Should -Be 1
    }
}
