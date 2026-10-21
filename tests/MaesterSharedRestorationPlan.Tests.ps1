BeforeAll {
  Import-Module (Join-Path $PSScriptRoot '../tooling/Maester-SharedRestorationPlan.psm1') -Force
  $module = Get-Module Maester-SharedRestorationPlan
  function Copy-TestValue($v) { $v | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable -Depth 16 -DateKind String }
  function Update-TestEvidence {
    $evidence.journalHash = & $module { param($j) Get-SharedHash $j } $journal
    $evidence.observations[0].expected = Copy-TestValue $journal.records[0].expected
    $evidence.observations[0].exactIds = Copy-TestValue $journal.records[0].exactIds
  }
  function Get-TestPlan { Get-MaesterSharedRestorationPlan -Journal $journal -Binding $binding -Evidence $evidence -Protection $protection -Now $now }
}
Describe 'Offline shared mutation concurrency contract' {
  BeforeEach {
    $now = [DateTimeOffset]::Parse('2026-10-21T18:00:00+00:00')
    $binding = @{ environmentName='shared-test'; solutionName='maester'; tenantId='11111111-1111-4111-8111-111111111111'; subscriptionId='22222222-2222-4222-8222-222222222222'; setupClientId='33333333-3333-4333-8333-333333333333'; resourceGroupId='/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/shared-test' }
    $before = @{redirectUris=@('https://example.test/original'); identifierUris=@(); groupMembershipClaims='None'; enableIdTokenIssuance=$false; enableAccessTokenIssuance=$false}
    $after = @{redirectUris=@('https://example.test/new'); identifierUris=@(); groupMembershipClaims='SecurityGroup'; enableIdTokenIssuance=$true; enableAccessTokenIssuance=$false}
    $record = @{ operationId='44444444-4444-4444-8444-444444444444'; key='application-config:test'; kind='ApplicationConfiguration'; planHash=('a'*64); ownership='Mutation'; state='applied'; expected=@{applicationObjectId='55555555-5555-4555-8555-555555555555';appId='66666666-6666-4666-8666-666666666666'}; exactIds=@{applicationObjectId='55555555-5555-4555-8555-555555555555'}; before=$before; after=$after; coveredByOperationId=$null; createdUtc=$now.AddMinutes(-3).ToString('o'); updatedUtc=$now.AddMinutes(-2).ToString('o') }
    $journal = @{schemaVersion='1.0';binding=$binding;records=@($record)}
    $evidence = @{schemaVersion='1.0';binding=(Copy-TestValue $binding);journalHash='';observations=@(@{operationId=$record.operationId;observedUtc=$now.AddMinutes(-1).ToString('o');state='present';expected=(Copy-TestValue $record.expected);exactIds=(Copy-TestValue $record.exactIds);values=(Copy-TestValue $after)})}
    $protection = @{applicationObjectIds=@();appIds=@();servicePrincipalIds=@()}
    Update-TestEvidence
  }
  It 'identifies a captured matching afterstate as review-only and never executable' {
    $p = Get-TestPlan
    $p.operations[0].status | Should -BeExactly 'reviewCandidate'
    $p.operations[0].reason | Should -BeExactly 'capturedAfterStateMatches'
    $p.executable | Should -BeFalse
    $p.authoritativeProviderRead | Should -BeFalse
    foreach ($field in @('mutationAllowed','deletionAllowed','adoptionAllowed')) { $p.operations[0][$field] | Should -BeFalse }
    $p.planHash | Should -Match '^[0-9a-f]{64}$'
  }
  It 'is deterministic, does not mutate inputs, and discloses no before/current payload' {
    $original = @($journal,$evidence,$protection) | ConvertTo-Json -Depth 16 -Compress
    $first = Get-TestPlan | ConvertTo-Json -Depth 16 -Compress
    $second = Get-TestPlan | ConvertTo-Json -Depth 16 -Compress
    $first | Should -BeExactly $second
    (@($journal,$evidence,$protection) | ConvertTo-Json -Depth 16 -Compress) | Should -BeExactly $original
    $first | Should -Not -Match 'example.test|redirectUris|55555555'
  }
  It 'recognizes already-before without claiming this deployment restored it' {
    $evidence.observations[0].values=Copy-TestValue $before
    $p=Get-TestPlan; $p.operations[0].status | Should -BeExactly 'alreadyAtBefore'
    $p.operations[0].reason | Should -BeExactly 'noWriteNeededNotRestoreProof'
  }
  It 'keeps an originally no-op change non-executable' {
    $record.after=Copy-TestValue $before; $evidence.observations[0].values=Copy-TestValue $before; Update-TestEvidence
    (Get-TestPlan).operations[0].status | Should -BeExactly 'alreadyAtBefore'
  }
  It 'preserves concurrent unrelated edits instead of merging fields or subtracting arrays' {
    $evidence.observations[0].values.redirectUris += 'https://other.example.test/callback'
    (Get-TestPlan).operations[0].reason | Should -BeExactly 'concurrentChangeConflict'
  }
  It 'distinguishes explicit null and empty arrays' {
    $record.before.identifierUris=$null; $record.after.identifierUris=@('api://example'); $evidence.observations[0].values.identifierUris=@(); Update-TestEvidence
    (Get-TestPlan).operations[0].reason | Should -BeExactly 'concurrentChangeConflict'
  }
  It 'does not conflate false and missing values' {
    $evidence.observations[0].values.Remove('enableAccessTokenIssuance')
    { Get-TestPlan } | Should -Throw '*missing*'
  }
  It 'requires complete before and after projections' {
    $record.before.Remove('redirectUris'); Update-TestEvidence
    { Get-TestPlan } | Should -Throw '*missing*'
  }
  It 'rejects coercible scalar arrays and string flags' {
    $evidence.observations[0].values.redirectUris=''; {Get-TestPlan} | Should -Throw '*arrays*'
    $evidence.observations[0].values.redirectUris=@(); $evidence.observations[0].values.enableIdTokenIssuance=''
    {Get-TestPlan} | Should -Throw '*Boolean*'
  }
  It 'rejects duplicate array members and unknown sensitive metadata' {
    $evidence.observations[0].values.redirectUris=@('https://example.test/a','https://example.test/a'); {Get-TestPlan} | Should -Throw '*unique*'
    $evidence.observations[0].values=Copy-TestValue $after; $evidence.observations[0].values.clientSecret='synthetic-not-secret'; {Get-TestPlan} | Should -Throw '*unsupported*'
  }
  It 'rejects journal and tenant binding mismatches' {
    $evidence.journalHash='b'*64; {Get-TestPlan} | Should -Throw '*exact journal*'
    Update-TestEvidence; $evidence.binding.environmentName='other'; {Get-TestPlan} | Should -Throw '*binding*'
  }
  It 'rejects conflicting exact provider IDs and tuple values' {
    $evidence.observations[0].exactIds.applicationObjectId='77777777-7777-4777-8777-777777777777'; {Get-TestPlan} | Should -Throw '*identity*'
    Update-TestEvidence; $evidence.observations[0].expected.appId='77777777-7777-4777-8777-777777777777'; {Get-TestPlan} | Should -Throw '*identity*'
  }
  It 'rejects duplicate and foreign operation observations' {
    $evidence.observations += Copy-TestValue $evidence.observations[0]; {Get-TestPlan} | Should -Throw '*Duplicate*'
    $evidence.observations=@($evidence.observations[0]); $evidence.observations[0].operationId='77777777-7777-4777-8777-777777777777'; {Get-TestPlan} | Should -Throw '*one supported*'
  }
  It 'blocks missing stale absent and unknown observations without inferring restoration' {
    $saved=Copy-TestValue $evidence.observations[0]; $evidence.observations=@(); (Get-TestPlan).operations[0].reason | Should -BeExactly 'observationMissing'
    $evidence.observations=@($saved); $evidence.observations[0].observedUtc=$now.AddMinutes(-20).ToString('o'); $record.createdUtc=$now.AddMinutes(-30).ToString('o'); $record.updatedUtc=$now.AddMinutes(-25).ToString('o'); Update-TestEvidence
    (Get-TestPlan).operations[0].reason | Should -BeExactly 'observationStale'
    $evidence.observations[0].observedUtc=$now.AddMinutes(-1).ToString('o'); $evidence.observations[0].state='absent';$evidence.observations[0].values=@{}
    (Get-TestPlan).operations[0].reason | Should -BeExactly 'targetAbsentNotRestored'
    $evidence.observations[0].state='unknown'; (Get-TestPlan).operations[0].reason | Should -BeExactly 'currentStateUnknown'
  }
  It 'rejects future timestamps and observations with values while absent' {
    $evidence.observations[0].observedUtc=$now.AddSeconds(1).ToString('o'); {Get-TestPlan} | Should -Throw '*Future*'
    $evidence.observations[0].observedUtc=$now.AddMinutes(-1).ToString('o'); $evidence.observations[0].state='absent'; {Get-TestPlan} | Should -Throw '*Unavailable*'
  }
  It 'blocks observations captured before the applied checkpoint or malformed receipt chronology' {
    $evidence.observations[0].observedUtc=$now.AddMinutes(-4).ToString('o'); (Get-TestPlan).operations[0].reason | Should -BeExactly 'observationPredatesReceipt'
    $record.createdUtc=$now.ToString('o'); Update-TestEvidence; (Get-TestPlan).operations[0].reason | Should -BeExactly 'observationPredatesReceipt'
  }
  It 'blocks protected application IDs without changing their receipts' {
    $protection.appIds=@($record.expected.appId); (Get-TestPlan).operations[0].reason | Should -BeExactly 'protectedIdentity'
    $protection.appIds=@(); $protection.applicationObjectIds=@($record.expected.applicationObjectId); (Get-TestPlan).operations[0].reason | Should -BeExactly 'protectedIdentity'
  }
  It 'cannot use the setup client as an adopted application' {
    $record.expected.appId=$binding.setupClientId; Update-TestEvidence; {Get-TestPlan} | Should -Throw '*protected setup client*'
  }
  It 'blocks unresolved partial writes, deleting, deleted and conflict receipts' {
    foreach($state in @('pending','deleting','deleted','conflict')) {
      $record.state=$state; if($state -eq 'pending') {$record.exactIds=@{}} else {$record.exactIds=@{applicationObjectId=$record.expected.applicationObjectId}}
      Update-TestEvidence; (Get-TestPlan).operations[0].reason | Should -BeExactly 'receiptNotApplied'
    }
  }
  It 'refuses implicit repeated generations even with different keys and a terminal predecessor' {
    $prior=Copy-TestValue $record; $prior.operationId='77777777-7777-4777-8777-777777777777'; $prior.key='application-config:prior';$prior.state='deleted'
    $journal.records=@($prior,$record);Update-TestEvidence
    (Get-TestPlan).operations[1].reason | Should -BeExactly 'repeatedTargetNeedsGenerationContract'
    $journal.records=@($record,$prior); Update-TestEvidence
    (Get-TestPlan).operations[0].reason | Should -BeExactly 'repeatedTargetNeedsGenerationContract'
  }
  It 'blocks conflicting immutable application pairs but keeps independent targets separate' {
    foreach ($changedField in @('appId','applicationObjectId')) {
      $prior=Copy-TestValue $record; $prior.operationId='77777777-7777-4777-8777-777777777777'; $prior.key='application-config:prior'; $prior.state='deleted'
      $prior.expected[$changedField]='88888888-8888-4888-8888-888888888888'
      $prior.exactIds.applicationObjectId=$prior.expected.applicationObjectId
      $journal.records=@($record,$prior); Update-TestEvidence
      (Get-TestPlan).operations[0].reason | Should -BeExactly 'repeatedTargetNeedsGenerationContract'
    }
    $prior.expected.appId='99999999-9999-4999-8999-999999999999'
    Update-TestEvidence
    (Get-TestPlan).operations[0].status | Should -BeExactly 'reviewCandidate'
  }
  It 'binds protection and every captured observation into the plan hash' {
    $a=(Get-TestPlan).planHash; $protection.appIds=@('77777777-7777-4777-8777-777777777777'); $b=(Get-TestPlan).planHash
    $a | Should -Not -BeExactly $b
    $evidence.observations[0].observedUtc=$now.AddSeconds(-30).ToString('o'); (Get-TestPlan).planHash | Should -Not -BeExactly $b
  }
  It 'supports only an explicit AllPrincipals OAuth tuple and preserved scope snapshot' {
    $record.kind='OAuth2PermissionGrant';$record.key='grant:test';$record.expected=@{clientId='55555555-5555-4555-8555-555555555555';resourceId='66666666-6666-4666-8666-666666666666';consentType='AllPrincipals'};$record.exactIds=@{grantId='opaque-grant-id'};$record.before=@{scopes=@('User.Read')};$record.after=@{scopes=@('User.Read','Group.Read.All')}
    $evidence.observations[0].principalId=$null;$evidence.observations[0].values=Copy-TestValue $record.after;Update-TestEvidence
    (Get-TestPlan).operations[0].status | Should -BeExactly 'reviewCandidate'
    $prior=Copy-TestValue $record; $prior.operationId='77777777-7777-4777-8777-777777777777'; $prior.key='grant:prior'; $prior.state='deleted'
    $prior.expected.clientId='88888888-8888-4888-8888-888888888888'
    $journal.records=@($record,$prior); Update-TestEvidence
    (Get-TestPlan).operations[0].reason | Should -BeExactly 'repeatedTargetNeedsGenerationContract'
    $prior.state='pending'; $prior.exactIds=@{}; $prior.expected=Copy-TestValue $record.expected
    Update-TestEvidence
    (Get-TestPlan).operations[0].reason | Should -BeExactly 'repeatedTargetNeedsGenerationContract'
    $journal.records=@($record); Update-TestEvidence
    $evidence.observations[0].values.scopes+= 'Mail.Read'; (Get-TestPlan).operations[0].reason | Should -BeExactly 'concurrentChangeConflict'
    $evidence.observations[0].principalId='77777777-7777-4777-8777-777777777777'; {Get-TestPlan} | Should -Throw '*conflicting principal*'
    $evidence.observations[0].Remove('principalId'); {Get-TestPlan} | Should -Throw '*explicit provider principalId*'
  }
  It 'does not call provider commands or mutate journal files' {
    $scriptText=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../tooling/Maester-SharedRestorationPlan.psm1') -Raw
    $scriptText | Should -Not -Match '\b(?:Invoke-MgGraphRequest|Invoke-RestMethod|Invoke-WebRequest|Open-MaesterOwnershipJournal|Start-MaesterOwnedOperation|Set-MaesterOwnedOperationState|Set-Content|Out-File)\b'
    $null=Get-TestPlan
  }
}
