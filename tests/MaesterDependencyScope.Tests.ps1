BeforeAll {
  $hooksRoot = Join-Path $PSScriptRoot '../components/powershell/maester-azd-hooks'
}

Describe 'Maester dependencies preserve their caller imports' {
  BeforeEach {
    # Match native setup: the entrypoint owns the approval/helper imports and a
    # separate setup module invokes the real canonical planner in module scope.
    Import-Module (Join-Path $hooksRoot 'Maester-SetupHelpers.psm1') -Force
    Import-Module (Join-Path $hooksRoot 'Maester-ConsentPlan.psm1') -Force
    $helperModule = Get-Module Maester-SetupHelpers
    $caller = New-Module -Name MaesterNestedConsentCaller -ArgumentList $hooksRoot -ScriptBlock {
      param($HooksRoot)
      $script:grantPath = Join-Path $HooksRoot 'Grant-MaesterGraphPermissions.ps1'
      function Get-NestedConsentPlan {
        & $script:grantPath -TenantId '11111111-1111-4111-8111-111111111111' `
          -PrincipalObjectId '22222222-2222-4222-8222-222222222222' -AppRoleValues 'Directory.Read.All'
      }
      function Invoke-NestedConsentApply {
        param([string]$ApprovedPlanHash)
        & $script:grantPath -TenantId '11111111-1111-4111-8111-111111111111' `
          -PrincipalObjectId '22222222-2222-4222-8222-222222222222' -AppRoleValues 'Directory.Read.All' `
          -Apply -ApprovedPlanHash $ApprovedPlanHash
      }
      Export-ModuleMember -Function Get-NestedConsentPlan, Invoke-NestedConsentApply
    }
    Import-Module $caller
    $manifest = Get-Content (Join-Path $hooksRoot 'Maester-GraphPermissions.json') -Raw | ConvertFrom-Json -AsHashtable
    $global:MaesterDependencyScopeState = @{
      PrincipalId = '22222222-2222-4222-8222-222222222222'
      ResourceId = '33333333-3333-4333-8333-333333333333'
      RoleId = $manifest.applicationRoles['Directory.Read.All'].applicationRoleId
      Assignments = [Collections.Generic.List[object]]::new()
      Writes = 0
      AllowWrite = $false
    }
    # Only provider/session boundaries are stubbed. Import-Module, the canonical
    # planner, manifest loading, plan hashing and approval remain real.
    & $helperModule {
      $script:MaesterGraphSession = @{
        TenantId = [guid]'11111111-1111-4111-8111-111111111111'
        ExpectedClientId = [guid]'55555555-5555-4555-8555-555555555555'
        ExpectedAccount = 'admin@example.com'; Environment = 'Global'; ContextScope = 'Process'
        Scopes = @(Get-MaesterSetupScopes); ProbeUri = '/v1.0/organization?$select=id&$top=1'
      }
      function script:Connect-AzdGraphSession { throw 'Unexpected real session provider.' }
      function script:Invoke-MgGraphRequest { throw 'Unexpected real Graph provider.' }
    }
    Mock Connect-AzdGraphSession -ModuleName Maester-SetupHelpers {}
    Mock Invoke-MgGraphRequest -ModuleName Maester-SetupHelpers {
      param($Method, $Uri, $Body)
      $state = $global:MaesterDependencyScopeState
      if ($Method -eq 'POST') {
        $state.Writes++
        if (-not $state.AllowWrite) { throw 'Provider write tripwire.' }
        $assignment = $Body | ConvertFrom-Json
        $assignment | Add-Member -NotePropertyName id -NotePropertyValue 'assignment-scope-test'
        $state.Assignments.Add($assignment)
        return $assignment
      }
      if ($Method -ne 'GET') { throw "Unexpected provider method: $Method" }
      if ($Uri.StartsWith("https://graph.microsoft.com/v1.0/servicePrincipals/$($state.PrincipalId)?")) {
        return [pscustomobject]@{ id = $state.PrincipalId; appId = '44444444-4444-4444-8444-444444444444'; servicePrincipalType = 'ManagedIdentity' }
      }
      if ($Uri.StartsWith('https://graph.microsoft.com/v1.0/servicePrincipals?')) {
        return [pscustomobject]@{ value = @([pscustomobject]@{
          id = $state.ResourceId; appId = '00000003-0000-0000-c000-000000000000'
          appRoles = @([pscustomobject]@{ id = $state.RoleId; value = 'Directory.Read.All'; isEnabled = $true; allowedMemberTypes = @('Application') })
        }) }
      }
      if ($Uri -like "*/servicePrincipals/$($state.PrincipalId)/appRoleAssignments?*") {
        return [pscustomobject]@{ value = @($state.Assignments.ToArray()) }
      }
      throw "Unexpected provider read: $Uri"
    }
  }

  AfterEach {
    Remove-Module MaesterNestedConsentCaller, Maester-InfrastructureOwnership, Maester-SetupHelpers, Maester-ConsentPlan -Force -ErrorAction SilentlyContinue
    Remove-Variable MaesterDependencyScopeState -Scope Global -ErrorAction SilentlyContinue
  }

  It 'retains entrypoint approval exports after repeated real nested dry-run planning' {
    $first = Get-NestedConsentPlan
    $second = Get-NestedConsentPlan
    $second.planHash | Should -BeExactly $first.planHash
    { Assert-MaesterConsentPlanApproval -Plan $second -ApprovedPlanHash $first.planHash } | Should -Not -Throw
    (Get-Command Assert-MaesterConsentPlanApproval).ModuleName | Should -BeExactly 'Maester-ConsentPlan'
    $global:MaesterDependencyScopeState.Writes | Should -Be 0
  }

  It 'keeps the approval boundary and next helper operation available through approved apply' {
    $plan = Get-NestedConsentPlan
    Assert-MaesterConsentPlanApproval -Plan $plan -ApprovedPlanHash $plan.planHash
    $global:MaesterDependencyScopeState.AllowWrite = $true
    $result = Invoke-NestedConsentApply -ApprovedPlanHash $plan.planHash
    $result.planHash | Should -BeExactly $plan.planHash
    $global:MaesterDependencyScopeState.Writes | Should -Be 1
    Assert-MaesterConsentPlanApproval -Plan $result -ApprovedPlanHash $plan.planHash
    # Native setup loads infrastructure ownership after approval, then continues
    # using the helper exports it imported before planning.
    Import-Module (Join-Path $hooksRoot 'Maester-InfrastructureOwnership.psm1')
    ConvertTo-BoolOrDefault -Value 'true' -Default $false | Should -BeTrue
    (Get-Command Invoke-GraphRestRequest).ModuleName | Should -BeExactly 'Maester-SetupHelpers'
    [object]::ReferenceEquals($helperModule, (Get-Module Maester-SetupHelpers)) | Should -BeTrue
    Test-MaesterGraphSession -TenantId '11111111-1111-4111-8111-111111111111' | Should -BeTrue
  }

  It 'denies a stale apply without writes and preserves approval exports for the next operation' {
    $plan = Get-NestedConsentPlan
    { Invoke-NestedConsentApply -ApprovedPlanHash ('0' * 64) } | Should -Throw '*approval of the current plan hash*'
    $global:MaesterDependencyScopeState.Writes | Should -Be 0
    { Assert-MaesterConsentPlanApproval -Plan $plan -ApprovedPlanHash $plan.planHash } | Should -Not -Throw
    $next = Get-NestedConsentPlan
    $next.planHash | Should -BeExactly $plan.planHash
    $global:MaesterDependencyScopeState.Writes | Should -Be 0
  }

  It 'continues rejecting a modified reviewed plan before any provider write' {
    $plan = Get-NestedConsentPlan
    $approvedHash = $plan.planHash
    $plan.details.profile = 'Minimal'
    { Assert-MaesterConsentPlanApproval -Plan $plan -ApprovedPlanHash $approvedHash } | Should -Throw '*modified after it was generated*'
    $global:MaesterDependencyScopeState.Writes | Should -Be 0
  }

  It 'preserves caller helper exports when infrastructure ownership is imported after approval' {
    (Get-Command ConvertTo-BoolOrDefault).ModuleName | Should -BeExactly 'Maester-SetupHelpers'
    Import-Module (Join-Path $hooksRoot 'Maester-InfrastructureOwnership.psm1')
    ConvertTo-BoolOrDefault -Value 'false' -Default $true | Should -BeFalse
    (Get-Command Invoke-GraphRestRequest).ModuleName | Should -BeExactly 'Maester-SetupHelpers'
    [object]::ReferenceEquals($helperModule, (Get-Module Maester-SetupHelpers)) | Should -BeTrue
    Test-MaesterGraphSession -TenantId '11111111-1111-4111-8111-111111111111' | Should -BeTrue
  }
}
