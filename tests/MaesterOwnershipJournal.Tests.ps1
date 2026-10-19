BeforeAll {
  $modulePath = Join-Path $PSScriptRoot '../components/powershell/maester-azd-hooks/Maester-OwnershipJournal.psm1'
  Import-Module $modulePath -Force
}

AfterAll { Remove-Module Maester-OwnershipJournal -Force -ErrorAction SilentlyContinue }

Describe 'Durable environment-bound Maester ownership journal' {
  BeforeEach {
    $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $binding = @{
      environmentName = 'journal-test'
      tenantId = '11111111-1111-4111-8111-111111111111'
      subscriptionId = '22222222-2222-4222-8222-222222222222'
      solutionName = 'maester'
      resourceGroupId = '/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/maester-journal-test'
      setupClientId = '33333333-3333-4333-8333-333333333333'
    }
    $expected = @{
      principalId = '44444444-4444-4444-8444-444444444444'
      resourceId = '55555555-5555-4555-8555-555555555555'
      appRoleId = '66666666-6666-4666-8666-666666666666'
    }
    $parameters = @{ Key = 'graph-role:principal:resource:role'; Kind = 'GraphAppRoleAssignment'; PlanHash = 'a' * 64; Ownership = 'Created'; Expected = $expected }
    $path = Join-Path $root '.azure/journal-test/maester-setup-ownership.json'
    $session = $null
  }

  AfterEach { if ($null -ne $session) { $session.Dispose() } }

  It 'creates only the fixed selected-environment file and reopens persisted entries' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    [IO.File]::Exists($path) | Should -BeTrue
    $operation = Start-MaesterOwnedOperation -Session $session @parameters
    (Get-MaesterOwnershipJournal $session).records[0].state | Should -BeExactly 'pending'
    Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ assignmentId = 'opaque_response-123' } | Out-Null
    $session.Dispose()
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding -RequireExisting
    $journal = Get-MaesterOwnershipJournal $session
    $journal.records.Count | Should -Be 1
    $journal.records[0].exactIds.assignmentId | Should -BeExactly 'opaque_response-123'
    $journal.records[0].state | Should -BeExactly 'applied'
  }

  It 'normalizes GUID casing without changing exact provider IDs or names' {
    $binding.tenantId = 'ABCDEFAB-1111-4111-8111-111111111111'
    $expected.principalId = 'ABCDEFAB-4444-4444-8444-444444444444'
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $operation = Start-MaesterOwnedOperation -Session $session @parameters
    Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ assignmentId = 'ABCD_opaque-CaSe' } | Out-Null
    $journal = Get-MaesterOwnershipJournal $session
    $journal.binding.tenantId | Should -BeExactly 'abcdefab-1111-4111-8111-111111111111'
    $journal.records[0].expected.principalId | Should -BeExactly 'abcdefab-4444-4444-8444-444444444444'
    $journal.records[0].exactIds.assignmentId | Should -BeExactly 'ABCD_opaque-CaSe'
  }

  It 'preserves earlier receipts and byte-identical no-op reads and reopen' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $first = Start-MaesterOwnedOperation -Session $session @parameters
    Complete-MaesterOwnedOperation -Session $session -OperationId $first.operationId -ExactIds @{ assignmentId = 'first-id' } | Out-Null
    $before = [IO.File]::ReadAllText($path)
    Get-MaesterOwnershipJournal $session | Out-Null
    $session.Dispose()
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    [IO.File]::ReadAllText($path) | Should -BeExactly $before
    $parameters.Key = 'graph-role:other'
    $expected.appRoleId = '77777777-7777-4777-8777-777777777777'
    Start-MaesterOwnedOperation -Session $session @parameters | Out-Null
    $journal = Get-MaesterOwnershipJournal $session
    $journal.records.Count | Should -Be 2
    $journal.records[0].exactIds.assignmentId | Should -BeExactly 'first-id'
  }

  It 'keeps caller mutations from changing captured binding or durable metadata' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $record = Start-MaesterOwnedOperation -Session $session @parameters
    $binding.setupClientId = $expected.principalId
    $record.expected.principalId = $expected.resourceId
    $expected.principalId = $expected.resourceId
    $journal = Get-MaesterOwnershipJournal $session
    $journal.binding.setupClientId | Should -BeExactly '33333333-3333-4333-8333-333333333333'
    $journal.records[0].expected.principalId | Should -BeExactly '44444444-4444-4444-8444-444444444444'
  }

  It 'fails closed on a different <Field> binding' -ForEach @(
    @{ Field = 'tenantId'; Value = '77777777-7777-4777-8777-777777777777' }
    @{ Field = 'subscriptionId'; Value = '77777777-7777-4777-8777-777777777777' }
    @{ Field = 'setupClientId'; Value = '77777777-7777-4777-8777-777777777777' }
    @{ Field = 'solutionName'; Value = 'another-solution' }
    @{ Field = 'resourceGroupId'; Value = '/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/other' }
  ) {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $session.Dispose()
    $binding[$Field] = $Value
    { Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding } | Should -Throw '*binding*'
  }

  It 'does not initialize a missing journal for cleanup' {
    { Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding -RequireExisting } | Should -Throw '*missing*'
    [IO.File]::Exists($path) | Should -BeFalse
  }

  It 'rejects environment traversal and a mismatched ARM resource-group binding' {
    $binding.environmentName = '../other'
    { Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding } | Should -Throw '*unsafe*'
    $binding.environmentName = 'journal-test'
    $binding.resourceGroupId = '/subscriptions/77777777-7777-4777-8777-777777777777/resourceGroups/other'
    { Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding } | Should -Throw '*subscription*'
    { Open-MaesterOwnershipJournal -ProjectRoot "$root/../$([IO.Path]::GetFileName($root))" -Binding $binding } | Should -Throw
  }

  It 'rejects symbolic links rather than following them to another environment' {
    $target = Join-Path $root 'foreign'
    [IO.Directory]::CreateDirectory($target) | Out-Null
    [IO.Directory]::CreateSymbolicLink((Join-Path $root '.azure'), $target) | Out-Null
    { Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding } | Should -Throw '*reparse*'
    @(Get-ChildItem $target -Force).Count | Should -Be 0
  }

  It 'rejects unsupported schema, unknown fields, duplicate JSON keys and oversized files' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $original = [IO.File]::ReadAllText($path)
    [IO.File]::WriteAllText($path, $original.Replace('"schemaVersion":"1.0"', '"schemaVersion":"9.0"'))
    { Get-MaesterOwnershipJournal $session } | Should -Throw '*schema*'
    [IO.File]::WriteAllText($path, $original.Replace('"schemaVersion":"1.0"', '"schemaVersion":"1.0","token":"secret"'))
    { Get-MaesterOwnershipJournal $session } | Should -Throw '*unsupported field*'
    [IO.File]::WriteAllText($path, $original.Replace('"schemaVersion":"1.0"', '"schemaVersion":"1.0","schemaVersion":"1.0"'))
    { Get-MaesterOwnershipJournal $session } | Should -Throw '*duplicate*'
    [IO.File]::WriteAllText($path, (' ' * (2MB + 1)))
    { Get-MaesterOwnershipJournal $session } | Should -Throw '*size*'
  }

  It 'rejects credential fields and unexpected nested metadata before pending is persisted' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $original = [IO.File]::ReadAllText($path)
    $expected.accessToken = 'not-a-real-token'
    { Start-MaesterOwnedOperation -Session $session @parameters } | Should -Throw '*unsupported field*'
    $expected.Remove('accessToken')
    $expected.principalId = @{ value = 'nested-credential' }
    { Start-MaesterOwnedOperation -Session $session @parameters } | Should -Throw '*GUID*'
    [IO.File]::ReadAllText($path) | Should -BeExactly $original
  }

  It 'blocks pending replay by key and by exact tuple under another key' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    Start-MaesterOwnedOperation -Session $session @parameters | Out-Null
    { Start-MaesterOwnedOperation -Session $session @parameters } | Should -Throw '*do not repeat*'
    $parameters.Key = 'a-different-key'
    { Start-MaesterOwnedOperation -Session $session @parameters } | Should -Throw '*same active*'
    $expected.roleValue = 'Different.Optional.Label'
    { Start-MaesterOwnedOperation -Session $session @parameters } | Should -Throw '*same active*'
    (Get-MaesterOwnershipJournal $session).records.Count | Should -Be 1
  }

  It 'holds an exclusive lifecycle lock until disposed and rejects a closed session' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    { Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding -LockTimeoutMilliseconds 20 } | Should -Throw '*lifecycle lock*'
    $session.Dispose()
    { Get-MaesterOwnershipJournal $session } | Should -Throw '*open ownership journal session*'
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding -LockTimeoutMilliseconds 20
    (Get-MaesterOwnershipJournal $session).records.Count | Should -Be 0
  }

  It 'preserves old bytes if pending persistence fails before the remote write' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $original = [IO.File]::ReadAllText($path)
    Mock -ModuleName Maester-OwnershipJournal Move-MaesterJournalCheckpoint { throw 'injected checkpoint failure' }
    $remoteCalled = $false
    { Start-MaesterOwnedOperation -Session $session @parameters; $remoteCalled = $true } | Should -Throw '*injected*'
    $remoteCalled | Should -BeFalse
    [IO.File]::ReadAllText($path) | Should -BeExactly $original
    @(Get-ChildItem ([IO.Path]::GetDirectoryName($path)) -Filter '*.tmp').Count | Should -Be 0
  }

  It 'retains pending intent and earlier applied entries if response checkpoint fails' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $first = Start-MaesterOwnedOperation -Session $session @parameters
    Complete-MaesterOwnedOperation -Session $session -OperationId $first.operationId -ExactIds @{ assignmentId = 'first-id' } | Out-Null
    $parameters.Key = 'second-key'; $expected.appRoleId = '77777777-7777-4777-8777-777777777777'
    $second = Start-MaesterOwnedOperation -Session $session @parameters
    $before = [IO.File]::ReadAllText($path)
    Mock -ModuleName Maester-OwnershipJournal Move-MaesterJournalCheckpoint { throw 'injected checkpoint failure' }
    { Complete-MaesterOwnedOperation -Session $session -OperationId $second.operationId -ExactIds @{ assignmentId = 'second-id' } } | Should -Throw '*injected*'
    [IO.File]::ReadAllText($path) | Should -BeExactly $before
    $journal = Get-MaesterOwnershipJournal $session
    $journal.records[0].state | Should -BeExactly 'applied'
    $journal.records[1].state | Should -BeExactly 'pending'
    { Start-MaesterOwnedOperation -Session $session @parameters } | Should -Throw '*do not repeat*'
  }

  It 'retains a completed checkpoint even when the process sees failure after atomic rename' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $operation = Start-MaesterOwnedOperation -Session $session @parameters
    Mock -ModuleName Maester-OwnershipJournal Move-MaesterJournalCheckpoint {
      param($Source, $Destination)
      [IO.File]::Move($Source, $Destination, $true)
      throw 'injected failure after rename'
    }
    { Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ assignmentId = 'response-id' } } | Should -Throw '*after rename*'
    (Get-MaesterOwnershipJournal $session).records[0].exactIds.assignmentId | Should -BeExactly 'response-id'
    { Start-MaesterOwnedOperation -Session $session @parameters } | Should -Throw '*do not repeat*'
  }

  It 'requires deleting checkpoint before deleted and retains terminal receipts' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $operation = Start-MaesterOwnedOperation -Session $session @parameters
    { Set-MaesterOwnedOperationState -Session $session -OperationId $operation.operationId -State deleting } | Should -Throw '*transition*'
    Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ assignmentId = 'id' } | Out-Null
    { Set-MaesterOwnedOperationState -Session $session -OperationId $operation.operationId -State deleted } | Should -Throw '*transition*'
    Set-MaesterOwnedOperationState -Session $session -OperationId $operation.operationId -State deleting | Out-Null
    (Get-MaesterOwnershipJournal $session).records[0].state | Should -BeExactly 'deleting'
    Set-MaesterOwnedOperationState -Session $session -OperationId $operation.operationId -State deleted | Out-Null
    $journal = Get-MaesterOwnershipJournal $session
    $journal.records.Count | Should -Be 1
    $journal.records[0].state | Should -BeExactly 'deleted'
    $journal.records[0].exactIds.assignmentId | Should -BeExactly 'id'
  }

  It 'persists unresolved conflicts without promoting unknown writes to applied' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $operation = Start-MaesterOwnedOperation -Session $session @parameters
    Set-MaesterOwnedOperationState -Session $session -OperationId $operation.operationId -State conflict | Out-Null
    { Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ assignmentId = 'guessed-id' } } | Should -Throw '*original pending*'
    { Set-MaesterOwnedOperationState -Session $session -OperationId $operation.operationId -State deleted } | Should -Throw '*transition*'
    (Get-MaesterOwnershipJournal $session).records[0].state | Should -BeExactly 'conflict'
  }

  It 'rejects malformed opaque response IDs and preserves pending intent' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $operation = Start-MaesterOwnedOperation -Session $session @parameters
    foreach ($id in @('../another', 'id?token=secret', 'id%2Fnext', 'id/next')) {
      { Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ assignmentId = $id } } | Should -Throw '*opaque*'
    }
    (Get-MaesterOwnershipJournal $session).records[0].state | Should -BeExactly 'pending'
  }

  It 'protects the original setup client and accepts only allowlisted mutation snapshots' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $mutation = @{ Session = $session; Key = 'app-mutation'; Kind = 'ApplicationConfiguration'; Ownership = 'Mutation'; PlanHash = 'b' * 64; Expected = @{ applicationObjectId = $expected.principalId; appId = $binding.setupClientId }; Before = @{ groupMembershipClaims = $null }; After = @{ groupMembershipClaims = 'SecurityGroup' } }
    { Start-MaesterOwnedOperation @mutation } | Should -Throw '*protected setup client*'
    $mutation.Expected.appId = $expected.resourceId
    $operation = Start-MaesterOwnedOperation @mutation
    Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ applicationObjectId = $expected.principalId } | Out-Null
    (Get-MaesterOwnershipJournal $session).records[0].before.groupMembershipClaims | Should -BeNullOrEmpty
  }

  It 'supports explicit foreign subscription grants while binding exact assignment IDs to scope' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $scope = '/subscriptions/77777777-7777-4777-8777-777777777777'
    $id = "$scope/providers/Microsoft.Authorization/roleAssignments/88888888-8888-4888-8888-888888888888"
    $azure = @{ Session = $session; Key = 'azure-role'; Kind = 'AzureRoleAssignment'; Ownership = 'Created'; PlanHash = 'c' * 64; Expected = @{ principalId = $expected.principalId; scope = $scope; roleDefinitionId = "$scope/providers/Microsoft.Authorization/roleDefinitions/99999999-9999-4999-8999-999999999999"; roleAssignmentId = $id } }
    $operation = Start-MaesterOwnedOperation @azure
    Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ roleAssignmentId = $id } | Out-Null
    (Get-MaesterOwnershipJournal $session).records[0].exactIds.roleAssignmentId | Should -BeExactly $id
    $azure.Key = 'wrong-scope'
    $azure.Expected.roleAssignmentId = $id.Replace('77777777-7777-4777-8777-777777777777', $binding.subscriptionId)
    $azure.Expected.principalId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    { Start-MaesterOwnedOperation @azure } | Should -Throw '*outside its explicit scope*'
  }

  It 'requires an exact owned parent before accepting parent-covered mutations' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $parent = Start-MaesterOwnedOperation -Session $session -Key 'app' -Kind EntraApplication -PlanHash ('a' * 64) -Ownership Created -Expected @{ purpose = 'EasyAuth'; displayName = 'test' }
    $mutation = @{ Session = $session; Key = 'app-config'; Kind = 'ApplicationConfiguration'; Ownership = 'Mutation'; PlanHash = 'b' * 64; Expected = @{ applicationObjectId = $expected.principalId; appId = $expected.resourceId }; CoveredByOperationId = $parent.operationId }
    { Start-MaesterOwnedOperation @mutation } | Should -Throw '*applied owned creation*'
    Complete-MaesterOwnedOperation -Session $session -OperationId $parent.operationId -ExactIds @{ applicationObjectId = $expected.principalId; appId = $expected.resourceId } | Out-Null
    $child = Start-MaesterOwnedOperation @mutation
    { Set-MaesterOwnedOperationState -Session $session -OperationId $parent.operationId -State deleting } | Should -Throw '*unresolved covered mutation*'
    Complete-MaesterOwnedOperation -Session $session -OperationId $child.operationId -ExactIds @{ applicationObjectId = $expected.principalId } | Out-Null
    (Get-MaesterOwnershipJournal $session).records[1].coveredByOperationId | Should -BeExactly $parent.operationId
    Set-MaesterOwnedOperationState -Session $session -OperationId $parent.operationId -State conflict | Out-Null
    (Get-MaesterOwnershipJournal $session).records[0].state | Should -BeExactly 'conflict'
    (Get-MaesterOwnershipJournal $session).records[1].coveredByOperationId | Should -BeExactly $parent.operationId
  }

  It 'binds ADO authorization aliases to the exact owned <ResourceType> parent' -ForEach @(
    @{ ResourceType = 'repository'; ParentKind = 'AdoRepository'; IdName = 'repositoryId'; Composite = $true }
    @{ ResourceType = 'endpoint'; ParentKind = 'AdoServiceConnection'; IdName = 'serviceConnectionId'; Composite = $false }
  ) {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $parentExpected = @{ organizationId = $expected.principalId; projectId = $expected.resourceId }
    $parent = Start-MaesterOwnedOperation -Session $session -Key 'parent' -Kind $ParentKind -PlanHash ('b' * 64) -Ownership Created -Expected $parentExpected
    $parentIds = @{}; $parentIds[$IdName] = $expected.appRoleId
    Complete-MaesterOwnedOperation -Session $session -OperationId $parent.operationId -ExactIds $parentIds | Out-Null
    $resourceId = if ($Composite) { "$($expected.resourceId).$($expected.appRoleId)" } else { $expected.appRoleId }
    $childExpected = @{ organizationId = $expected.principalId; projectId = $expected.resourceId; resourceType = $ResourceType; resourceId = $resourceId }
    $child = Start-MaesterOwnedOperation -Session $session -Key 'authorization' -Kind AdoPipelineAuthorization -PlanHash ('b' * 64) -Ownership Mutation -Expected $childExpected -CoveredByOperationId $parent.operationId -Before @{allPipelinesAuthorized=$false} -After @{allPipelinesAuthorized=$true}
    Complete-MaesterOwnedOperation -Session $session -OperationId $child.operationId -ExactIds @{resourceId=$resourceId} | Out-Null
    (Get-MaesterOwnershipJournal $session).records[1].coveredByOperationId | Should -BeExactly $parent.operationId
  }

  It 'rejects an ADO alias that names another project despite a matching parent GUID' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $parent = Start-MaesterOwnedOperation -Session $session -Key 'parent' -Kind AdoRepository -PlanHash ('b' * 64) -Ownership Created -Expected @{organizationId=$expected.principalId;projectId=$expected.resourceId}
    Complete-MaesterOwnedOperation -Session $session -OperationId $parent.operationId -ExactIds @{repositoryId=$expected.appRoleId} | Out-Null
    { Start-MaesterOwnedOperation -Session $session -Key 'authorization' -Kind AdoPipelineAuthorization -PlanHash ('b' * 64) -Ownership Mutation -Expected @{organizationId=$expected.principalId;projectId='77777777-7777-4777-8777-777777777777';resourceType='repository';resourceId="77777777-7777-4777-8777-777777777777.$($expected.appRoleId)"} -CoveredByOperationId $parent.operationId -Before @{allPipelinesAuthorized=$false} -After @{allPipelinesAuthorized=$true} } | Should -Throw '*exact owned parent*'
    (Get-MaesterOwnershipJournal $session).records.Count | Should -Be 1
  }

  It 'does not accept a matching appId as coverage for a different application object' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $parent = Start-MaesterOwnedOperation -Session $session -Key 'app' -Kind EntraApplication -PlanHash ('b' * 64) -Ownership Created -Expected @{purpose='EasyAuth';displayName='owned'}
    Complete-MaesterOwnedOperation -Session $session -OperationId $parent.operationId -ExactIds @{applicationObjectId=$expected.principalId;appId=$expected.resourceId} | Out-Null
    { Start-MaesterOwnedOperation -Session $session -Key 'wrong-app' -Kind ApplicationConfiguration -Ownership Mutation -PlanHash ('b' * 64) -Expected @{applicationObjectId=$expected.appRoleId;appId=$expected.resourceId} -CoveredByOperationId $parent.operationId } | Should -Throw '*exact owned parent*'
    (Get-MaesterOwnershipJournal $session).records.Count | Should -Be 1
  }

  It 'retains only sanitized creation configuration for exact owned applications' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $configuration = @{redirectUris=@('https://owned.azurewebsites.net/.auth/login/aad/callback');identifierUris=@();groupMembershipClaims='SecurityGroup';enableIdTokenIssuance=$true;enableAccessTokenIssuance=$false;signInAudience='AzureADMyOrg'}
    $operation = Start-MaesterOwnedOperation -Session $session -Key 'configured-app' -Kind EntraApplication -PlanHash ('b' * 64) -Ownership Created -Expected @{purpose='EasyAuth';displayName='owned'} -After $configuration
    Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{applicationObjectId=$expected.principalId;appId=$expected.resourceId} | Out-Null
    $record = (Get-MaesterOwnershipJournal $session).records[0]
    $record.after.signInAudience | Should -BeExactly 'AzureADMyOrg'
    $record.after.redirectUris | Should -BeExactly $configuration.redirectUris
    $configuration.passwordCredentials = @('never-persist')
    { Start-MaesterOwnedOperation -Session $session -Key 'unsafe-app' -Kind EntraApplication -PlanHash ('b' * 64) -Ownership Created -Expected @{purpose='Runtime';displayName='unsafe'} -After $configuration } | Should -Throw '*unsupported field*'
    $configuration.Remove('passwordCredentials')
    $configuration.signInAudience = 'Unrecognized'
    { Start-MaesterOwnedOperation -Session $session -Key 'invalid-audience' -Kind EntraApplication -PlanHash ('b' * 64) -Ownership Created -Expected @{purpose='Runtime';displayName='unsafe'} -After $configuration } | Should -Throw '*enum*'
  }

  It 'allows additive pipeline revision readback but never replacement of acknowledged IDs' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $operation = Start-MaesterOwnedOperation -Session $session -Key 'pipeline' -Kind AdoPipeline -PlanHash ('d' * 64) -Ownership Created -Expected @{ organizationId = $expected.principalId; projectId = $expected.resourceId; repositoryId = $expected.appRoleId; yamlPath = '/.pipelines/maester.yml'; branch = 'refs/heads/main' }
    Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ pipelineId = '12' } | Out-Null
    Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ pipelineId = '12'; pipelineRevision = '2' } | Out-Null
    { Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ pipelineId = '13'; pipelineRevision = '2' } } | Should -Throw '*cannot be replaced*'
    { Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ pipelineId = '12' } } | Should -Throw '*cannot be replaced*'
    (Get-MaesterOwnershipJournal $session).records[0].exactIds.pipelineRevision | Should -BeExactly '2'
  }

  It 'retains optional immutable runtime and ADO anchors on reopen' {
    $binding.runtimeResourceId = "$($binding.resourceGroupId)/providers/Microsoft.Automation/automationAccounts/runtime"
    $binding.runtimePrincipalId = $expected.principalId
    $binding.adoOrganizationUrl = 'https://dev.azure.com/example'
    $binding.organizationId = $expected.resourceId
    $binding.projectId = $expected.appRoleId
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $session.Dispose()
    $binding.runtimePrincipalId = '77777777-7777-4777-8777-777777777777'
    { Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding } | Should -Throw '*binding*'
  }

  It 'accepts composite ADO repository permission IDs and rejects a different project' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $composite = "$($expected.resourceId).$($expected.appRoleId)"
    $operation = Start-MaesterOwnedOperation -Session $session -Key 'repository-auth' -Kind AdoPipelineAuthorization -Ownership Mutation -PlanHash ('e' * 64) -Expected @{ organizationId = $expected.principalId; projectId = $expected.resourceId; resourceType = 'repository'; resourceId = $composite } -Before @{ allPipelinesAuthorized = $false } -After @{ allPipelinesAuthorized = $true }
    Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ resourceId = $composite } | Out-Null
    { Start-MaesterOwnedOperation -Session $session -Key 'wrong-project' -Kind AdoPipelineAuthorization -Ownership Mutation -PlanHash ('e' * 64) -Expected @{ organizationId = $expected.principalId; projectId = $expected.appRoleId; resourceType = 'repository'; resourceId = $composite } -Before @{ allPipelinesAuthorized = $false } -After @{ allPipelinesAuthorized = $true } } | Should -Throw '*exact project*'
  }

  It 'accepts safe opaque Exchange identities without storing provider result blobs' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $operation = Start-MaesterOwnedOperation -Session $session -Key 'exchange-role' -Kind ExchangeRoleAssignment -Ownership Created -PlanHash ('f' * 64) -Expected @{ servicePrincipalId = $expected.principalId; roleName = 'View-Only Configuration' }
    Complete-MaesterOwnedOperation -Session $session -OperationId $operation.operationId -ExactIds @{ exchangeRoleAssignmentId = 'Example Organization\Maester View-Only' } | Out-Null
    (Get-MaesterOwnershipJournal $session).records[0].exactIds.exchangeRoleAssignmentId | Should -BeExactly 'Example Organization\Maester View-Only'
  }

  It 'enforces the lifecycle lock in another PowerShell process' {
    $session = Open-MaesterOwnershipJournal -ProjectRoot $root -Binding $binding
    $scriptPath = Join-Path $root 'lock-check.ps1'
    $bindingPath = Join-Path $root 'binding.json'
    $binding | ConvertTo-Json | Set-Content $bindingPath
    @'
param($ModulePath, $Root, $BindingPath)
Import-Module $ModulePath -Force
$binding = Get-Content $BindingPath -Raw | ConvertFrom-Json -AsHashtable
try { $session = Open-MaesterOwnershipJournal -ProjectRoot $Root -Binding $binding -LockTimeoutMilliseconds 50; $session.Dispose(); exit 10 }
catch { if ($_.Exception.Message -notlike '*lifecycle lock*') { exit 11 }; exit 0 }
'@ | Set-Content $scriptPath
    $info = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh'))
    $info.UseShellExecute = $false
    foreach ($argument in @('-NoProfile', '-File', $scriptPath, $modulePath, $root, $bindingPath)) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($info)
    try {
      $process.WaitForExit(10000) | Should -BeTrue
      $process.ExitCode | Should -Be 0
    } finally { if (-not $process.HasExited) { $process.Kill() }; $process.Dispose() }
  }
}
