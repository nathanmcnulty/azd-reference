BeforeAll {
  $script:hookRoot=Join-Path (Split-Path $PSScriptRoot -Parent) 'components/powershell/maester-azd-hooks'
  Import-Module (Join-Path $script:hookRoot 'Maester-OwnershipJournal.psm1')
  Import-Module (Join-Path $script:hookRoot 'Maester-PreDownCleanup.psm1') -Force
  function New-CleanupFixture {
    param([string]$Root, [switch]$Pending)
    $binding=@{environmentName='cleanup-test';solutionName='function-app';tenantId='11111111-1111-4111-8111-111111111111';subscriptionId='22222222-2222-4222-8222-222222222222';setupClientId='33333333-3333-4333-8333-333333333333';resourceGroupId='/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/cleanup-test'}
    [IO.Directory]::CreateDirectory($Root)|Out-Null
    $session=Open-MaesterOwnershipJournal -ProjectRoot $Root -Binding $binding
    try {
      $record=Start-MaesterOwnedOperation -Session $session -Key 'runtime/role' -Kind DirectoryRoleAssignment -PlanHash ('a'*64) -Ownership Created -Expected @{principalId='44444444-4444-4444-8444-444444444444';roleDefinitionId='55555555-5555-4555-8555-555555555555';directoryScopeId='/'}
      if (-not $Pending) { $record=Complete-MaesterOwnedOperation -Session $session -OperationId $record.operationId -ExactIds @{assignmentId='assignment-id'} }
      return @{Root=$Root;Binding=$binding;Record=$record}
    } finally { $session.Dispose() }
  }
}
AfterAll { Remove-Module Maester-PreDownCleanup,Maester-OwnershipJournal -Force -ErrorAction SilentlyContinue; Remove-Variable CleanupFixtureState -Scope Global -ErrorAction SilentlyContinue }

Describe 'Exact ownership cleanup lifecycle' {
  BeforeEach {
    $fixture=New-CleanupFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
    $global:CleanupFixtureState=@{Present=$true;ReadFailure=$false;DeleteFailure=$false;DeleteCalls=0;GetCalls=0;ArmPresent=$false;ArmFailure=$false;ChangedTuple=$false;MissingReadsAfterDelete=$false;SessionCheck=$false}
    Mock Get-AzCliSubscriptionContext -ModuleName Maester-PreDownCleanup { @{id=$SubscriptionId;tenantId=$TenantId;state='Enabled'} }
    Mock Invoke-MaesterCleanupArmRequest -ModuleName Maester-PreDownCleanup {
      if ($global:CleanupFixtureState.ArmFailure) { throw 'ARM HTTP 403' }
      @{StatusCode=if($global:CleanupFixtureState.ArmPresent){200}else{404};Value=@{id=$ResourceId}}
    }
    Mock Initialize-MaesterCleanupGraph -ModuleName Maester-PreDownCleanup { @{clientIds=@('33333333-3333-4333-8333-333333333333');objectIds=@()} }
    Mock Initialize-MaesterCleanupExchange -ModuleName Maester-PreDownCleanup {}
    Mock Start-Sleep -ModuleName Maester-PreDownCleanup {}
    Mock Test-MaesterCleanupCanPrompt -ModuleName Maester-PreDownCleanup { $true }
    Mock Read-Host -ModuleName Maester-PreDownCleanup { '' }
    Mock Invoke-MaesterCleanupGraphRequest -ModuleName Maester-PreDownCleanup {
      param($Binding,$Method,$Path)
      if ($Method -eq 'DELETE') {
        $global:CleanupFixtureState.DeleteCalls++
        if ($global:CleanupFixtureState.DeleteFailure) { throw 'typed provider failure before confirmed deletion' }
        if (-not $global:CleanupFixtureState.MissingReadsAfterDelete) { $global:CleanupFixtureState.Present=$false }
        return @{StatusCode=204;Value=$null}
      }
      $global:CleanupFixtureState.GetCalls++
      if ($global:CleanupFixtureState.ReadFailure) { throw 'Graph HTTP 403' }
      if (-not $global:CleanupFixtureState.Present) { return @{StatusCode=404;Value=$null} }
      @{StatusCode=200;Value=@{id='assignment-id';principalId=if($global:CleanupFixtureState.ChangedTuple){'99999999-9999-4999-8999-999999999999'}else{'44444444-4444-4444-8444-444444444444'};roleDefinitionId='55555555-5555-4555-8555-555555555555';directoryScopeId='/'}}
    }
  }
  It 'has zero destructive transports for preview, omitted approval and default-No cancellation' {
    $plan=Get-MaesterOwnedCleanupPlan -ProjectRoot $fixture.Root -Binding $fixture.Binding
    $plan.Entries.Count | Should -Be 1
    { Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $fixture.Root -Binding $fixture.Binding } | Should -Throw '*Explicit cleanup approval is required*'
    { Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -InteractiveConsent } | Should -Throw '*not approved*'
    $global:CleanupFixtureState.DeleteCalls | Should -Be 0
    $session=Open-MaesterOwnershipJournal -ProjectRoot $fixture.Root -Binding $fixture.Binding -RequireExisting
    try { (Get-MaesterOwnershipJournal $session).records[0].state | Should -BeExactly applied } finally { $session.Dispose() }
  }
  It 'rejects a stale exact approval hash before any DELETE' {
    { Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -ApprovedPlanHash ('0'*64) } | Should -Throw '*hash is stale*'
    $global:CleanupFixtureState.DeleteCalls | Should -Be 0
  }
  It 'revalidates the exact tuple, deletes one ID, verifies absence, checkpoints and is idempotent' {
    $plan=Get-MaesterOwnedCleanupPlan -ProjectRoot $fixture.Root -Binding $fixture.Binding
    $result=Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -ApprovedPlanHash $plan.PlanHash
    $result.Completed | Should -BeTrue
    $global:CleanupFixtureState.DeleteCalls | Should -Be 1
    $session=Open-MaesterOwnershipJournal -ProjectRoot $fixture.Root -Binding $fixture.Binding -RequireExisting
    try { (Get-MaesterOwnershipJournal $session).records[0].state | Should -BeExactly deleted } finally { $session.Dispose() }
    (Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $fixture.Root -Binding $fixture.Binding).Completed | Should -BeTrue
    $global:CleanupFixtureState.DeleteCalls | Should -Be 1
  }
  It 'retains deleting state when the DELETE outcome is unknown and safely retries with a fresh plan' {
    $plan=Get-MaesterOwnedCleanupPlan -ProjectRoot $fixture.Root -Binding $fixture.Binding
    $global:CleanupFixtureState.DeleteFailure=$true
    { Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -ApprovedPlanHash $plan.PlanHash } | Should -Throw '*Azure has been removed; external cleanup is incomplete*'
    $session=Open-MaesterOwnershipJournal -ProjectRoot $fixture.Root -Binding $fixture.Binding -RequireExisting
    try { (Get-MaesterOwnershipJournal $session).records[0].state | Should -BeExactly deleting } finally { $session.Dispose() }
    $global:CleanupFixtureState.DeleteFailure=$false
    $plan=Get-MaesterOwnedCleanupPlan -ProjectRoot $fixture.Root -Binding $fixture.Binding
    (Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -ApprovedPlanHash $plan.PlanHash).Completed | Should -BeTrue
  }
  It 'never converts 403, timeout or current Azure existence into absence' {
    $global:CleanupFixtureState.ReadFailure=$true
    { Get-MaesterOwnedCleanupPlan -ProjectRoot $fixture.Root -Binding $fixture.Binding } | Should -Throw '*Graph HTTP 403*'
    $global:CleanupFixtureState.ReadFailure=$false;$global:CleanupFixtureState.ArmPresent=$true
    { Get-MaesterOwnedCleanupPlan -ProjectRoot $fixture.Root -Binding $fixture.Binding } | Should -Throw '*still exists*'
    $global:CleanupFixtureState.ArmPresent=$false;$global:CleanupFixtureState.ArmFailure=$true
    { Get-MaesterOwnedCleanupPlan -ProjectRoot $fixture.Root -Binding $fixture.Binding } | Should -Throw '*ARM HTTP 403*'
    $global:CleanupFixtureState.DeleteCalls | Should -Be 0
  }
  It 'blocks pending writes before ARM, Graph or Exchange transports' {
    $pending=New-CleanupFixture -Root (Join-Path $TestDrive 'pending') -Pending
    { Get-MaesterOwnedCleanupPlan -ProjectRoot $pending.Root -Binding $pending.Binding } | Should -Throw '*pending operation*'
    Should -Invoke Invoke-MaesterCleanupArmRequest -ModuleName Maester-PreDownCleanup -Times 0 -Exactly
    $global:CleanupFixtureState.GetCalls | Should -Be 0
  }
  It 'fails closed on a missing legacy journal' {
    [IO.Directory]::CreateDirectory((Join-Path $TestDrive 'legacy'))|Out-Null
    { Invoke-MaesterOwnedCleanupPostDown -ProjectRoot (Join-Path $TestDrive 'legacy') -Binding $fixture.Binding -InteractiveConsent } | Should -Throw '*journal is missing*'
    $global:CleanupFixtureState.DeleteCalls | Should -Be 0
  }
  It 'preserves a changed exact target tuple after a previously correct preview' {
    $plan=Get-MaesterOwnedCleanupPlan -ProjectRoot $fixture.Root -Binding $fixture.Binding
    $global:CleanupFixtureState.ChangedTuple=$true
    { Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -ApprovedPlanHash $plan.PlanHash } | Should -Throw '*no longer matches*'
    $global:CleanupFixtureState.DeleteCalls | Should -Be 0
  }
  It 'requires bounded confirmed absence and retains retry evidence when readback remains present' {
    $plan=Get-MaesterOwnedCleanupPlan -ProjectRoot $fixture.Root -Binding $fixture.Binding
    $global:CleanupFixtureState.MissingReadsAfterDelete=$true
    { Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -ApprovedPlanHash $plan.PlanHash } | Should -Throw '*bounded verification window*'
    $global:CleanupFixtureState.DeleteCalls | Should -Be 1
    $session=Open-MaesterOwnershipJournal -ProjectRoot $fixture.Root -Binding $fixture.Binding -RequireExisting
    try { (Get-MaesterOwnershipJournal $session).records[0].state | Should -BeExactly deleting } finally { $session.Dispose() }
  }
  It 'resolves retained optional binding only with the explicit selected anchors' {
    $resolved=Resolve-MaesterCleanupBinding -ProjectRoot $fixture.Root -EnvironmentName cleanup-test -SolutionName function-app -TenantId $fixture.Binding.tenantId -SubscriptionId $fixture.Binding.subscriptionId
    $resolved.setupClientId | Should -BeExactly $fixture.Binding.setupClientId
    { Resolve-MaesterCleanupBinding -ProjectRoot $fixture.Root -EnvironmentName cleanup-test -SolutionName function-app -TenantId 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' -SubscriptionId $fixture.Binding.subscriptionId } | Should -Throw '*selected tenantId binding*'
  }
}

Describe 'Cleanup finite provider safety checks' {
  It 'uses numeric provider 404 only and never a message substring' {
    InModuleScope Maester-PreDownCleanup {
      $errorRecord=[Management.Automation.ErrorRecord]::new([Exception]::new('404 Not Found'), 'fake', [Management.Automation.ErrorCategory]::NotSpecified, $null)
      Get-MaesterCleanupHttpStatus $errorRecord | Should -Be 0
    }
  }
  It 'protects both the original and currently authenticated setup client and object IDs' {
    InModuleScope Maester-PreDownCleanup {
      $protection=@{clientIds=@('original','current');objectIds=@('current-sp','original-app')}
      foreach ($target in @('original','current','current-sp','original-app')) {
        $record=@{operationId='operation';expected=@{principalId=$target};exactIds=@{}}
        { Assert-MaesterCleanupProtected $record $protection } | Should -Throw '*retained setup identity*'
      }
    }
  }
  It 'blocks unsupported shared mutations and forged owned-parent relationships' {
    InModuleScope Maester-PreDownCleanup {
      $mutation=@{operationId='mutation';kind='ApplicationConfiguration';state='applied';ownership='Mutation';expected=@{applicationObjectId='shared'};coveredByOperationId=$null}
      { Assert-MaesterCleanupJournal @{records=@($mutation)} } | Should -Throw '*shared mutation*'
      $parent=@{operationId='parent';kind='EntraApplication';state='applied';ownership='Created';exactIds=@{applicationObjectId='owned'}}
      $mutation.coveredByOperationId='parent'
      { Assert-MaesterCleanupJournal @{records=@($parent,$mutation)} } | Should -Throw '*does not identify*'
    }
  }
  It 'rejects unrecorded children instead of deleting their owned parent' {
    InModuleScope Maester-PreDownCleanup {
      { Assert-MaesterCleanupKnownChildren @(@{id='unrecorded'}) @('owned') 'credential' } | Should -Throw '*unrecorded credential*'
    }
  }
  It 'rejects config-only legacy APIs before any transport' {
    { Invoke-MaesterStandardPreDownCleanup -ManagedIdentityPrincipalEnvName FUNCTION_APP_MI_PRINCIPAL_ID } | Should -Throw '*config-only cleanup is unsafe*'
    { Invoke-MaesterAzureDevOpsPreDownCleanup } | Should -Throw '*config-only cleanup is unsafe*'
  }
}

Describe 'Separate exact infrastructure unlock approval' {
  BeforeAll { Import-Module (Join-Path $script:hookRoot 'Maester-InfrastructureOwnership.psm1') }
  BeforeEach {
    $fixture=New-CleanupFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
    $global:CleanupFixtureState=@{Unlocks=0;Deletes=0;Locked=$true}
    Mock Import-Module -ModuleName Maester-PreDownCleanup {}
    Mock Assert-MaesterCleanupArmAuthority -ModuleName Maester-PreDownCleanup {}
    Mock Test-MaesterInfrastructureOwnership -ModuleName Maester-PreDownCleanup {
      [pscustomobject]@{SafeToDelete=(-not $global:CleanupFixtureState.Locked);SafeToUnlock=$true;PlanHash=('c'*64);PresentOwnedLockIds=@('/exact/owned/lock');OwnedResourceIds=@('/exact/runtime');BlockingReason='';DeletionWarning='Owned child resources and data are also removed.'}
    }
    Mock Unlock-MaesterInfrastructureLocks -ModuleName Maester-PreDownCleanup { $global:CleanupFixtureState.Unlocks++;$global:CleanupFixtureState.Locked=$false }
    Mock Invoke-MaesterCleanupDelete -ModuleName Maester-PreDownCleanup { $global:CleanupFixtureState.Deletes++ }
    Mock Initialize-MaesterCleanupGraph -ModuleName Maester-PreDownCleanup { throw 'Pre-down must not establish a Graph session.' }
    Mock Test-MaesterCleanupCanPrompt -ModuleName Maester-PreDownCleanup { $true }
    Mock Read-Host -ModuleName Maester-PreDownCleanup { '' }
  }
  It 'does not unlock after omitted approval, default-No cancellation or a stale hash' {
    { Test-MaesterOwnedCleanupPreDown -ProjectRoot $fixture.Root -Binding $fixture.Binding } | Should -Throw '*Explicit cleanup approval*'
    { Test-MaesterOwnedCleanupPreDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -InteractiveConsent } | Should -Throw '*not approved*'
    { Test-MaesterOwnedCleanupPreDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -ApprovedUnlockPlanHash ('0'*64) } | Should -Throw '*hash is stale*'
    $global:CleanupFixtureState.Unlocks | Should -Be 0
    $global:CleanupFixtureState.Deletes | Should -Be 0
  }
  It 'unlocks only after exact approval and keeps all external authorization applied' {
    $result=Test-MaesterOwnedCleanupPreDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -ApprovedUnlockPlanHash ('c'*64)
    $result.ExternalDeletionAttempted | Should -BeFalse
    $global:CleanupFixtureState.Unlocks | Should -Be 1
    $global:CleanupFixtureState.Deletes | Should -Be 0
    Should -Invoke Initialize-MaesterCleanupGraph -ModuleName Maester-PreDownCleanup -Times 0 -Exactly
    $session=Open-MaesterOwnershipJournal -ProjectRoot $fixture.Root -Binding $fixture.Binding -RequireExisting
    try { (Get-MaesterOwnershipJournal $session).records[0].state | Should -BeExactly applied } finally { $session.Dispose() }
  }
  It 'returns an exact lock plan without prompting or unlocking in PlanOnly mode' {
    $result=Test-MaesterOwnedCleanupPreDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -PlanOnly
    $result.PlanOnly | Should -BeTrue
    $result.SafeToDelete | Should -BeFalse
    $result.UnlockPlanHash | Should -BeExactly ('c'*64)
    $result.PresentOwnedLockIds | Should -Be @('/exact/owned/lock')
    $global:CleanupFixtureState.Unlocks | Should -Be 0
    Should -Invoke Read-Host -ModuleName Maester-PreDownCleanup -Times 0 -Exactly
  }
  It 'blocks foreign infrastructure and never offers to remove its lock' {
    Mock Test-MaesterInfrastructureOwnership -ModuleName Maester-PreDownCleanup { [pscustomobject]@{SafeToDelete=$false;SafeToUnlock=$false;BlockingReason='foreign resource or lock'} }
    { Test-MaesterOwnedCleanupPreDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -ApprovedUnlockPlanHash ('c'*64) } | Should -Throw '*foreign resource or lock*'
    $global:CleanupFixtureState.Unlocks | Should -Be 0
  }
}

Describe 'Exact Graph parent and child handler inventory' {
  BeforeEach {
    $global:CleanupFixtureState=@{ForeignCredential=$false;ForeignOwner=$false;ForeignFic=$false;ForeignPrincipal=$false;Owner='';ConfigurationChanged=$false;AppAbsent=$false}
    Mock Invoke-MaesterCleanupGraphRequest -ModuleName Maester-PreDownCleanup {
      param($Binding,$Method,$Path)
      if ($Path -match '^/v1\.0/applications/app-object(?:\?|$)') {
        if ($global:CleanupFixtureState.AppAbsent) { return @{StatusCode=404;Value=$null} }
        return @{StatusCode=200;Value=@{id='app-object';appId='app-client';displayName='Owned';passwordCredentials=@(if($global:CleanupFixtureState.ForeignCredential){@{keyId='foreign'}});keyCredentials=@();web=@{redirectUris=@('https://owned.example/return');implicitGrantSettings=@{enableIdTokenIssuance=$true;enableAccessTokenIssuance=$false}};identifierUris=@();signInAudience='AzureADMyOrg';groupMembershipClaims=if($global:CleanupFixtureState.ConfigurationChanged){'All'}else{'SecurityGroup'}}}
      }
      if ($Path -like '*/owners?*') { return @{StatusCode=200;Value=@{value=@(if($global:CleanupFixtureState.ForeignOwner){@{id='foreign-owner'}}elseif($global:CleanupFixtureState.Owner){@{id=$global:CleanupFixtureState.Owner}})}} }
      if ($Path -like '*/federatedIdentityCredentials') { return @{StatusCode=200;Value=@{value=@(if($global:CleanupFixtureState.ForeignFic){@{id='foreign-fic'}})}} }
      if ($Path -like '/v1.0/servicePrincipals?*') { return @{StatusCode=200;Value=@{value=@(if($global:CleanupFixtureState.ForeignPrincipal){@{id='foreign-sp'}})}} }
      throw "Unexpected Graph fixture path $Path"
    }
  }
  It 'accepts only the exact approved implicit creator owner and rejects later owners/credentials/FICs/SPs' {
    InModuleScope Maester-PreDownCleanup {
      $app=@{operationId='app-operation';kind='EntraApplication';ownership='Created';state='applied';expected=@{purpose='EasyAuth';displayName='Owned';creatorPrincipalId='approved-creator'};exactIds=@{applicationObjectId='app-object';appId='app-client'};after=@{redirectUris=@('https://owned.example/return');identifierUris=@();groupMembershipClaims='SecurityGroup';enableIdTokenIssuance=$true;enableAccessTokenIssuance=$false;signInAudience='AzureADMyOrg'}}
      $journal=@{binding=@{tenantId='tenant'};records=@($app)};$protected=@{clientIds=@('setup');objectIds=@()}
      $global:CleanupFixtureState.Owner='approved-creator'
      (Get-MaesterCleanupTarget $app $journal $protected).action | Should -BeExactly Delete
      $global:CleanupFixtureState.ForeignOwner=$true
      { Get-MaesterCleanupTarget $app $journal $protected } | Should -Throw '*owners not covered*'
      $global:CleanupFixtureState.ForeignOwner=$false;$global:CleanupFixtureState.ForeignCredential=$true
      { Get-MaesterCleanupTarget $app $journal $protected } | Should -Throw '*unrecorded passwordCredentials*'
      $global:CleanupFixtureState.ForeignCredential=$false;$global:CleanupFixtureState.ForeignFic=$true
      { Get-MaesterCleanupTarget $app $journal $protected } | Should -Throw '*unrecorded federated credential*'
      $global:CleanupFixtureState.ForeignFic=$false;$global:CleanupFixtureState.ForeignPrincipal=$true
      { Get-MaesterCleanupTarget $app $journal $protected } | Should -Throw '*unrecorded service principal*'
    }
  }
  It 'blocks parent deletion after a recorded configuration was changed concurrently' {
    InModuleScope Maester-PreDownCleanup {
      $app=@{operationId='app-operation';kind='EntraApplication';ownership='Created';state='applied';expected=@{purpose='EasyAuth';displayName='Owned'};exactIds=@{applicationObjectId='app-object';appId='app-client'};after=@{redirectUris=@('https://owned.example/return');identifierUris=@();groupMembershipClaims='SecurityGroup';enableIdTokenIssuance=$true;enableAccessTokenIssuance=$false;signInAudience='AzureADMyOrg'}}
      $app.after.groupMembershipClaims='None'
      $config=@{operationId='config-operation';kind='ApplicationConfiguration';ownership='Mutation';state='applied';expected=@{applicationObjectId='app-object';appId='app-client'};exactIds=@{applicationObjectId='app-object'};after=@{groupMembershipClaims='SecurityGroup'};coveredByOperationId='app-operation'}
      $journal=@{binding=@{tenantId='tenant'};records=@($app,$config)};$protected=@{clientIds=@('setup');objectIds=@()}
      (Get-MaesterCleanupTarget $app $journal $protected).action | Should -BeExactly Delete
      $global:CleanupFixtureState.ConfigurationChanged=$true
      { Get-MaesterCleanupTarget $app $journal $protected } | Should -Throw '*application configuration groupMembershipClaims*'
    }
  }
  It 'uses safe child-before-parent ordering and resolves only exact owned-parent covered mutations' {
    InModuleScope Maester-PreDownCleanup {
      $app=@{operationId='app-operation';kind='EntraApplication';ownership='Created';state='applied';expected=@{purpose='EasyAuth';displayName='Owned'};exactIds=@{applicationObjectId='app-object';appId='app-client'};after=@{redirectUris=@('https://owned.example/return');identifierUris=@();groupMembershipClaims='SecurityGroup';enableIdTokenIssuance=$true;enableAccessTokenIssuance=$false;signInAudience='AzureADMyOrg'}}
      $app.after.groupMembershipClaims='None'
      $config=@{operationId='config-operation';kind='ApplicationConfiguration';ownership='Mutation';state='applied';expected=@{applicationObjectId='app-object';appId='app-client'};exactIds=@{applicationObjectId='app-object'};after=@{groupMembershipClaims='SecurityGroup'};coveredByOperationId='app-operation'}
      $journal=@{binding=@{tenantId='tenant'};records=@($app,$config)};$protected=@{clientIds=@('setup');objectIds=@()}
      $plan=New-MaesterOwnedCleanupPlan $journal $protected
      @($plan.Entries | ForEach-Object action) | Should -Be @('CoveredByParent','Delete')
      $app.state='deleted'
      { Assert-MaesterCleanupJournal $journal } | Should -Not -Throw
      { Get-MaesterCleanupTarget $config $journal $protected } | Should -Throw '*previously deleted parent was restored*'
      $global:CleanupFixtureState.AppAbsent=$true
      (Get-MaesterCleanupTarget $config $journal $protected).action | Should -BeExactly CoveredByParent
    }
  }
}

Describe 'Finite ADO exact identity and concurrency checks' {
  BeforeEach {
    $global:CleanupFixtureState=@{Revision=3;RepoChanged=$false;ForeignPipeline=$false;Shared=$false;AppChanged=$false;ScopeChanged=$false}
    Mock Assert-MaesterCleanupAdoAuthority -ModuleName Maester-PreDownCleanup {}
    Mock Invoke-MaesterCleanupAdoRequest -ModuleName Maester-PreDownCleanup {
      param($Binding,$Method,$Path)
      $project='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';$repository='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';$endpoint='cccccccc-cccc-4ccc-8ccc-cccccccccccc'
      if ($Path -match '/build/definitions/42\?') { return @{StatusCode=200;Value=@{id=42;revision=$global:CleanupFixtureState.Revision;project=@{id=$project};repository=@{id=$repository;defaultBranch='refs/heads/main'};process=@{yamlFilename='azure-pipelines.yml'}}} }
      if ($Path -match '/serviceendpoint/endpoints/') { return @{StatusCode=200;Value=@{id=$endpoint;type='azurerm';isShared=$global:CleanupFixtureState.Shared;isReady=$true;url='https://management.azure.com/';authorization=@{scheme='WorkloadIdentityFederation';parameters=@{workloadIdentityFederationIssuer='https://issuer.example/';workloadIdentityFederationSubject='owned-subject';tenantid='tenant';serviceprincipalid=if($global:CleanupFixtureState.AppChanged){'foreign-app'}else{'owned-app'};scope=if($global:CleanupFixtureState.ScopeChanged){'/foreign'}else{'/owned/scope'}}};data=@{subscriptionId='subscription';isDraft=$false};serviceEndpointProjectReferences=@(@{projectReference=@{id=$project}})}} }
      if ($Path -match '/pipelinepermissions/') { return @{StatusCode=200;Value=@{allPipelines=@{authorized=$true};pipelines=@()}} }
      if ($Path -match '/build/definitions\?') { return @{StatusCode=200;Value=@{value=@(if($global:CleanupFixtureState.ForeignPipeline){@{id=77}})}} }
      if ($Path -match '/git/repositories/[^/]+\?') { return @{StatusCode=200;Value=@{id=$repository;project=@{id=$project}}} }
      if ($Path -match '/refs\?') { return @{StatusCode=200;Value=@{value=@(@{name='refs/heads/main';objectId=if($global:CleanupFixtureState.RepoChanged){'f'*40}else{'a'*40}})}} }
      if ($Path -match '/pullrequests\?') { return @{StatusCode=200;Value=@{value=@()}} }
      throw "Unexpected ADO fixture path $Path"
    }
  }
  It 'rejects an edited pipeline revision rather than deleting the new pipeline content' {
    InModuleScope Maester-PreDownCleanup {
      $record=@{operationId='pipeline';kind='AdoPipeline';ownership='Created';state='applied';expected=@{organizationId='org';projectId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';repositoryId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';branch='refs/heads/main';yamlPath='azure-pipelines.yml'};exactIds=@{pipelineId='42';pipelineRevision='3'};after=@{}}
      $journal=@{binding=@{};records=@($record)};$protection=@{clientIds=@();objectIds=@()}
      (Get-MaesterCleanupTarget $record $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.Revision=4
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*pipeline revision*'
      $record.exactIds.Remove('pipelineRevision')
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*no exact revision*'
    }
  }
  It 'checks exact endpoint project/app/scope and preserves sharing or foreign pipeline dependencies' {
    InModuleScope Maester-PreDownCleanup {
      $record=@{operationId='endpoint';kind='AdoServiceConnection';ownership='Created';state='applied';expected=@{organizationId='org';projectId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';scope='/owned/scope'};exactIds=@{serviceConnectionId='cccccccc-cccc-4ccc-8ccc-cccccccccccc'};after=@{}}
      $binding=@{tenantId='tenant';subscriptionId='subscription'}
      $config=@{operationId='binding';kind='AdoServiceConnectionBinding';ownership='Mutation';state='applied';coveredByOperationId='endpoint';expected=@{appId='owned-app';serviceConnectionId='cccccccc-cccc-4ccc-8ccc-cccccccccccc'};after=@{scope='/owned/scope';issuer='https://issuer.example/';subject='owned-subject';isReady=$true;isDraft=$false}}
      $permission=@{operationId='permission';kind='AdoPipelineAuthorization';ownership='Mutation';state='applied';coveredByOperationId='endpoint';expected=@{resourceType='endpoint';resourceId='cccccccc-cccc-4ccc-8ccc-cccccccccccc'};after=@{allPipelinesAuthorized=$true}}
      $journal=@{binding=$binding;records=@($record,$config,$permission)};$protection=@{clientIds=@();objectIds=@()}
      (Get-MaesterCleanupTarget $record $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.Shared=$true
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*shared*'
      $global:CleanupFixtureState.Shared=$false;$global:CleanupFixtureState.AppChanged=$true
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*application binding*'
      $global:CleanupFixtureState.AppChanged=$false;$global:CleanupFixtureState.ScopeChanged=$true
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*ARM scope*'
      $global:CleanupFixtureState.ScopeChanged=$false;$global:CleanupFixtureState.ForeignPipeline=$true
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*unrecorded all-pipelines endpoint dependent*'
    }
  }
  It 'accepts only the terminal owned publication commit and preserves rollback or unrecorded source drift' {
    InModuleScope Maester-PreDownCleanup {
      $record=@{operationId='repo';kind='AdoRepository';ownership='Created';state='applied';expected=@{organizationId='org';projectId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'};exactIds=@{repositoryId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'};after=@{}}
      $prior=@{operationId='publication-1';kind='AdoRepositoryPublication';state='applied';ownership='Mutation';coveredByOperationId='repo';expected=@{repositoryId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';branch='refs/heads/main'};after=@{commitId=('a'*40)}}
      $current=@{operationId='publication-2';kind='AdoRepositoryPublication';state='applied';ownership='Mutation';coveredByOperationId='repo';supersedesOperationId='publication-1';expected=@{repositoryId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';branch='refs/heads/main'};before=@{commitId=('a'*40)};after=@{commitId=('b'*40)}}
      $permission=@{operationId='permission';kind='AdoPipelineAuthorization';ownership='Mutation';state='applied';coveredByOperationId='repo';expected=@{resourceType='repository';resourceId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'};after=@{allPipelinesAuthorized=$true}}
      $journal=@{binding=@{};records=@($record,$prior,$current,$permission)};$protection=@{clientIds=@();objectIds=@()}
      # The fixture's live ref is 'a': accepting any historical receipt would be unsafe.
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*unrecorded or changed branch/tag*'
      $prior.after.commitId='b'*40;$current.before.commitId='b'*40;$current.after.commitId='a'*40
      (Get-MaesterCleanupTarget $record $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.RepoChanged=$true
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*unrecorded or changed branch/tag*'
      $global:CleanupFixtureState.RepoChanged=$false
      $current.state='deleted'
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*unrecorded or changed branch/tag*'
    }
  }
  It 'preserves a repository with changed publication refs or unrecorded pipeline sharing' {
    InModuleScope Maester-PreDownCleanup {
      $record=@{operationId='repo';kind='AdoRepository';ownership='Created';state='applied';expected=@{organizationId='org';projectId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'};exactIds=@{repositoryId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'};after=@{}}
      $publication=@{operationId='publication';kind='AdoRepositoryPublication';state='applied';ownership='Mutation';coveredByOperationId='repo';expected=@{repositoryId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';branch='refs/heads/main'};after=@{commitId=('a'*40)}}
      $permission=@{operationId='permission';kind='AdoPipelineAuthorization';ownership='Mutation';state='applied';coveredByOperationId='repo';expected=@{resourceType='repository';resourceId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'};after=@{allPipelinesAuthorized=$true}}
      $journal=@{binding=@{};records=@($record,$publication,$permission)};$protection=@{clientIds=@();objectIds=@()}
      (Get-MaesterCleanupTarget $record $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.RepoChanged=$true
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*unrecorded or changed branch/tag*'
      $global:CleanupFixtureState.RepoChanged=$false;$global:CleanupFixtureState.ForeignPipeline=$true
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*unrecorded all-pipelines repository dependent*'
    }
  }
}

Describe 'Typed provider errors and finite request destinations' {
  BeforeEach {
    Mock Get-AzCliAccessToken -ModuleName Maester-PreDownCleanup { throw 'No token should be acquired for an invalid route.' }
  }
  It 'does not replay persisted absolute URLs or unsafe provider paths' {
    InModuleScope Maester-PreDownCleanup {
      $binding=@{subscriptionId='22222222-2222-4222-8222-222222222222';tenantId='tenant';adoOrganizationUrl='https://dev.azure.com/owned-org'}
      { Invoke-MaesterCleanupAdoRequest $binding DELETE 'https://attacker.example/delete' } | Should -Throw '*Unsupported cleanup Azure DevOps route*'
      { Invoke-MaesterCleanupArmRequest $binding DELETE '/subscriptions/22222222-2222-4222-8222-222222222222/../other' '2022-04-01' } | Should -Throw '*unsafe path*'
      { Invoke-MaesterCleanupGraphRequest $binding DELETE 'https://attacker.example/delete' } | Should -Throw '*Unsupported cleanup Graph route*'
    }
    Should -Invoke Get-AzCliAccessToken -ModuleName Maester-PreDownCleanup -Times 0 -Exactly
  }
  It 'maps only typed numeric Graph 404 to absence and propagates 403 and timeout errors' {
    Mock Invoke-GraphRestRequest -ModuleName Maester-PreDownCleanup {
      $exception=[Exception]::new('authorization failed, 404 misleading text')
      $exception | Add-Member -NotePropertyName ResponseStatusCode -NotePropertyValue 403
      throw $exception
    }
    InModuleScope Maester-PreDownCleanup { { Invoke-MaesterCleanupGraphRequest @{tenantId='tenant'} GET '/v1.0/applications/owned' } | Should -Throw '*authorization failed*' }
    Mock Invoke-GraphRestRequest -ModuleName Maester-PreDownCleanup {
      $exception=[Exception]::new('not found')
      $exception | Add-Member -NotePropertyName ResponseStatusCode -NotePropertyValue 404
      throw $exception
    }
    InModuleScope Maester-PreDownCleanup { (Invoke-MaesterCleanupGraphRequest @{tenantId='tenant'} GET '/v1.0/applications/owned').StatusCode | Should -Be 404 }
    Mock Invoke-GraphRestRequest -ModuleName Maester-PreDownCleanup { throw [TimeoutException]::new('timeout') }
    InModuleScope Maester-PreDownCleanup { { Invoke-MaesterCleanupGraphRequest @{tenantId='tenant'} GET '/v1.0/applications/owned' } | Should -Throw '*timeout*' }
  }
  It 'rejects incomplete dependency pages and accepts a complete empty collection' {
    InModuleScope Maester-PreDownCleanup {
      { Assert-MaesterCleanupCollection @{StatusCode=200;Value=@{value=@();'@odata.nextLink'='https://graph.microsoft.com/next'}} 'children' } | Should -Throw '*paginated*'
      @(Assert-MaesterCleanupCollection @{StatusCode=200;Value=@{value=@()}} 'children').Count | Should -Be 1
      $items=Assert-MaesterCleanupCollection @{StatusCode=200;Value=@{value=@()}} 'children'
      $items.Count | Should -Be 0
      { Assert-MaesterCleanupCollection @{StatusCode=200;Value=@{}} 'children' } | Should -Throw '*does not contain*'
    }
  }
}

Describe 'Finite Exchange exact identity handler' {
  BeforeAll {
    InModuleScope Maester-PreDownCleanup {
      function script:Get-ServicePrincipal { param($Identity) throw 'Unmocked Exchange lookup.' }
      function script:Get-ManagementRoleAssignment { param($Identity,$RoleAssignee) throw 'Unmocked Exchange role lookup.' }
      function script:Remove-ServicePrincipal { param($Identity,$Confirm) throw 'Unmocked Exchange delete.' }
      function script:Remove-ManagementRoleAssignment { param($Identity,$Confirm) throw 'Unmocked Exchange role delete.' }
    }
  }
  BeforeEach {
    $global:CleanupFixtureState=@{ForeignAssignment=$false;PrincipalGone=$false;RoleGone=$false;PrincipalFailure=$false;Deletes=@()}
    Mock Get-ServicePrincipal -ModuleName Maester-PreDownCleanup {
      if ($global:CleanupFixtureState.PrincipalFailure) { throw '404 in message, but no typed absence status' }
      if (-not $global:CleanupFixtureState.PrincipalGone) { [pscustomobject]@{ObjectId='directory-principal';AppId='runtime-app';DisplayName='Friendly only'} }
    }
    Mock Get-ManagementRoleAssignment -ModuleName Maester-PreDownCleanup {
      param($Identity,$RoleAssignee)
      if (-not $global:CleanupFixtureState.RoleGone) { [pscustomobject]@{Identity='exact-role-identity';Role='View-Only Configuration';RoleAssignee='Friendly display name'} }
      if ($RoleAssignee -and $global:CleanupFixtureState.ForeignAssignment) { [pscustomobject]@{Identity='foreign-role';Role='Other';RoleAssignee='Friendly display name'} }
    }
    Mock Remove-ServicePrincipal -ModuleName Maester-PreDownCleanup { $global:CleanupFixtureState.Deletes+=,$Identity;$global:CleanupFixtureState.PrincipalGone=$true }
    Mock Remove-ManagementRoleAssignment -ModuleName Maester-PreDownCleanup { $global:CleanupFixtureState.Deletes+=,$Identity;$global:CleanupFixtureState.RoleGone=$true }
  }
  It 'verifies provider ObjectId/AppId and blocks an unrecorded Exchange role before deleting a principal' {
    InModuleScope Maester-PreDownCleanup {
      $principal=@{operationId='principal';kind='ExchangeServicePrincipal';ownership='Created';state='applied';expected=@{appId='runtime-app';servicePrincipalId='directory-principal'};exactIds=@{exchangeServicePrincipalId='directory-principal'};after=@{}}
      $role=@{operationId='role';kind='ExchangeRoleAssignment';ownership='Created';state='applied';expected=@{servicePrincipalId='directory-principal';roleName='View-Only Configuration'};exactIds=@{exchangeRoleAssignmentId='exact-role-identity'};after=@{}}
      $journal=@{binding=@{};records=@($principal,$role)};$protection=@{clientIds=@();objectIds=@()}
      (Get-MaesterCleanupTarget $principal $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.ForeignAssignment=$true
      { Get-MaesterCleanupTarget $principal $journal $protection } | Should -Throw '*unrecorded Exchange role*'
      $global:CleanupFixtureState.ForeignAssignment=$false;$global:CleanupFixtureState.PrincipalFailure=$true
      { Get-MaesterCleanupTarget $principal $journal $protection } | Should -Throw '*no typed absence status*'
    }
  }
  It 'uses exact role identity for deletion and verifies absence without display-name fallback' {
    InModuleScope Maester-PreDownCleanup {
      $role=@{operationId='role';kind='ExchangeRoleAssignment';ownership='Created';state='applied';expected=@{servicePrincipalId='directory-principal';roleName='View-Only Configuration'};exactIds=@{exchangeRoleAssignmentId='exact-role-identity'};after=@{}}
      $journal=@{binding=@{};records=@($role)};$protection=@{clientIds=@();objectIds=@()}
      $entry=Get-MaesterCleanupTarget $role $journal $protection
      Invoke-MaesterCleanupDelete $entry $role @{}
      (Test-MaesterCleanupExactAbsence $entry $role @{}) | Should -BeTrue
      $global:CleanupFixtureState.Deletes | Should -Be @('exact-role-identity')
    }
  }
}

Describe 'Canonical selected cleanup Graph session' {
  BeforeAll {
    InModuleScope Maester-PreDownCleanup { function script:Get-MgContext { [pscustomobject]@{ClientId='66666666-6666-4666-8666-666666666666'} } }
  }
  BeforeEach {
    $script:oldClient=$env:MAESTER_SETUP_CLIENT_ID;$script:oldAccount=$env:MAESTER_SETUP_ACCOUNT
    $env:MAESTER_SETUP_CLIENT_ID='77777777-7777-4777-8777-777777777777';$env:MAESTER_SETUP_ACCOUNT='operator@example.com'
    $global:CleanupFixtureState=@{Scopes=@();Clients=@();Interactive=$null;Replacement=$null}
    Mock Assert-GraphAccess -ModuleName Maester-PreDownCleanup {
      param($TenantId,$ClientId,$ExpectedAccount,$Scopes,$AllowInteractive,$AllowContextReplacement)
      $global:CleanupFixtureState.Scopes=@($Scopes);$global:CleanupFixtureState.Interactive=[bool]$AllowInteractive;$global:CleanupFixtureState.Replacement=[bool]$AllowContextReplacement
    }
    Mock Invoke-MaesterCleanupGraphRequest -ModuleName Maester-PreDownCleanup {
      param($Binding,$Method,$Path)
      if ($Path -match "appId eq '([^']+)'") { $global:CleanupFixtureState.Clients+=,$Matches[1] }
      @{StatusCode=200;Value=@{value=@(@{id="protected-$($Matches[1])"})}}
    }
    Mock Get-AzCliAccessToken -ModuleName Maester-PreDownCleanup { throw 'Cleanup Graph must not request a CLI token.' }
  }
  AfterEach { $env:MAESTER_SETUP_CLIENT_ID=$script:oldClient;$env:MAESTER_SETUP_ACCOUNT=$script:oldAccount }
  It 'selects the complete exact union once and protects original/current/ambient clients plus the access group' {
    InModuleScope Maester-PreDownCleanup {
      $journal=@{binding=@{tenantId='tenant';setupClientId='33333333-3333-4333-8333-333333333333'};records=@(@{kind='DirectoryRoleAssignment';state='applied';after=@{}},@{kind='EntraApplication';state='applied';after=@{}},@{kind='OAuth2PermissionGrant';state='applied';after=@{}},@{kind='WebAppAuthConfiguration';state='applied';after=@{allowedGroups=@('88888888-8888-4888-8888-888888888888')}})}
      $protection=Initialize-MaesterCleanupGraph $journal
      $global:CleanupFixtureState.Scopes | Should -Be @('Application.Read.All','Application.ReadWrite.All','DelegatedPermissionGrant.ReadWrite.All','Directory.Read.All','RoleManagement.ReadWrite.Directory')
      @($protection.clientIds).Count | Should -Be 3
      $protection.objectIds | Should -Contain '88888888-8888-4888-8888-888888888888'
      $global:CleanupFixtureState.Interactive | Should -BeFalse
      $global:CleanupFixtureState.Replacement | Should -BeFalse
    }
    Should -Invoke Assert-GraphAccess -ModuleName Maester-PreDownCleanup -Times 1 -Exactly
    Should -Invoke Get-AzCliAccessToken -ModuleName Maester-PreDownCleanup -Times 0 -Exactly
  }
  It 'propagates authentication failure without expanding permissions or retrying a different identity' {
    Mock Assert-GraphAccess -ModuleName Maester-PreDownCleanup { throw 'selected scope not preconsented' }
    InModuleScope Maester-PreDownCleanup {
      { Initialize-MaesterCleanupGraph @{binding=@{tenantId='tenant';setupClientId='33333333-3333-4333-8333-333333333333'};records=@(@{kind='GraphAppRoleAssignment';state='applied';after=@{}})} } | Should -Throw '*not preconsented*'
    }
    Should -Invoke Assert-GraphAccess -ModuleName Maester-PreDownCleanup -Times 1 -Exactly
    Should -Invoke Invoke-MaesterCleanupGraphRequest -ModuleName Maester-PreDownCleanup -Times 0 -Exactly
  }
}

Describe 'Exact finite grant and credential handlers' {
  BeforeEach {
    $global:CleanupFixtureState=@{Value=@{};Status=200}
    Mock Invoke-MaesterCleanupGraphRequest -ModuleName Maester-PreDownCleanup { @{StatusCode=$global:CleanupFixtureState.Status;Value=$global:CleanupFixtureState.Value} }
    Mock Invoke-MaesterCleanupArmRequest -ModuleName Maester-PreDownCleanup { @{StatusCode=$global:CleanupFixtureState.Status;Value=$global:CleanupFixtureState.Value} }
  }
  It 'verifies exact app-role, FIC issuer/subject/audiences and delegated grant scopes' {
    InModuleScope Maester-PreDownCleanup {
      $protection=@{clientIds=@();objectIds=@()};$journal=@{binding=@{tenantId='tenant'};records=@()}
      $record=@{operationId='role';kind='GraphAppRoleAssignment';ownership='Created';expected=@{principalId='principal';resourceId='resource';appRoleId='role'};exactIds=@{assignmentId='opaque-id'};after=@{}}
      $global:CleanupFixtureState.Value=@{id='opaque-id';principalId='principal';resourceId='resource';appRoleId='role'}
      (Get-MaesterCleanupTarget $record $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.Value.resourceId='other'
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*app-role resourceId*'
      $record=@{operationId='fic';kind='FederatedIdentityCredential';ownership='Created';expected=@{applicationObjectId='parent';issuer='https://issuer.example/';subject='exact-subject';audiences=@('api://AzureADTokenExchange')};exactIds=@{federatedCredentialId='fic-id'};after=@{}}
      $global:CleanupFixtureState.Value=@{id='fic-id';issuer='https://issuer.example/';subject='exact-subject';audiences=@('api://AzureADTokenExchange')}
      (Get-MaesterCleanupTarget $record $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.Value.subject='different-subject'
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*federated credential subject*'
      $record=@{operationId='grant';kind='OAuth2PermissionGrant';ownership='Created';expected=@{clientId='client';resourceId='resource';consentType='AllPrincipals'};exactIds=@{grantId='grant-id'};after=@{scopes=@('User.Read','openid')}}
      $global:CleanupFixtureState.Value=@{id='grant-id';clientId='client';resourceId='resource';consentType='AllPrincipals';scope='openid User.Read'}
      (Get-MaesterCleanupTarget $record $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.Value.scope='openid User.Read Mail.Read'
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*delegated grant scopes changed*'
    }
  }
  It 'verifies full Azure role target tuple and discharges Web App auth only after exact ARM 404' {
    InModuleScope Maester-PreDownCleanup {
      $protection=@{clientIds=@();objectIds=@()};$group='/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/owned';$journal=@{binding=@{resourceGroupId=$group};records=@()}
      $record=@{operationId='rbac';kind='AzureRoleAssignment';ownership='Created';expected=@{principalId='principal';roleDefinitionId='reader';scope=$group;principalType='ServicePrincipal'};exactIds=@{roleAssignmentId="$group/providers/Microsoft.Authorization/roleAssignments/assignment"};after=@{}}
      $global:CleanupFixtureState.Value=@{id=$record.exactIds.roleAssignmentId;properties=@{principalId='principal';roleDefinitionId='reader';scope=$group;principalType='ServicePrincipal'}}
      (Get-MaesterCleanupTarget $record $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.Value.properties.principalId='foreign'
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*Azure role principalId*'
      $record=@{operationId='auth';kind='WebAppAuthConfiguration';ownership='Mutation';expected=@{webAppResourceId="$group/providers/Microsoft.Web/sites/owned-web"};exactIds=@{};after=@{}}
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*Web App still exists*'
      $global:CleanupFixtureState.Status=404
      (Get-MaesterCleanupTarget $record $journal $protection).action | Should -BeExactly AlreadyAbsent
    }
  }
}

Describe 'Owned parent completion and covered mutation checkpoints' {
  BeforeEach {
    $fixture=New-CleanupFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
    $session=Open-MaesterOwnershipJournal -ProjectRoot $fixture.Root -Binding $fixture.Binding -RequireExisting
    try {
      $app=Start-MaesterOwnedOperation -Session $session -Key 'easy-auth/app' -Kind EntraApplication -PlanHash ('b'*64) -Ownership Created -Expected @{purpose='EasyAuth';displayName='OwnedApp'} -After @{redirectUris=@();identifierUris=@();groupMembershipClaims='None';enableIdTokenIssuance=$false;enableAccessTokenIssuance=$false;signInAudience='AzureADMyOrg'}
      $app=Complete-MaesterOwnedOperation -Session $session -OperationId $app.operationId -ExactIds @{applicationObjectId='99999999-9999-4999-8999-999999999999';appId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}
      $config=Start-MaesterOwnedOperation -Session $session -Key 'easy-auth/config' -Kind ApplicationConfiguration -PlanHash ('b'*64) -Ownership Mutation -Expected @{applicationObjectId=$app.exactIds.applicationObjectId;appId=$app.exactIds.appId} -After @{groupMembershipClaims='None'} -CoveredByOperationId $app.operationId
      $config=Complete-MaesterOwnedOperation -Session $session -OperationId $config.operationId -ExactIds @{applicationObjectId=$app.exactIds.applicationObjectId}
    } finally { $session.Dispose() }
    $global:CleanupFixtureState=@{AppPresent=$true;RolePresent=$true;Deletes=@();CheckpointPath=(Join-Path $fixture.Root '.azure/cleanup-test/maester-setup-ownership.json');ConfigId=$config.operationId}
    Mock Get-AzCliSubscriptionContext -ModuleName Maester-PreDownCleanup { @{id=$SubscriptionId;tenantId=$TenantId;state='Enabled'} }
    Mock Invoke-MaesterCleanupArmRequest -ModuleName Maester-PreDownCleanup { @{StatusCode=404;Value=$null} }
    Mock Initialize-MaesterCleanupGraph -ModuleName Maester-PreDownCleanup { @{clientIds=@();objectIds=@()} }
    Mock Initialize-MaesterCleanupExchange -ModuleName Maester-PreDownCleanup {}
    Mock Invoke-MaesterCleanupGraphRequest -ModuleName Maester-PreDownCleanup {
      param($Binding,$Method,$Path)
      $isApp=$Path -match '^/v1\.0/applications/99999999-9999-4999-8999-999999999999(?:\?|$)'
      $isRole=$Path -match '/roleAssignments/assignment-id$'
      if ($Method -eq 'DELETE') {
        $checkpoint=Get-Content -LiteralPath $global:CleanupFixtureState.CheckpointPath -Raw | ConvertFrom-Json -AsHashtable
        $kind=if($isApp){'EntraApplication'}else{'DirectoryRoleAssignment'}
        @($checkpoint.records | Where-Object kind -CEQ $kind)[0].state | Should -BeExactly deleting
        @($checkpoint.records | Where-Object operationId -CEQ $global:CleanupFixtureState.ConfigId)[0].state | Should -BeExactly applied
        $global:CleanupFixtureState.Deletes+=,$kind
        if ($isApp) {$global:CleanupFixtureState.AppPresent=$false} else {$global:CleanupFixtureState.RolePresent=$false}
        return @{StatusCode=204;Value=$null}
      }
      if ($isRole) { if (-not $global:CleanupFixtureState.RolePresent) { return @{StatusCode=404;Value=$null} }; return @{StatusCode=200;Value=@{id='assignment-id';principalId='44444444-4444-4444-8444-444444444444';roleDefinitionId='55555555-5555-4555-8555-555555555555';directoryScopeId='/'}} }
      if ($isApp) { if (-not $global:CleanupFixtureState.AppPresent) { return @{StatusCode=404;Value=$null} }; return @{StatusCode=200;Value=@{id='99999999-9999-4999-8999-999999999999';appId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';displayName='OwnedApp';groupMembershipClaims='None';signInAudience='AzureADMyOrg';identifierUris=@();web=@{redirectUris=@();implicitGrantSettings=@{enableIdTokenIssuance=$false;enableAccessTokenIssuance=$false}};passwordCredentials=@();keyCredentials=@()}} }
      @{StatusCode=200;Value=@{value=@()}}
    }
  }
  It 'checkpoints each deleting state before DELETE and marks the covered mutation only after parent absence' {
    $plan=Get-MaesterOwnedCleanupPlan -ProjectRoot $fixture.Root -Binding $fixture.Binding
    (Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -ApprovedPlanHash $plan.PlanHash).Completed | Should -BeTrue
    $global:CleanupFixtureState.Deletes | Should -Be @('DirectoryRoleAssignment','EntraApplication')
    $session=Open-MaesterOwnershipJournal -ProjectRoot $fixture.Root -Binding $fixture.Binding -RequireExisting
    try { @((Get-MaesterOwnershipJournal $session).records | Where-Object state -NE deleted).Count | Should -Be 0 } finally { $session.Dispose() }
  }
  It 'safely discharges a remaining mutation after a parent removal was already checkpointed' {
    $session=Open-MaesterOwnershipJournal -ProjectRoot $fixture.Root -Binding $fixture.Binding -RequireExisting
    try {
      foreach ($record in @((Get-MaesterOwnershipJournal $session).records | Where-Object ownership -EQ Created)) {
        $null=Set-MaesterOwnedOperationState -Session $session -OperationId $record.operationId -State deleting
        $null=Set-MaesterOwnedOperationState -Session $session -OperationId $record.operationId -State deleted
      }
    } finally { $session.Dispose() }
    $global:CleanupFixtureState.AppPresent=$false;$global:CleanupFixtureState.RolePresent=$false
    $plan=Get-MaesterOwnedCleanupPlan -ProjectRoot $fixture.Root -Binding $fixture.Binding
    $plan.Entries[0].action | Should -BeExactly CoveredByParent
    (Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $fixture.Root -Binding $fixture.Binding -ApprovedPlanHash $plan.PlanHash).Completed | Should -BeTrue
    $global:CleanupFixtureState.Deletes.Count | Should -Be 0
  }
}

Describe 'Read-only exported cleanup scope preview' {
  It 'returns the exact derived scopes without authenticating or calling any provider' {
    $fixture=New-CleanupFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
    Mock Initialize-MaesterCleanupGraph -ModuleName Maester-PreDownCleanup { throw 'No auth in scope preview.' }
    Mock Invoke-MaesterCleanupArmRequest -ModuleName Maester-PreDownCleanup { throw 'No provider in scope preview.' }
    Mock Invoke-MaesterCleanupGraphRequest -ModuleName Maester-PreDownCleanup { throw 'No provider in scope preview.' }
    @(Get-MaesterOwnedCleanupScopes -ProjectRoot $fixture.Root -Binding $fixture.Binding) | Should -Be @('Application.Read.All','Directory.Read.All','RoleManagement.ReadWrite.Directory')
    Should -Invoke Initialize-MaesterCleanupGraph -ModuleName Maester-PreDownCleanup -Times 0 -Exactly
    Should -Invoke Invoke-MaesterCleanupArmRequest -ModuleName Maester-PreDownCleanup -Times 0 -Exactly
    Should -Invoke Invoke-MaesterCleanupGraphRequest -ModuleName Maester-PreDownCleanup -Times 0 -Exactly
    InModuleScope Maester-PreDownCleanup {
      @(Get-MaesterCleanupScopes @{records=@(@{kind='EntraServicePrincipal';state='applied'})}) | Should -Be @('Application.Read.All','Application.ReadWrite.All','Directory.Read.All')
    }
  }
}

Describe 'Bootstrap-style partial endpoint cleanup' {
  BeforeEach {
    $global:CleanupFixtureState=@{Bound=$false;Draft=$true;Ready=$true;Issuer='https://vstoken.dev.azure.com/11111111-1111-4111-8111-111111111111';Subject='sc://owned-org/owned-project/owned-connection'}
    Mock Assert-MaesterCleanupAdoAuthority -ModuleName Maester-PreDownCleanup {}
    Mock Invoke-MaesterCleanupAdoRequest -ModuleName Maester-PreDownCleanup {
      param($Binding,$Method,$Path)
      if ($Path -match '/pipelinepermissions/') { return @{StatusCode=404;Value=$null} }
      # The fixture mirrors Maester-AdoBootstrap's POST/snapshot provider shape:
      # isReady at top level, isDraft in data, federation in authorization.parameters.
      @{StatusCode=200;Value=[pscustomobject]@{
        id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';name='owned-connection';type='AzureRM';url='https://management.azure.com/';isShared=$false;isReady=$global:CleanupFixtureState.Ready
        data=[pscustomobject]@{subscriptionId='subscription';subscriptionName='Owned';environment='AzureCloud';scopeLevel='Subscription';creationMode='Manual';isDraft=$global:CleanupFixtureState.Draft}
        authorization=[pscustomobject]@{scheme='WorkloadIdentityFederation';parameters=[pscustomobject]@{tenantid='tenant';serviceprincipalid=if($global:CleanupFixtureState.Bound){'owned-app'}else{''};scope='/owned/scope';workloadIdentityFederationIssuer=$global:CleanupFixtureState.Issuer;workloadIdentityFederationSubject=$global:CleanupFixtureState.Subject}}
        serviceEndpointProjectReferences=@([pscustomobject]@{name='owned-connection';projectReference=[pscustomobject]@{id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';name='owned-project'}})
      }}
    }
  }
  It 'can remove its exact unbound draft after early bootstrap stops before application creation' {
    InModuleScope Maester-PreDownCleanup {
      $record=@{operationId='endpoint';kind='AdoServiceConnection';ownership='Created';state='applied';expected=@{organizationId='org';projectId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';scope='/owned/scope';serviceConnectionName='owned-connection'};exactIds=@{serviceConnectionId='cccccccc-cccc-4ccc-8ccc-cccccccccccc'};after=@{}}
      $journal=@{binding=@{tenantId='tenant';subscriptionId='subscription'};records=@($record)};$protection=@{clientIds=@();objectIds=@()}
      (Get-MaesterCleanupTarget $record $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.Draft=$false
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*unchanged unbound draft*'
    }
  }
  It 'checks the final authorization.parameters federation tuple and data.isDraft against the covered mutation receipt' {
    InModuleScope Maester-PreDownCleanup {
      $record=@{operationId='endpoint';kind='AdoServiceConnection';ownership='Created';state='applied';expected=@{organizationId='org';projectId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';scope='/owned/scope';serviceConnectionName='owned-connection'};exactIds=@{serviceConnectionId='cccccccc-cccc-4ccc-8ccc-cccccccccccc'};after=@{}}
      $config=@{operationId='binding';kind='AdoServiceConnectionBinding';ownership='Mutation';state='applied';coveredByOperationId='endpoint';expected=@{appId='owned-app';serviceConnectionId='cccccccc-cccc-4ccc-8ccc-cccccccccccc'};after=@{scope='/owned/scope';isReady=$true;isDraft=$false;issuer='https://vstoken.dev.azure.com/11111111-1111-4111-8111-111111111111';subject='sc://owned-org/owned-project/owned-connection'}}
      $journal=@{binding=@{tenantId='tenant';subscriptionId='subscription'};records=@($record,$config)};$protection=@{clientIds=@();objectIds=@()}
      $global:CleanupFixtureState.Bound=$true;$global:CleanupFixtureState.Draft=$false
      (Get-MaesterCleanupTarget $record $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.Subject='sc://foreign-org/foreign-project/foreign-connection'
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*endpoint federation subject*'
      $global:CleanupFixtureState.Subject='sc://owned-org/owned-project/owned-connection';$global:CleanupFixtureState.Draft=$true
      { Get-MaesterCleanupTarget $record $journal $protection } | Should -Throw '*endpoint draft state*'
    }
  }
}

Describe 'Non-interactive cleanup approval guard' {
  It 'rejects interactive consent before Read-Host when stdin or CI is noninteractive' {
    Mock Test-MaesterCleanupCanPrompt -ModuleName Maester-PreDownCleanup { $false }
    Mock Read-Host -ModuleName Maester-PreDownCleanup { throw 'Must not read input.' }
    InModuleScope Maester-PreDownCleanup { { Confirm-MaesterCleanupPlan -PlanHash ('a'*64) -InteractiveConsent } | Should -Throw '*Interactive cleanup approval is unavailable*' }
    Should -Invoke Read-Host -ModuleName Maester-PreDownCleanup -Times 0 -Exactly
  }
}

Describe 'Documented complete Exchange inventory absence' {
  It 'filters exact ObjectId and never mistakes unrelated principals for the missing target' {
    Mock Get-ServicePrincipal -ModuleName Maester-PreDownCleanup { [pscustomobject]@{ObjectId='unrelated-principal';AppId='unrelated-app'} }
    InModuleScope Maester-PreDownCleanup {
      $record=@{kind='ExchangeServicePrincipal';exactIds=@{exchangeServicePrincipalId='owned-principal'}}
      (Get-MaesterCleanupExchangeObject $record).StatusCode | Should -Be 404
      (Test-MaesterCleanupExactAbsence @{provider='Exchange'} $record @{}) | Should -BeTrue
    }
    Should -Invoke Get-ServicePrincipal -ModuleName Maester-PreDownCleanup -Times 2 -Exactly -ParameterFilter { -not $Identity }
  }
  It 'refuses incomplete identity inventories and any failed enumeration' {
    Mock Get-ServicePrincipal -ModuleName Maester-PreDownCleanup { [pscustomobject]@{DisplayName='identity missing'} }
    InModuleScope Maester-PreDownCleanup { { Get-MaesterCleanupExchangeObject @{kind='ExchangeServicePrincipal';exactIds=@{exchangeServicePrincipalId='owned-principal'}} } | Should -Throw '*incomplete exact identities*' }
    Mock Get-ServicePrincipal -ModuleName Maester-PreDownCleanup { $e=[Exception]::new('collection route missing');$e|Add-Member -NotePropertyName ResponseStatusCode -NotePropertyValue 404;throw $e }
    InModuleScope Maester-PreDownCleanup { { Get-MaesterCleanupExchangeObject @{kind='ExchangeServicePrincipal';exactIds=@{exchangeServicePrincipalId='owned-principal'}} } | Should -Throw '*collection route missing*' }
  }
}

Describe 'Owned principal membership and covered grant dependency checks' {
  BeforeEach {
    $global:CleanupFixtureState=@{MembershipType='#microsoft.graph.directoryRole';RoleTemplate='owned-role-definition';MembershipPresent=$true;GrantPresent=$false;GrantScopes='User.Read';GrantPrincipal=$null}
    Mock Invoke-MaesterCleanupArmRequest -ModuleName Maester-PreDownCleanup { @{StatusCode=200;Value=@{value=@()}} }
    Mock Invoke-MaesterCleanupGraphRequest -ModuleName Maester-PreDownCleanup {
      param($Binding,$Method,$Path)
      if ($Path -match '^/v1\.0/servicePrincipals/runtime-principal\?') { return @{StatusCode=200;Value=@{id='runtime-principal';appId='runtime-app';appOwnerOrganizationId='tenant';passwordCredentials=@();keyCredentials=@()}} }
      if ($Path -match '^/v1\.0/directoryRoles/') { return @{StatusCode=200;Value=@{id='12121212-1212-4212-8212-121212121212';roleTemplateId=$global:CleanupFixtureState.RoleTemplate}} }
      if ($Path -match '/memberOf\?') { return @{StatusCode=200;Value=@{value=@(if($global:CleanupFixtureState.MembershipPresent){@{id='12121212-1212-4212-8212-121212121212';'@odata.type'=$global:CleanupFixtureState.MembershipType}})}} }
      if ($Path -match '/roleAssignments/role-assignment$') { return @{StatusCode=200;Value=@{id='role-assignment';principalId='runtime-principal';roleDefinitionId='owned-role-definition';directoryScopeId='/'}} }
      if ($Path -match "oauth2PermissionGrants.*clientId eq" -and $global:CleanupFixtureState.GrantPresent) { return @{StatusCode=200;Value=@{value=@(@{id='covered-grant';clientId='runtime-principal';resourceId='resource';consentType='AllPrincipals';scope=$global:CleanupFixtureState.GrantScopes;principalId=$global:CleanupFixtureState.GrantPrincipal})}} }
      @{StatusCode=200;Value=@{value=@()}}
    }
  }
  It 'allows the initial exact owned built-in role and rejects foreign/group/blank or stale memberships' {
    InModuleScope Maester-PreDownCleanup {
      $principal=@{operationId='principal';kind='EntraServicePrincipal';ownership='Created';state='applied';expected=@{appId='runtime-app'};exactIds=@{servicePrincipalId='runtime-principal'};after=@{}}
      $role=@{operationId='role';kind='DirectoryRoleAssignment';ownership='Created';state='applied';expected=@{principalId='runtime-principal';roleDefinitionId='owned-role-definition';directoryScopeId='/'};exactIds=@{assignmentId='role-assignment'};after=@{}}
      $journal=@{binding=@{tenantId='tenant';subscriptionId='subscription'};records=@($principal,$role)};$protection=@{clientIds=@();objectIds=@()}
      @((New-MaesterOwnedCleanupPlan $journal $protection).Entries | ForEach-Object kind) | Should -Be @('DirectoryRoleAssignment','EntraServicePrincipal')
      $global:CleanupFixtureState.RoleTemplate='foreign-role'
      { Get-MaesterCleanupTarget $principal $journal $protection } | Should -Throw '*unrecorded or stale directory-role*'
      $global:CleanupFixtureState.RoleTemplate='owned-role-definition';$global:CleanupFixtureState.MembershipType='#microsoft.graph.group'
      { Get-MaesterCleanupTarget $principal $journal $protection } | Should -Throw '*group or unknown membership*'
      $global:CleanupFixtureState.MembershipType=''
      { Get-MaesterCleanupTarget $principal $journal $protection } | Should -Throw '*group or unknown membership*'
      $global:CleanupFixtureState.MembershipType='#microsoft.graph.directoryRole';$role.state='deleted'
      { Get-MaesterCleanupTarget $principal $journal $protection } | Should -Throw '*unrecorded or stale directory-role*'
    }
  }
  It 'does not let parent deletion bypass a concurrently expanded covered delegated grant' {
    InModuleScope Maester-PreDownCleanup {
      $principal=@{operationId='principal';kind='EntraServicePrincipal';ownership='Created';state='applied';expected=@{appId='runtime-app'};exactIds=@{servicePrincipalId='runtime-principal'};after=@{}}
      $grant=@{operationId='grant';kind='OAuth2PermissionGrant';ownership='Mutation';state='applied';expected=@{clientId='runtime-principal';resourceId='resource';consentType='AllPrincipals'};exactIds=@{grantId='covered-grant'};after=@{scopes=@('User.Read')};coveredByOperationId='principal'}
      $journal=@{binding=@{tenantId='tenant';subscriptionId='subscription'};records=@($principal,$grant)};$protection=@{clientIds=@();objectIds=@()}
      $global:CleanupFixtureState.MembershipPresent=$false;$global:CleanupFixtureState.GrantPresent=$true
      (Get-MaesterCleanupTarget $principal $journal $protection).action | Should -BeExactly Delete
      $global:CleanupFixtureState.GrantScopes='User.Read Mail.Read'
      { Get-MaesterCleanupTarget $principal $journal $protection } | Should -Throw '*dependent delegated grant scopes changed*'
      $global:CleanupFixtureState.GrantScopes='User.Read';$global:CleanupFixtureState.GrantPrincipal='foreign-principal'
      { Get-MaesterCleanupTarget $principal $journal $protection } | Should -Throw '*AllPrincipals dependent delegated grant has a non-null principalId*'
    }
  }
}

Describe 'Supported pipeline deletion semantics' {
  It 'deletes the exact definition through the documented route without an unsupported revision query' {
    Mock Invoke-MaesterCleanupAdoRequest -ModuleName Maester-PreDownCleanup { @{StatusCode=204;Value=$null} }
    InModuleScope Maester-PreDownCleanup {
      $entry=@{provider='Ado';target='/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/_apis/build/definitions/42?api-version=7.1'}
      $record=@{kind='AdoPipeline';exactIds=@{pipelineId='42';pipelineRevision='3'}}
      Invoke-MaesterCleanupDelete $entry $record @{}
    }
    Should -Invoke Invoke-MaesterCleanupAdoRequest -ModuleName Maester-PreDownCleanup -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Path -ceq '/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/_apis/build/definitions/42?api-version=7.1' }
  }
}

Describe 'Idempotent scope preview and finite directory-role read' {
  It 'returns no scopes and performs no authentication when all receipts are deleted' {
    $fixture=New-CleanupFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
    $session=Open-MaesterOwnershipJournal -ProjectRoot $fixture.Root -Binding $fixture.Binding -RequireExisting
    try {
      $null=Set-MaesterOwnedOperationState -Session $session -OperationId $fixture.Record.operationId -State deleting
      $null=Set-MaesterOwnedOperationState -Session $session -OperationId $fixture.Record.operationId -State deleted
    } finally { $session.Dispose() }
    Mock Initialize-MaesterCleanupGraph -ModuleName Maester-PreDownCleanup { throw 'No auth on idempotent scope preview.' }
    @(Get-MaesterOwnedCleanupScopes -ProjectRoot $fixture.Root -Binding $fixture.Binding).Count | Should -Be 0
    Should -Invoke Initialize-MaesterCleanupGraph -ModuleName Maester-PreDownCleanup -Times 0 -Exactly
  }
  It 'allows only exact directory-role GET and never a directory-role deletion or advanced query cast' {
    Mock Invoke-GraphRestRequest -ModuleName Maester-PreDownCleanup { @{id='12121212-1212-4212-8212-121212121212';roleTemplateId='template'} }
    InModuleScope Maester-PreDownCleanup {
      (Invoke-MaesterCleanupGraphRequest @{tenantId='tenant'} GET '/v1.0/directoryRoles/12121212-1212-4212-8212-121212121212?$select=id,roleTemplateId').StatusCode | Should -Be 200
      { Invoke-MaesterCleanupGraphRequest @{tenantId='tenant'} DELETE '/v1.0/directoryRoles/12121212-1212-4212-8212-121212121212?$select=id,roleTemplateId' } | Should -Throw '*Unsupported cleanup Graph route*'
    }
    Should -Invoke Invoke-GraphRestRequest -ModuleName Maester-PreDownCleanup -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and $Uri -ceq 'https://graph.microsoft.com/v1.0/directoryRoles/12121212-1212-4212-8212-121212121212?$select=id,roleTemplateId' }
  }
}

Describe 'Case-sensitive opaque dependency identity' {
  It 'never treats a case-variant Graph opaque ID as the receipted owned child' {
    InModuleScope Maester-PreDownCleanup {
      { Assert-MaesterCleanupKnownChildren @(@{id='Opaque-AbC'}) @('Opaque-abc') 'grant' } | Should -Throw '*unrecorded grant*'
      { Assert-MaesterCleanupKnownChildren @(@{id='Opaque-abc'}) @('Opaque-abc') 'grant' } | Should -Not -Throw
    }
  }
}

Describe 'Malformed and duplicate dependency inventories' {
  It 'requires an actual provider array and unique case-sensitive child IDs' {
    InModuleScope Maester-PreDownCleanup {
      foreach ($value in @('owned',@{id='owned'})) {
        { Assert-MaesterCleanupCollection @{StatusCode=200;Value=@{value=$value}} 'children' } | Should -Throw '*exact array value inventory*'
      }
      { Assert-MaesterCleanupKnownChildren @(@{id='owned'},@{id='owned'}) @('owned') 'child' } | Should -Throw '*duplicate child identity*'
    }
  }
}

Describe 'Complete owned application creation baseline' {
  It 'preserves missing baselines and new redirect, identifier or sign-in changes, while applying exact covered overrides' {
    InModuleScope Maester-PreDownCleanup {
      $baseline=@{redirectUris=@();identifierUris=@();groupMembershipClaims='None';enableIdTokenIssuance=$false;enableAccessTokenIssuance=$false;signInAudience='AzureADMyOrg'}
      $record=@{operationId='app';kind='EntraApplication';state='applied';ownership='Created';exactIds=@{applicationObjectId='owned-app';appId='owned-client'};after=$baseline}
      $application=@{web=@{redirectUris=@();implicitGrantSettings=@{enableIdTokenIssuance=$false;enableAccessTokenIssuance=$false}};identifierUris=@();groupMembershipClaims=$null;signInAudience='AzureADMyOrg'}
      $journal=@{records=@($record)}
      { Assert-MaesterCleanupApplicationConfiguration $record $journal $application } | Should -Not -Throw
      $application.web.redirectUris=@('https://new.example/callback')
      { Assert-MaesterCleanupApplicationConfiguration $record $journal $application } | Should -Throw '*application configuration redirectUris changed*'
      $override=@{kind='ApplicationConfiguration';state='applied';ownership='Mutation';coveredByOperationId='app';after=@{redirectUris=@('https://new.example/callback')}}
      $journal.records=@($record,$override)
      { Assert-MaesterCleanupApplicationConfiguration $record $journal $application } | Should -Not -Throw
      $application.identifierUris=@('api://new-resource')
      { Assert-MaesterCleanupApplicationConfiguration $record $journal $application } | Should -Throw '*application configuration identifierUris changed*'
      $application.identifierUris=@();$application.signInAudience='AzureADMultipleOrgs'
      { Assert-MaesterCleanupApplicationConfiguration $record $journal $application } | Should -Throw '*application configuration signInAudience*'
      $application.signInAudience='AzureADMyOrg';$record.after.Remove('enableIdTokenIssuance')
      { Assert-MaesterCleanupApplicationConfiguration $record $journal $application } | Should -Throw '*no complete configuration baseline*'
    }
  }
}
