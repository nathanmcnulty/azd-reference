BeforeAll {
    function global:Get-MgEnvironment {}
    function global:Get-MgContext {}
    function global:Connect-MgGraph {
        param($TenantId, $ClientId, $Environment, $Scopes, $ContextScope, $ClientTimeout, $NoWelcome, $ErrorAction)
    }
    function global:Invoke-MgGraphRequest {
        param($Method, $Uri, $OutputType, $ErrorAction)
    }

    $modulePath = Join-Path $PSScriptRoot '../components/powershell/graph-delegated-authentication/Azd.GraphAuthentication.psd1'
    Import-Module $modulePath -Force
    $script:tenantId = [guid]'11111111-1111-4111-8111-111111111111'
    $script:clientId = [guid]'33333333-3333-4333-8333-333333333333'
    $script:scopes = @('Policy.Read.All', 'RoleManagement.Read.Directory')

    function New-TestGraphContext {
        param(
            [string] $TenantId = $script:tenantId.Guid,
            [AllowNull()][AllowEmptyString()][string] $ClientId = $script:clientId.Guid,
            [string] $Environment = 'Global',
            [string] $Account = 'admin@example.com',
            [string] $AuthType = 'Delegated',
            [string] $ContextScope = 'CurrentUser',
            [string[]] $Scopes = $script:scopes
        )
        [pscustomobject]@{
            TenantId = $TenantId
            ClientId = $ClientId
            Environment = $Environment
            Account = $Account
            AuthType = $AuthType
            ContextScope = $ContextScope
            Scopes = $Scopes
        }
    }

    function New-TestGraphHttpException {
        param(
            [Parameter(Mandatory)][int] $StatusCode,
            [switch] $UnauthorizedType
        )
        $exception = if ($UnauthorizedType) {
            [System.UnauthorizedAccessException]::new('not persisted')
        }
        else {
            [System.Exception]::new('not persisted')
        }
        $exception | Add-Member -NotePropertyName StatusCode -NotePropertyValue $StatusCode
        return $exception
    }
}

AfterAll {
    Remove-Module Azd.GraphAuthentication -Force -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-MgEnvironment, Function:\Get-MgContext, Function:\Connect-MgGraph, Function:\Invoke-MgGraphRequest -ErrorAction SilentlyContinue
}

Describe 'Delegated Microsoft Graph authentication coordination' {
    BeforeEach {
        Mock Get-MgEnvironment -ModuleName Azd.GraphAuthentication {
            @(
                [pscustomobject]@{ Name = 'Global' },
                [pscustomobject]@{ Name = 'USGov' }
            )
        }
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication { New-TestGraphContext }
        Mock Connect-MgGraph -ModuleName Azd.GraphAuthentication
        Mock Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication { [pscustomobject]@{ id = 'probe' } }
    }

    It 'trims, sorts, and deduplicates scopes without adding permissions' {
        $resolved = @(Resolve-AzdGraphScopeSet -Scope @(' RoleManagement.Read.Directory ', 'policy.read.all', 'Policy.Read.All'))

        $resolved | Should -Be @('policy.read.all', 'RoleManagement.Read.Directory')
    }

    It 'rejects empty and malformed scope sets' {
        { Resolve-AzdGraphScopeSet -Scope @() } | Should -Throw
        { Resolve-AzdGraphScopeSet -Scope @('Policy.Read.All', 'not a scope') } | Should -Throw
    }

    It 'preserves CurrentUser as the default and reuses an exact usable context without connecting' {
        $result = Connect-AzdGraphSession `
            -TenantId $tenantId `
            -ExpectedClientId $clientId `
            -Scopes $scopes `
            -ExpectedAccount 'ADMIN@example.com' `
            -ProbeUri '/v1.0/roleManagement/directory/roleDefinitions?$top=1'

        $result.clientId | Should -Be $clientId.Guid
        $result.contextScope | Should -BeExactly 'CurrentUser'
        $result.contextReused | Should -BeTrue
        $result.connectInvoked | Should -BeFalse
        $result.PSObject.Properties.Name | Should -Not -Contain 'accessToken'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 1
    }

    It 'reuses an exact Process context only when Process is explicitly selected' {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication { New-TestGraphContext -ContextScope Process }

        $result = Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -ContextScope Process

        $result.contextScope | Should -BeExactly 'Process'
        $result.contextReused | Should -BeTrue
        $result.connectInvoked | Should -BeFalse
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0 -Exactly
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 1 -Exactly
    }

    It 'preserves the original positional account and timeout arguments with <selection>' -ForEach @(
        @{ selection = 'default CurrentUser scope'; expectedScope = 'CurrentUser'; scopeOptions = @{} }
        @{ selection = 'Process scope selected by name'; expectedScope = 'Process'; scopeOptions = @{ ContextScope = 'Process' } }
    ) {
        $script:contextCalls = 0
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            $script:contextCalls++
            if ($script:contextCalls -eq 1) { return $null }
            return New-TestGraphContext -ContextScope $expectedScope
        }

        $result = Connect-AzdGraphSession $tenantId $clientId $scopes '/v1.0/me' 'Global' 'admin@example.com' 180 -AllowInteractive @scopeOptions

        $result.account | Should -BeExactly 'admin@example.com'
        $result.contextScope | Should -BeExactly $expectedScope
        $result.connectInvoked | Should -BeTrue
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1 -Exactly -ParameterFilter {
            $TenantId -eq $script:tenantId.Guid -and
            $ClientId -eq $script:clientId.Guid -and
            $Environment -eq 'Global' -and
            $ContextScope -ceq $expectedScope -and
            $ClientTimeout -eq 180
        }
    }

    It 'rejects an invalid requested context scope before any Graph command' {
        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -ContextScope Machine -AllowInteractive -AllowContextReplacement } |
            Should -Throw '*ContextScope*'
        Should -Invoke Get-MgEnvironment -ModuleName Azd.GraphAuthentication -Times 0 -Exactly
        Should -Invoke Get-MgContext -ModuleName Azd.GraphAuthentication -Times 0 -Exactly
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0 -Exactly
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0 -Exactly
    }

    It 'refuses a CurrentUser context for Process with <authorization>' -ForEach @(
        @{ authorization = 'neither authorization'; interactive = $false; replacement = $false }
        @{ authorization = 'interactive authorization only'; interactive = $true; replacement = $false }
        @{ authorization = 'replacement authorization only'; interactive = $false; replacement = $true }
        @{ authorization = 'both authorizations'; interactive = $true; replacement = $true }
    ) {
        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -ContextScope Process -AllowInteractive:$interactive -AllowContextReplacement:$replacement } |
            Should -Throw '*cannot replace an inherited non-Process context*fresh pwsh -NoProfile*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0 -Exactly
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0 -Exactly
    }

    It 'connects once with exactly Process scope from <initialContext> and then reuses it' -ForEach @(
        @{ initialContext = 'no context'; inherited = $false }
        @{ initialContext = 'an explicitly replaceable mismatched Process context'; inherited = $true }
    ) {
        $script:contextCalls = 0
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            $script:contextCalls++
            if ($script:contextCalls -eq 1) {
                if ($inherited) { return New-TestGraphContext -ContextScope Process -ClientId '44444444-4444-4444-8444-444444444444' }
                return $null
            }
            return New-TestGraphContext -ContextScope Process
        }

        $first = Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -ContextScope Process -AllowInteractive -AllowContextReplacement:$inherited
        $second = Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -ContextScope Process

        $first.contextScope | Should -BeExactly 'Process'
        $first.connectInvoked | Should -BeTrue
        $first.contextReused | Should -BeFalse
        $second.contextScope | Should -BeExactly 'Process'
        $second.contextReused | Should -BeTrue
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1 -Exactly -ParameterFilter {
            $TenantId -eq $script:tenantId.Guid -and
            $ClientId -eq $script:clientId.Guid -and
            $Environment -eq 'Global' -and
            $ContextScope -ceq 'Process' -and
            $ClientTimeout -eq 300 -and
            $NoWelcome -eq $true -and
            (@($Scopes | Sort-Object) -join ',') -eq (@($script:scopes | Sort-Object) -join ',')
        }
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 2 -Exactly
    }

    It 'refuses an inherited context with missing scope in Process mode even when replacement is authorized' {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication { New-TestGraphContext | Select-Object -Property * -ExcludeProperty ContextScope }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -ContextScope Process -AllowInteractive -AllowContextReplacement } |
            Should -Throw '*cannot replace an inherited non-Process context*fresh pwsh -NoProfile*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0 -Exactly
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0 -Exactly
    }

    It 'rejects a newly connected CurrentUser context when Process was requested without probing or retrying' {
        $script:contextCalls = 0
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            $script:contextCalls++
            if ($script:contextCalls -eq 1) { return $null }
            return New-TestGraphContext
        }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -ContextScope Process -AllowInteractive } |
            Should -Throw '*completed without the required session properties*context scope*Process*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1 -Exactly -ParameterFilter { $ContextScope -ceq 'Process' }
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0 -Exactly
    }

    It 'does not connect when a matching context fails its probe noninteractively' {
        $script:probeException = New-TestGraphHttpException -StatusCode 401
        Mock Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication { throw $script:probeException }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' } |
            Should -Throw '*not usable in this process*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'does not connect when no context is available noninteractively' {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication { $null }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' } |
            Should -Throw '*required for noninteractive execution*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'rejects a blank expected account before any Graph command runs' {
        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount '  ' -ProbeUri '/v1.0/me' } |
            Should -Throw '*ExpectedAccount*'
        Should -Invoke Get-MgEnvironment -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Get-MgContext -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'requires an explicit GUID expected client ID' {
        $parameter = (Get-Command Connect-AzdGraphSession).Parameters['ExpectedClientId']
        $parameter.ParameterType | Should -Be ([guid])
        @($parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
            Should -Be 1
    }

    It 'rejects invalid or default expected client IDs before any Graph command runs' -ForEach @(
        @{ Name = 'empty GUID'; ExpectedId = [guid]::Empty },
        @{ Name = 'empty string'; ExpectedId = '' },
        @{ Name = 'null'; ExpectedId = $null },
        @{ Name = 'malformed'; ExpectedId = 'not-a-client-id' },
        @{ Name = 'SDK default'; ExpectedId = '14d82eec-204b-4c2f-b7e8-296a70dab67e' }
    ) {
        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $ExpectedId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive -AllowContextReplacement } |
            Should -Throw '*ExpectedClientId*'
        Should -Invoke Get-MgEnvironment -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Get-MgContext -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'rejects an inherited <Name> client before probing or silently replacing it' -ForEach @(
        @{ Name = 'wrong'; Context = { New-TestGraphContext -ClientId '44444444-4444-4444-8444-444444444444' } },
        @{ Name = 'SDK default'; Context = { New-TestGraphContext -ClientId '14d82eec-204b-4c2f-b7e8-296a70dab67e' } },
        @{ Name = 'missing property'; Context = { New-TestGraphContext | Select-Object -Property * -ExcludeProperty ClientId } },
        @{ Name = 'null'; Context = { New-TestGraphContext -ClientId $null } },
        @{ Name = 'blank'; Context = { New-TestGraphContext -ClientId '  ' } },
        @{ Name = 'empty GUID'; Context = { New-TestGraphContext -ClientId ([guid]::Empty) } },
        @{ Name = 'malformed'; Context = { New-TestGraphContext -ClientId 'not-a-client-id' } }
    ) {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication { & $Context }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*cannot be replaced without explicit authorization*context client ID*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'does not replace a wrong inherited client noninteractively even when replacement is authorized' {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            New-TestGraphContext -ClientId '44444444-4444-4444-8444-444444444444'
        }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowContextReplacement } |
            Should -Throw '*required for noninteractive execution*context client ID does not match*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'refuses a mismatched inherited account without replacement authorization' {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            New-TestGraphContext -Account 'other@example.com'
        }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*context account does not match*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'rejects each incompatible delegated context property' -ForEach @(
        @{ Name = 'environment'; Context = { New-TestGraphContext -Environment 'USGov' } },
        @{ Name = 'authentication type'; Context = { New-TestGraphContext -AuthType 'AppOnly' } },
        @{ Name = 'context scope'; Context = { New-TestGraphContext -ContextScope 'Process' } }
    ) {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication { & $Context }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' } |
            Should -Throw
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'refuses to replace a mismatched inherited context by default' {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            New-TestGraphContext -TenantId '22222222-2222-4222-8222-222222222222'
        }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*cannot be replaced without explicit authorization*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'connects at most once with the complete exact context when authorized' {
        $script:contextCalls = 0
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            $script:contextCalls++
            if ($script:contextCalls -eq 1) {
                return New-TestGraphContext -TenantId '22222222-2222-4222-8222-222222222222'
            }
            return New-TestGraphContext
        }

        $result = Connect-AzdGraphSession `
            -TenantId $tenantId `
            -ExpectedClientId $clientId `
            -Scopes @('RoleManagement.Read.Directory', 'Policy.Read.All', 'Policy.Read.All') `
            -Environment Global `
            -ExpectedAccount 'admin@example.com' `
            -ProbeUri '/v1.0/roleManagement/directory/roleDefinitions?$top=1' `
            -AllowInteractive `
            -AllowContextReplacement

        $result.connectInvoked | Should -BeTrue
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1 -ParameterFilter {
            $TenantId -eq $script:tenantId.Guid -and
            $ClientId -eq $script:clientId.Guid -and
            $Environment -eq 'Global' -and
            $ContextScope -eq 'CurrentUser' -and
            $NoWelcome -eq $true -and
            (@($Scopes | Sort-Object) -join ',') -eq 'Policy.Read.All,RoleManagement.Read.Directory'
        }
    }

    It 'replaces a wrong client once only when explicitly authorized and then reuses the exact application session' {
        $script:contextCalls = 0
        $script:setupScopes = @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'Policy.Read.All', 'RoleManagement.Read.Directory')
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            $script:contextCalls++
            if ($script:contextCalls -eq 1) {
                return New-TestGraphContext -ClientId '14d82eec-204b-4c2f-b7e8-296a70dab67e' -Scopes $script:setupScopes
            }
            return New-TestGraphContext -Scopes $script:setupScopes
        }

        $first = Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $script:setupScopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive -AllowContextReplacement
        $second = Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $script:setupScopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me'

        $first.clientId | Should -Be $clientId.Guid
        $first.contextReused | Should -BeFalse
        $second.clientId | Should -Be $clientId.Guid
        $second.contextReused | Should -BeTrue
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1 -ParameterFilter {
            $ClientId -eq $script:clientId.Guid -and
            $TenantId -eq $script:tenantId.Guid -and
            $Environment -eq 'Global' -and
            $ContextScope -eq 'CurrentUser' -and
            $NoWelcome -eq $true -and
            (@($Scopes | Sort-Object) -join ',') -eq (@($script:setupScopes | Sort-Object) -join ',')
        }
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 2
    }

    It 'rejects a post-connect <Name> client before probing or retrying' -ForEach @(
        @{ Name = 'wrong'; Context = { New-TestGraphContext -ClientId '44444444-4444-4444-8444-444444444444' } },
        @{ Name = 'SDK default'; Context = { New-TestGraphContext -ClientId '14d82eec-204b-4c2f-b7e8-296a70dab67e' } },
        @{ Name = 'missing property'; Context = { New-TestGraphContext | Select-Object -Property * -ExcludeProperty ClientId } },
        @{ Name = 'null'; Context = { New-TestGraphContext -ClientId $null } },
        @{ Name = 'blank'; Context = { New-TestGraphContext -ClientId '  ' } },
        @{ Name = 'empty GUID'; Context = { New-TestGraphContext -ClientId ([guid]::Empty) } },
        @{ Name = 'malformed'; Context = { New-TestGraphContext -ClientId 'not-a-client-id' } }
    ) {
        $script:contextCalls = 0
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            $script:contextCalls++
            if ($script:contextCalls -eq 1) { return $null }
            return & $Context
        }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*completed without the required session properties*context client ID*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1 -ParameterFilter {
            $ClientId -eq $script:clientId.Guid
        }
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'reauthenticates once when matching metadata has an unusable token and interaction is allowed' {
        $script:probeCalls = 0
        Mock Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication {
            $script:probeCalls++
            if ($script:probeCalls -eq 1) { throw (New-TestGraphHttpException -StatusCode 401) }
            [pscustomobject]@{ id = 'probe' }
        }

        $result = Connect-AzdGraphSession `
            -TenantId $tenantId `
            -ExpectedClientId $clientId `
            -Scopes $scopes `
            -ExpectedAccount 'admin@example.com' `
            -ProbeUri '/v1.0/me' `
            -AllowInteractive

        $result.connectInvoked | Should -BeTrue
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 2
    }

    It 'fails if the resulting context does not prove all requested scopes' {
        $script:contextCalls = 0
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            $script:contextCalls++
            if ($script:contextCalls -eq 1) { return $null }
            return New-TestGraphContext -Scopes @('Policy.Read.All')
        }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*missing scopes*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1
    }

    It 'rejects a wrong account selected during interactive connection before probing' {
        $script:contextCalls = 0
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            $script:contextCalls++
            if ($script:contextCalls -eq 1) { return $null }
            return New-TestGraphContext -Account 'other@example.com'
        }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*context account does not match*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'does not initiate authentication for authorization, throttling, or transport probe failures' -ForEach @(
        @{ Name = 'authorization'; StatusCode = 403 },
        @{ Name = 'throttling'; StatusCode = 429 },
        @{ Name = 'transport'; StatusCode = $null }
    ) {
        $script:probeException = [System.Exception]::new('not persisted')
        if ($null -ne $StatusCode) {
            $script:probeException | Add-Member -NotePropertyName StatusCode -NotePropertyValue $StatusCode
        }
        Mock Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication { throw $script:probeException }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*Authentication was not started*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'treats an explicit 403 as authorization even when the exception type says unauthorized' {
        $script:probeException = New-TestGraphHttpException -StatusCode 403 -UnauthorizedType
        Mock Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication { throw $script:probeException }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*Classification: authorization*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'fails if the post-connect read-only probe is not usable' {
        $script:contextCalls = 0
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            $script:contextCalls++
            if ($script:contextCalls -eq 1) { return $null }
            return New-TestGraphContext
        }
        Mock Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication { throw [System.UnauthorizedAccessException]::new() }

        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*read-only session probe failed*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1
    }

    It 'rejects absolute probe URLs before any Graph command runs' {
        { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri 'https://example.invalid/' } |
            Should -Throw
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'rejects malformed or control-character probe URIs before any Graph command runs' {
        foreach ($probeUri in '/v1.0/', "/v1.0/me`r`nX-Test: bad", '/v1.0//example.invalid') {
            { Connect-AzdGraphSession -TenantId $tenantId -ExpectedClientId $clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri $probeUri } |
                Should -Throw '*ProbeUri*'
        }
        Should -Invoke Get-MgEnvironment -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }
    It 'rejects an empty tenant before every Graph command' {
        { Connect-AzdGraphSession -TenantId ([guid]::Empty) -ExpectedClientId $script:clientId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' } | Should -Throw '*nonempty tenant*'
        Should -Invoke Get-MgEnvironment -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Get-MgContext -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

}
