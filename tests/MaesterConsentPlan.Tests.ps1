BeforeAll {
  Import-Module (Join-Path $PSScriptRoot '../components/powershell/maester-azd-hooks/Maester-ConsentPlan.psm1') -Force
}

AfterAll {
  Remove-Module Maester-ConsentPlan -Force -ErrorAction SilentlyContinue
}

Describe 'Versioned Maester consent-plan approval boundary' {
  BeforeEach {
    $planParameters = @{
      TenantId = '11111111-1111-4111-8111-111111111111'
      PrincipalObjectId = '22222222-2222-4222-8222-222222222222'
      Capability = 'GraphApplicationRoles'
      ManifestVersion = '2.3.0-1'
      ManifestSha256 = 'a' * 64
      Desired = @('Directory.Read.All', 'Policy.Read.All')
      Missing = @('Policy.Read.All')
      Details = @{ resourceId = '33333333-3333-4333-8333-333333333333'; profile = 'Full' }
    }
  }

  It 'produces deterministic, normalized, versioned plans without removing existing grants' {
    $first = New-MaesterConsentPlan @planParameters
    $second = New-MaesterConsentPlan @planParameters

    ($first | ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly ($second | ConvertTo-Json -Depth 20 -Compress)
    $first.schemaVersion | Should -BeExactly '1.0'
    $first.planHash | Should -Match '^[a-f0-9]{64}$'
    $first.manifestSha256 | Should -BeExactly ('a' * 64)
    $first.removalPolicy | Should -BeExactly 'PreserveExistingGrants'
    @($first.desired) | Should -Be @('Directory.Read.All', 'Policy.Read.All')
    @($first.missing) | Should -Be @('Policy.Read.All')
    $first.PSObject.Properties.Name | Should -Not -Contain 'remove'
  }

  It 'ignores ordering and duplicates in desired/missing permission sets and detail keys' {
    $planParameters.Missing = @('Policy.Read.All', 'Directory.Read.All')
    $first = New-MaesterConsentPlan @planParameters
    $planParameters.Desired = @('Policy.Read.All', 'Directory.Read.All', 'Policy.Read.All')
    $planParameters.Missing = @('Directory.Read.All', 'Policy.Read.All', 'Directory.Read.All')
    $planParameters.Details = @{ profile = 'Full'; resourceId = '33333333-3333-4333-8333-333333333333' }
    $planParameters.ManifestSha256 = 'A' * 64
    $second = New-MaesterConsentPlan @planParameters

    $second.planHash | Should -BeExactly $first.planHash
    @($second.desired).Count | Should -Be 2
    @($second.missing).Count | Should -Be 2
  }

  It 'canonicalizes nested dictionary and object keys independently of their insertion order' {
    $planParameters.Details = @{
      resource = [ordered]@{
        tenant = 'selected-tenant'
        access = [pscustomobject][ordered]@{
          mode = 'Delegated'
          flags = [ordered]@{ write = $true; read = $true }
        }
      }
      operations = @(
        [pscustomobject][ordered]@{ role = 'Policy.Read.All'; order = 1 }
        [ordered]@{ role = 'Directory.Read.All'; order = 2 }
      )
    }
    $first = New-MaesterConsentPlan @planParameters
    $planParameters.Details = @{
      operations = @(
        [ordered]@{ order = 1; role = 'Policy.Read.All' }
        [pscustomobject][ordered]@{ order = 2; role = 'Directory.Read.All' }
      )
      resource = [pscustomobject][ordered]@{
        access = [ordered]@{
          flags = [pscustomobject][ordered]@{ read = $true; write = $true }
          mode = 'Delegated'
        }
        tenant = 'selected-tenant'
      }
    }
    $second = New-MaesterConsentPlan @planParameters

    $second.planHash | Should -BeExactly $first.planHash
    ($second.details | ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly ($first.details | ConvertTo-Json -Depth 20 -Compress)
    { Assert-MaesterConsentPlanApproval -Plan $second -ApprovedPlanHash $first.planHash } | Should -Not -Throw
  }

  It 'preserves the order of array operations while canonicalizing object properties' {
    $planParameters.Details = @{
      operations = @(
        @{ order = 1; role = 'Policy.Read.All' }
        @{ order = 2; role = 'Directory.Read.All' }
      )
    }
    $first = New-MaesterConsentPlan @planParameters
    $planParameters.Details.operations = @($planParameters.Details.operations[1], $planParameters.Details.operations[0])
    $second = New-MaesterConsentPlan @planParameters

    @($first.details.operations | ForEach-Object role) | Should -Be @('Policy.Read.All', 'Directory.Read.All')
    @($second.details.operations | ForEach-Object role) | Should -Be @('Directory.Read.All', 'Policy.Read.All')
    $second.planHash | Should -Not -BeExactly $first.planHash
    { Assert-MaesterConsentPlanApproval -Plan $second -ApprovedPlanHash $first.planHash } | Should -Throw '*approval of the current plan hash*'
  }

  It 'preserves JSON-roundtripped details, array shapes and approval for <representation>' -ForEach @(
    @{ representation = 'PSCustomObject'; asHashtable = $false }
    @{ representation = 'IDictionary'; asHashtable = $true }
  ) {
    $planParameters.Details = @{
      resource = @{ enabled = $true; owner = [pscustomobject]@{ tenant = 'selected-tenant'; optional = $null } }
      operations = @(@{ role = 'Policy.Read.All'; order = 1 })
      emptyOperations = @()
      nullOperation = @($null)
      nestedOperations = @(@('read', 'write'), @('verify'))
    }
    $plan = New-MaesterConsentPlan @planParameters
    $restored = $plan | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable:$asHashtable

    $restored.planHash | Should -BeExactly $plan.planHash
    ($restored.details.operations -is [array]) | Should -BeTrue
    ($restored.details.emptyOperations -is [array]) | Should -BeTrue
    ($restored.details.nullOperation -is [array]) | Should -BeTrue
    @($restored.details.operations).Count | Should -Be 1
    @($restored.details.emptyOperations).Count | Should -Be 0
    @($restored.details.nullOperation).Count | Should -Be 1
    $restored.details.nullOperation[0] | Should -BeNullOrEmpty
    @($restored.details.nestedOperations).Count | Should -Be 2
    @($restored.details.nestedOperations[0]) | Should -Be @('read', 'write')
    @($restored.details.nestedOperations[1]) | Should -Be @('verify')
    { Assert-MaesterConsentPlanApproval -Plan $restored -ApprovedPlanHash $plan.planHash } | Should -Not -Throw
  }

  It 'invalidates approval when a nested property is altered after <representation> serialization' -ForEach @(
    @{ representation = 'PSCustomObject'; asHashtable = $false }
    @{ representation = 'IDictionary'; asHashtable = $true }
  ) {
    $planParameters.Details = @{
      resource = @{ owner = @{ tenant = 'selected-tenant' } }
      operations = @(@{ role = 'Policy.Read.All'; enabled = $true })
    }
    $plan = New-MaesterConsentPlan @planParameters
    $restored = $plan | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable:$asHashtable
    $restored.details.resource.owner.tenant = 'different-tenant'

    { Assert-MaesterConsentPlanApproval -Plan $restored -ApprovedPlanHash $plan.planHash } | Should -Throw '*modified after it was generated*'
  }

  It 'supports <selection> details without changing the empty-object hash' -ForEach @(
    @{ selection = 'omitted'; omitDetails = $true }
    @{ selection = 'explicit empty'; omitDetails = $false }
  ) {
    $planParameters.Details = @{}
    if ($omitDetails) { $planParameters.Remove('Details') }
    $plan = New-MaesterConsentPlan @planParameters
    $planParameters.Details = @{}
    $explicit = New-MaesterConsentPlan @planParameters

    ($plan.details | ConvertTo-Json -Compress) | Should -BeExactly '{}'
    $plan.planHash | Should -BeExactly $explicit.planHash
    { Assert-MaesterConsentPlanApproval -Plan $plan -ApprovedPlanHash $plan.planHash } | Should -Not -Throw
  }

  It 'preserves nested empty objects and empty arrays as distinct consent details' {
    $planParameters.Details = @{ nested = @{} }
    $objectPlan = New-MaesterConsentPlan @planParameters
    $planParameters.Details = @{ nested = @() }
    $arrayPlan = New-MaesterConsentPlan @planParameters

    ($objectPlan.details | ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly '{"nested":{}}'
    ($arrayPlan.details | ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly '{"nested":[]}'
    $objectPlan.planHash | Should -Not -BeExactly $arrayPlan.planHash
  }

  It 'binds deeply nested details beyond the old JSON depth limit into the approval hash' {
    $leaf = @{ value = 'original-permission-sensitive-value' }
    $deep = $leaf
    for ($depth = 0; $depth -lt 23; $depth++) { $deep = @{ child = $deep } }
    $planParameters.Details = $deep
    $first = New-MaesterConsentPlan @planParameters
    $leaf.value = 'changed-permission-sensitive-value'
    $second = New-MaesterConsentPlan @planParameters

    $second.planHash | Should -Not -BeExactly $first.planHash
    { Assert-MaesterConsentPlanApproval -Plan $second -ApprovedPlanHash $first.planHash } | Should -Throw '*approval of the current plan hash*'
    { Assert-MaesterConsentPlanApproval -Plan $second -ApprovedPlanHash $second.planHash } | Should -Not -Throw
  }

  It 'refuses details too deep to serialize instead of hashing a silently truncated approval target' {
    $deep = @{ value = 'permission-sensitive-leaf' }
    for ($depth = 0; $depth -lt 33; $depth++) { $deep = @{ child = $deep } }
    $planParameters.Details = $deep
    { New-MaesterConsentPlan @planParameters } | Should -Throw
  }

  It 'does not permit a missing permission outside the reviewed desired set' {
    $planParameters.Missing = @('Application.ReadWrite.All')
    { New-MaesterConsentPlan @planParameters } | Should -Throw '*unrequested permission*'
  }

  It 'rejects an empty <field> identity' -ForEach @(
    @{ field = 'TenantId' }
    @{ field = 'PrincipalObjectId' }
  ) {
    $planParameters[$field] = [guid]::Empty
    { New-MaesterConsentPlan @planParameters } | Should -Throw '*non-empty tenant and principal*'
  }

  It 'rejects malformed manifest digest <digest>' -ForEach @(
    @{ digest = '' }
    @{ digest = 'not-a-digest' }
    @{ digest = ('g' * 64) }
    @{ digest = ('a' * 63) }
  ) {
    $planParameters.ManifestSha256 = $digest
    { New-MaesterConsentPlan @planParameters } | Should -Throw
  }

  It 'requires the exact current hash before applying a nonempty permission expansion' {
    $plan = New-MaesterConsentPlan @planParameters
    { Assert-MaesterConsentPlanApproval -Plan $plan } | Should -Throw '*approval of the current plan hash*'
    { Assert-MaesterConsentPlanApproval -Plan $plan -ApprovedPlanHash ('b' * 64) } | Should -Throw '*approval of the current plan hash*'
    { Assert-MaesterConsentPlanApproval -Plan $plan -ApprovedPlanHash $plan.planHash.ToUpperInvariant() } | Should -Throw '*approval of the current plan hash*'
    { Assert-MaesterConsentPlanApproval -Plan $plan -ApprovedPlanHash $plan.planHash } | Should -Not -Throw
  }

  It 'invalidates earlier approval when the <field> changes' -ForEach @(
    @{ field = 'TenantId'; value = '44444444-4444-4444-8444-444444444444' }
    @{ field = 'PrincipalObjectId'; value = '44444444-4444-4444-8444-444444444444' }
    @{ field = 'Capability'; value = 'WebAppDelegatedConsent' }
    @{ field = 'ManifestVersion'; value = '2.3.0-2' }
    @{ field = 'ManifestSha256'; value = ('b' * 64) }
    @{ field = 'Desired'; value = @('Directory.Read.All', 'Policy.Read.All', 'Reports.Read.All') }
    @{ field = 'Missing'; value = @('Directory.Read.All', 'Policy.Read.All') }
    @{ field = 'Details'; value = @{ resourceId = '44444444-4444-4444-8444-444444444444'; profile = 'Full' } }
  ) {
    $approved = New-MaesterConsentPlan @planParameters
    $planParameters[$field] = $value
    $current = New-MaesterConsentPlan @planParameters

    $current.planHash | Should -Not -BeExactly $approved.planHash
    { Assert-MaesterConsentPlanApproval -Plan $current -ApprovedPlanHash $approved.planHash } | Should -Throw '*approval of the current plan hash*'
    { Assert-MaesterConsentPlanApproval -Plan $current -ApprovedPlanHash $current.planHash } | Should -Not -Throw
  }

  It 'allows a no-op with <selection> without prompting or approval' -ForEach @(
    @{ selection = 'already granted desired permissions'; desired = @('Directory.Read.All', 'Policy.Read.All') }
    @{ selection = 'no selected permissions'; desired = @() }
  ) {
    $planParameters.Desired = $desired
    $planParameters.Missing = @()
    $plan = New-MaesterConsentPlan @planParameters
    Mock Read-Host -ModuleName Maester-ConsentPlan { throw 'No-op must not prompt.' }
    Mock Write-Host -ModuleName Maester-ConsentPlan {}

    { Assert-MaesterConsentPlanApproval -Plan $plan } | Should -Not -Throw
    Confirm-MaesterConsentPlan -Plan $plan | Should -BeExactly $plan.planHash
    Should -Invoke Read-Host -ModuleName Maester-ConsentPlan -Times 0 -Exactly
  }

  It 'fails closed for permission expansion in a <environmentName> noninteractive run' -ForEach @(
    @{ environmentName = 'CI' }
    @{ environmentName = 'AZD_NON_INTERACTIVE' }
  ) {
    $savedValue = [Environment]::GetEnvironmentVariable($environmentName)
    try {
      [Environment]::SetEnvironmentVariable($environmentName, 'true')
      $plan = New-MaesterConsentPlan @planParameters
      Mock Read-Host -ModuleName Maester-ConsentPlan { throw 'Noninteractive execution must not prompt.' }
      Mock Write-Host -ModuleName Maester-ConsentPlan {}
      { Confirm-MaesterConsentPlan -Plan $plan } | Should -Throw '*explicit approved plan hash*'
      Should -Invoke Read-Host -ModuleName Maester-ConsentPlan -Times 0 -Exactly
    }
    finally {
      [Environment]::SetEnvironmentVariable($environmentName, $savedValue)
    }
  }

  It 'rejects a mutated <field> even when its retained hash was once approved' -ForEach @(
    @{ field = 'tenantId'; value = '44444444-4444-4444-8444-444444444444' }
    @{ field = 'principalObjectId'; value = '44444444-4444-4444-8444-444444444444' }
    @{ field = 'manifestVersion'; value = '2.3.0-2' }
    @{ field = 'missing'; value = @('Directory.Read.All', 'Policy.Read.All') }
    @{ field = 'missing'; value = @() }
    @{ field = 'schemaVersion'; value = '2.0' }
    @{ field = 'details'; value = @{ resourceId = '44444444-4444-4444-8444-444444444444' } }
    @{ field = 'removalPolicy'; value = 'RemoveUnselectedGrants' }
  ) {
    $plan = New-MaesterConsentPlan @planParameters
    $approvedHash = $plan.planHash
    $plan.$field = $value
    { Assert-MaesterConsentPlanApproval -Plan $plan -ApprovedPlanHash $approvedHash } | Should -Throw
  }
  It 'preserves pipeline-wrapped string values instead of interpreting them as object properties' {
    $planParameters.Details = @{ scopes = @('openid', 'profile', 'email', 'User.Read' | Where-Object { $_ -notin @('openid', 'User.Read') }) }
    $plan = New-MaesterConsentPlan @planParameters
    @($plan.details.scopes) | Should -Be @('profile', 'email')
    ($plan | ConvertTo-Json -Depth 100 -Compress) | Should -Match '"scopes":\["profile","email"\]'
    { Assert-MaesterConsentPlanApproval -Plan $plan -ApprovedPlanHash $plan.planHash } | Should -Not -Throw
  }

  It 'rejects a concealed permission delta before confirmation display or no-op acceptance' {
    $plan = New-MaesterConsentPlan @planParameters
    $originalHash = $plan.planHash
    $plan.desired = @()
    $plan.missing = @()
    $plan.details.profile = 'Minimal'
    Mock Write-Host {} -ModuleName Maester-ConsentPlan
    Mock Read-Host { throw 'A mutated plan must not reach the approval prompt.' } -ModuleName Maester-ConsentPlan
    { Confirm-MaesterConsentPlan -Plan $plan } | Should -Throw '*modified after it was generated*'
    $plan.planHash | Should -Be $originalHash
    Should -Invoke Write-Host -ModuleName Maester-ConsentPlan -Times 0
    Should -Invoke Read-Host -ModuleName Maester-ConsentPlan -Times 0
  }

  It 'preserves empty JSON objects in nested provider configuration' {
    $planParameters.Details = @{ authsettings = @{ login = @{ routes = ('{}' | ConvertFrom-Json) } } }
    $plan = New-MaesterConsentPlan @planParameters
    ($plan | ConvertTo-Json -Depth 100 -Compress) | Should -Match '"routes":\{\}'
    { Assert-MaesterConsentPlanApproval -Plan $plan -ApprovedPlanHash $plan.planHash } | Should -Not -Throw
  }

}
