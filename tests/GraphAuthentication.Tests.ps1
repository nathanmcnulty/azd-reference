BeforeAll {
    function global:Get-MgEnvironment {}
    function global:Get-MgContext {}
    function global:Connect-MgGraph {
        param($TenantId, $Environment, $Scopes, $ContextScope, $ClientTimeout, $NoWelcome, $ErrorAction)
    }
    function global:Invoke-MgGraphRequest {
        param($Method, $Uri, $OutputType, $ErrorAction)
    }

    $modulePath = Join-Path $PSScriptRoot '../components/powershell/graph-delegated-authentication/Azd.GraphAuthentication.psd1'
    Import-Module $modulePath -Force
    $script:tenantId = [guid]'11111111-1111-4111-8111-111111111111'
    $script:scopes = @('Policy.Read.All', 'RoleManagement.Read.Directory')

    function New-TestGraphContext {
        param(
            [string] $TenantId = $script:tenantId.Guid,
            [string] $Environment = 'Global',
            [string] $Account = 'admin@example.com',
            [string] $AuthType = 'Delegated',
            [string] $ContextScope = 'CurrentUser',
            [string[]] $Scopes = $script:scopes
        )
        [pscustomobject]@{
            TenantId = $TenantId
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

    It 'reuses an exact usable context without connecting' {
        $result = Connect-AzdGraphSession `
            -TenantId $tenantId `
            -Scopes $scopes `
            -ExpectedAccount 'ADMIN@example.com' `
            -ProbeUri '/v1.0/roleManagement/directory/roleDefinitions?$top=1'

        $result.contextReused | Should -BeTrue
        $result.connectInvoked | Should -BeFalse
        $result.PSObject.Properties.Name | Should -Not -Contain 'accessToken'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 1
    }

    It 'does not connect when a matching context fails its probe noninteractively' {
        $script:probeException = New-TestGraphHttpException -StatusCode 401
        Mock Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication { throw $script:probeException }

        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' } |
            Should -Throw '*not usable in this process*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'does not connect when no context is available noninteractively' {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication { $null }

        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' } |
            Should -Throw '*required for noninteractive execution*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'rejects a blank expected account before any Graph command runs' {
        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount '  ' -ProbeUri '/v1.0/me' } |
            Should -Throw '*ExpectedAccount*'
        Should -Invoke Get-MgEnvironment -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Get-MgContext -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'refuses a mismatched inherited account without replacement authorization' {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            New-TestGraphContext -Account 'other@example.com'
        }

        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*context account does not match*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'rejects each incompatible delegated context property' -ForEach @(
        @{ Name = 'environment'; Context = { New-TestGraphContext -Environment 'USGov' } },
        @{ Name = 'authentication type'; Context = { New-TestGraphContext -AuthType 'AppOnly' } },
        @{ Name = 'context scope'; Context = { New-TestGraphContext -ContextScope 'Process' } }
    ) {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication { & $Context }

        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' } |
            Should -Throw
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'refuses to replace a mismatched inherited context by default' {
        Mock Get-MgContext -ModuleName Azd.GraphAuthentication {
            New-TestGraphContext -TenantId '22222222-2222-4222-8222-222222222222'
        }

        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
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
            -Scopes @('RoleManagement.Read.Directory', 'Policy.Read.All', 'Policy.Read.All') `
            -Environment Global `
            -ExpectedAccount 'admin@example.com' `
            -ProbeUri '/v1.0/roleManagement/directory/roleDefinitions?$top=1' `
            -AllowInteractive `
            -AllowContextReplacement

        $result.connectInvoked | Should -BeTrue
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1 -ParameterFilter {
            $TenantId -eq $script:tenantId.Guid -and
            $Environment -eq 'Global' -and
            $ContextScope -eq 'CurrentUser' -and
            $NoWelcome -eq $true -and
            (@($Scopes | Sort-Object) -join ',') -eq 'Policy.Read.All,RoleManagement.Read.Directory'
        }
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

        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
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

        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
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

        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*Authentication was not started*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'treats an explicit 403 as authorization even when the exception type says unauthorized' {
        $script:probeException = New-TestGraphHttpException -StatusCode 403 -UnauthorizedType
        Mock Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication { throw $script:probeException }

        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
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

        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri '/v1.0/me' -AllowInteractive } |
            Should -Throw '*read-only session probe failed*'
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 1
    }

    It 'rejects absolute probe URLs before any Graph command runs' {
        { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri 'https://example.invalid/' } |
            Should -Throw
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }

    It 'rejects malformed or control-character probe URIs before any Graph command runs' {
        foreach ($probeUri in '/v1.0/', "/v1.0/me`r`nX-Test: bad", '/v1.0//example.invalid') {
            { Connect-AzdGraphSession -TenantId $tenantId -Scopes $scopes -ExpectedAccount 'admin@example.com' -ProbeUri $probeUri } |
                Should -Throw '*ProbeUri*'
        }
        Should -Invoke Get-MgEnvironment -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Connect-MgGraph -ModuleName Azd.GraphAuthentication -Times 0
        Should -Invoke Invoke-MgGraphRequest -ModuleName Azd.GraphAuthentication -Times 0
    }
}
