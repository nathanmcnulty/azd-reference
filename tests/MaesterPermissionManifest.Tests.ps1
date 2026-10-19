BeforeAll {
    $manifestPath = Join-Path $PSScriptRoot '../components/powershell/maester-azd-hooks/Maester-GraphPermissions.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
}
Describe 'Maester 2.3.0 reviewed application permission inventory' {
    It 'binds stable module, bundled tests, source and package bytes together' {
        $manifest.schemaVersion | Should -BeExactly '1.0'
        $manifest.manifestVersion | Should -BeExactly '1.0.0'
        $manifest.maesterVersion | Should -BeExactly '2.3.0'
        $manifest.resourceAppId | Should -BeExactly '00000003-0000-0000-c000-000000000000'
        $manifest.upstream.sourceCommit | Should -BeExactly '7413c42d3fcc724dfea94d2726e690ddd364d914'
        $manifest.upstream.packageSha256 | Should -BeExactly '95F720822D04271F5E15F4665BC017111DC72E17B97E5D0525CB4EC2FF5BD0B0'
        $manifest.upstream.packageUrl | Should -BeExactly 'https://www.powershellgallery.com/api/v2/package/Maester/2.3.0'
        $manifest.upstream.bundledTests.testFileCount | Should -Be 519
        $manifest.upstream.bundledTests.allFileCount | Should -Be 524
        $manifest.upstream.bundledTests.configVersion | Should -BeExactly '2026.10.06.1'
        $manifest.upstream.bundledTests.fileInventorySha256 | Should -Match '^[a-f0-9]{64}$'
    }
    It 'preserves exactly the original eight Minimal roles' {
        $expected = @('Directory.Read.All','DirectoryRecommendations.Read.All','IdentityRiskEvent.Read.All','Policy.Read.All','Policy.Read.ConditionalAccess','RoleManagement.Read.All','Reports.Read.All','UserAuthenticationMethod.Read.All')
        @($manifest.profiles.Minimal).Count | Should -Be 8
        @(Compare-Object $expected $manifest.profiles.Minimal).Count | Should -Be 0
    }
    It 'builds Full from 25 upstream defaults plus two reviewed application-specific reads' {
        @($manifest.upstream.defaultReadScopes).Count | Should -Be 25
        @($manifest.profiles.Full).Count | Should -Be 27
        $expected = @($manifest.upstream.defaultReadScopes) + @('Policy.Read.DeviceConfiguration','Sites.Read.All')
        @(Compare-Object $expected $manifest.profiles.Full).Count | Should -Be 0
        @($manifest.reviewedSupplements.role | Sort-Object) | Should -Be @('Policy.Read.DeviceConfiguration','Sites.Read.All')
        $manifest.applicationRoles['Policy.Read.DeviceConfiguration'].applicationRoleId | Should -BeExactly 'bdba4817-6ba1-4a7c-8a01-be9bc7c242dd'
        $manifest.applicationRoles['Sites.Read.All'].applicationRoleId | Should -BeExactly '332a536c-c7ef-4017-ab91-336970924f0d'
    }
    It 'preserves Extended as the explicit legacy 19 roles, not a Full alias' {
        $expected = @($manifest.profiles.Minimal) + @('DeviceManagementConfiguration.Read.All','DeviceManagementServiceConfig.Read.All','DeviceManagementManagedDevices.Read.All','DeviceManagementRBAC.Read.All','PrivilegedAccess.Read.AzureAD','ReportSettings.Read.All','RoleEligibilitySchedule.Read.Directory','SecurityIdentitiesHealth.Read.All','SecurityIdentitiesSensors.Read.All','SharePointTenantSettings.Read.All','ThreatHunting.Read.All')
        @($manifest.profiles.Extended).Count | Should -Be 19
        @(Compare-Object $expected $manifest.profiles.Extended).Count | Should -Be 0
        $manifest.profiles.Full | Should -Not -Contain 'PrivilegedAccess.Read.AzureAD'
    }
    It 'separates mail, report privacy writes, setup administration and preview roles' {
        @($manifest.optionalCapabilities.MailSend) | Should -Be @('Mail.Send')
        @($manifest.optionalCapabilities.ReportSettingsWrite) | Should -Be @('ReportSettings.ReadWrite.All')
        foreach ($profile in $manifest.profiles.Values) {
            @($profile | Select-Object -Unique).Count | Should -Be @($profile).Count
            foreach ($role in $profile) {
                $role | Should -Not -Match 'Write|Send|Directory.AccessAsUser|AppRoleAssignment|AgentIdentity'
            }
        }
        $manifest.profiles.Full | Should -Not -Contain 'Application.Read.All'
        $manifest.applicationRoles.Keys | Should -Not -Contain 'ChannelMessage.Send'
        @($manifest.coverage.separatePreviewReadRoles).Count | Should -Be 4
        $manifest.separateWorkloadRequirements.ExchangeOnline.applicationRoles | Should -Be @('Exchange.ManageAsApp')
    }
    It 'records only application-role identities for every grantable role' {
        $roles = @($manifest.profiles.Values | ForEach-Object { $_ }) + @($manifest.optionalCapabilities.Values | ForEach-Object { $_ })
        foreach ($role in @($roles | Select-Object -Unique)) {
            $manifest.applicationRoles.ContainsKey($role) | Should -BeTrue
            $manifest.applicationRoles[$role].permissionType | Should -BeExactly 'Application'
            $manifest.applicationRoles[$role].applicationRoleId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            $manifest.applicationRoles[$role].source | Should -Match '^https://learn.microsoft.com/en-us/graph/permissions-reference#'
        }
        # Application IDs must not be copied from their same-named delegated scopes.
        $manifest.applicationRoles['Directory.Read.All'].applicationRoleId | Should -BeExactly '7ab1d382-f21e-4acd-a863-ba3e13f7da61'
        $manifest.applicationRoles['Directory.Read.All'].applicationRoleId | Should -Not -Be '06da0dbc-49e2-44d2-8312-53f166ab848a'
    }
    It 'preserves visible coverage limits and the broad site-read consequence' {
        $manifest.coverage.defaultExcludedTags | Should -Be @('Preview','LongRunning')
        ($manifest.reviewedSupplements | Where-Object role -EQ 'Sites.Read.All').consequence | Should -Match 'documents and list items across all site collections'
        $manifest.capabilityConsequences.ReportSettingsWrite | Should -Match 'Restoration can fail'
        ($manifest.coverage.unverifiedDependencies | Where-Object test -EQ 'Test-MtCisaNotifyHighRisk').endpoint | Should -BeExactly 'GET beta/identityProtection/settings/notifications'
        $onPremGap = $manifest.coverage.unverifiedDependencies | Where-Object test -EQ 'Test-MtOnPremisesSynchronization.Tests.ps1'
        $onPremGap.reason | Should -Match 'application access as not supported'
        @($onPremGap.sources).Count | Should -Be 2
        @($onPremGap.commands).Count | Should -Be 2
        $manifest.profiles.Full | Should -Contain 'OnPremDirectorySynchronization.Read.All'
    }
}
