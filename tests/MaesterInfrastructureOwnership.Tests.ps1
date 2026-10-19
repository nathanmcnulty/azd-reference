BeforeAll {
  $repoRoot = Split-Path $PSScriptRoot -Parent
  Import-Module (Join-Path $repoRoot 'components/powershell/maester-azd-hooks/Maester-InfrastructureOwnership.psm1') -Force
}

AfterAll { Remove-Module Maester-InfrastructureOwnership -Force -ErrorAction SilentlyContinue }

Describe 'Fresh dedicated resource-group ownership' {
  BeforeEach {
    $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    New-Item (Join-Path $root 'infra') -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $root 'infra/main.bicep') 'targetScope = ''resourceGroup'''
    $script:parameters = @{ ProjectRoot = $root; EnvironmentName = 'fresh'; SolutionName = 'function-app';
      SubscriptionId = '11111111-1111-4111-8111-111111111111'; TenantId = '22222222-2222-4222-8222-222222222222' }
    $script:groupId = "/subscriptions/$($parameters.SubscriptionId)/resourceGroups/rg-fresh"
    $script:resourceId = "$groupId/providers/Microsoft.Storage/storageAccounts/stfresh"
    $script:lockId = "$resourceId/providers/Microsoft.Authorization/locks/lock-cannot-delete-storage"
    $script:receiptPath = Join-Path $root '.azure/fresh/maester-infrastructure-ownership.json'
    $global:InfrastructureTestState = @{
      Values = @{ AZURE_ENV_NAME = 'fresh'; AZURE_SUBSCRIPTION_ID = $parameters.SubscriptionId; AZURE_TENANT_ID = $parameters.TenantId;
        AZURE_LOCATION = 'eastus2'; AZURE_RESOURCE_GROUP = 'rg-fresh' }
      GroupId = $groupId; Group = $null; GetStatus = 404; CreateStatus = 201; CreateThrow = $false; WrongId = $false
      ResourceIds = @($resourceId); LockIds = @(); Requests = [Collections.Generic.List[object]]::new(); ReceiptPath = $receiptPath
      ResourceNextLink = ''; LockNextLink = ''; LockLevel = 'CanNotDelete'; DeleteThrow = $false; DeletePersists = $false; UnlistedExactLock = $false
    }
    $script:savedEnvironment = @{}
    foreach ($name in @('AZURE_ENV_NAME', 'AZURE_TENANT_ID', 'AZURE_SUBSCRIPTION_ID', 'AZURE_RESOURCE_GROUP')) {
      $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
      [Environment]::SetEnvironmentVariable($name, $null)
    }
    Mock Get-MaesterInfrastructureEnvironment -ModuleName Maester-InfrastructureOwnership { $global:InfrastructureTestState.Values }
    Mock Set-MaesterInfrastructureResourceGroup -ModuleName Maester-InfrastructureOwnership {}
    Mock Get-AzCliSubscriptionContext -ModuleName Maester-InfrastructureOwnership {}
    Mock Invoke-MaesterInfrastructureArm -ModuleName Maester-InfrastructureOwnership {
      param($Context, $Method, $Path, $Body)
      $state = $global:InfrastructureTestState
      $state.Requests.Add(@{ Method = $Method; Path = $Path })
      if ($Method -eq 'PUT') {
        $pending = Get-Content -LiteralPath $state.ReceiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
        if ($pending.state -ne 'Pending' -or $pending.createStatus -ne 0) { throw 'Create occurred before durable pending checkpoint.' }
        if ($state.CreateThrow) { throw 'Synthetic timeout' }
        $state.Group = @{ id = $(if ($state.WrongId) { "$($state.GroupId)-other" } else { $state.GroupId }); tags = $Body.tags; properties = @{ provisioningState = 'Succeeded' } }
        $state.GetStatus = 200
        return @{ StatusCode = $state.CreateStatus; Value = $state.Group }
      }
      if ($Path -match '/resources\?') { return @{ StatusCode = 200; Value = @{ value = @($state.ResourceIds | ForEach-Object { @{ id = $_ } }); nextLink = $state.ResourceNextLink } } }
      if ($Path -match '/providers/Microsoft.Authorization/locks\?') { return @{ StatusCode = 200; Value = @{ value = @($state.LockIds | ForEach-Object { @{ id = $_; properties = @{ level = $state.LockLevel } } }); nextLink = $state.LockNextLink } } }
      if ($Path -match '/providers/Microsoft.Authorization/locks/') {
        $id = $Path.Split('?')[0]
        if ($Method -eq 'DELETE') {
          $pending = Get-Content -LiteralPath $state.ReceiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
          if ($pending.lockStates[$id] -ne 'PendingRemoval') { throw 'Delete occurred before durable pending checkpoint.' }
          if ($state.DeleteThrow) { throw 'Synthetic delete timeout' }
          if (-not $state.DeletePersists) { $state.LockIds = @($state.LockIds | Where-Object { $_ -ine $id }) }
          return @{ StatusCode = 204; Value = $null }
        }
        if ($id -iin $state.LockIds -or $state.UnlistedExactLock) { return @{ StatusCode = 200; Value = @{ id = $id; properties = @{ level = $state.LockLevel } } } }
        return @{ StatusCode = 404; Value = $null }
      }
      return @{ StatusCode = $state.GetStatus; Value = $state.Group }
    }
    function Complete-TestInfrastructure {
      param([switch]$WithLocks)
      Initialize-MaesterInfrastructureOwnership @parameters | Out-Null
      $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
      $global:InfrastructureTestState.Values.MAESTER_INFRASTRUCTURE_OWNERSHIP_ID = $receipt.ownershipId
      $ids = @($resourceId)
      $locks = @()
      if ($WithLocks) { $ids += $lockId; $locks += $lockId; $global:InfrastructureTestState.LockIds = @($lockId) }
      $global:InfrastructureTestState.Values.MAESTER_OWNED_RESOURCE_IDS = ConvertTo-Json -InputObject $ids -Compress
      $global:InfrastructureTestState.Values.MAESTER_OWNED_LOCK_IDS = ConvertTo-Json -InputObject $locks -Compress
      Complete-MaesterInfrastructureOwnership @parameters
    }
  }
  AfterEach {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    Remove-Variable InfrastructureTestState -Scope Global -ErrorAction SilentlyContinue
  }

  It 'checkpoints absence and exact HTTP 201 before owning a newly created group' {
    $result = Initialize-MaesterInfrastructureOwnership @parameters
    $result.Owned | Should -BeTrue
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
    $receipt.state | Should -BeExactly 'Created'
    $receipt.createStatus | Should -Be 201
    $receipt.preexistenceStatus | Should -Be 404
    $receipt.binding.resourceGroupId | Should -BeExactly $groupId
    $global:InfrastructureTestState.Group.tags['azd-env-name'] | Should -BeExactly 'fresh'
    $receipt.Keys | Should -Not -Contain 'setupClientId'
    (Test-MaesterInfrastructureOwnership @parameters).SafeToDelete | Should -BeFalse
  }

  It 'never adopts or PUTs a previously existing group even with template-looking names and tags' {
    $global:InfrastructureTestState.GetStatus = 200
    $global:InfrastructureTestState.Group = @{ id = $groupId; tags = @{ workload = 'maester'; environment = 'fresh' } }
    (Initialize-MaesterInfrastructureOwnership @parameters).Owned | Should -BeFalse
    Test-Path -LiteralPath $receiptPath | Should -BeFalse
    Should -Invoke Invoke-MaesterInfrastructureArm -ModuleName Maester-InfrastructureOwnership -Times 0 -Exactly -ParameterFilter { $Method -eq 'PUT' }
    (Test-MaesterInfrastructureOwnership @parameters).SafeToDelete | Should -BeFalse
  }

  It 'does not create after unknown preexistence HTTP <status>' -ForEach @(@{ status = 400 }, @{ status = 401 }, @{ status = 403 }, @{ status = 429 }, @{ status = 500 }) {
    $global:InfrastructureTestState.GetStatus = $status
    { Initialize-MaesterInfrastructureOwnership @parameters } | Should -Throw '*prove*absent*'
    Should -Invoke Invoke-MaesterInfrastructureArm -ModuleName Maester-InfrastructureOwnership -Times 0 -Exactly -ParameterFilter { $Method -eq 'PUT' }
  }

  It 'leaves HTTP <status> create outcomes pending and refuses a query-based recovery' -ForEach @(@{ status = 200 }, @{ status = 202 }, @{ status = 204 }, @{ status = 409 }, @{ status = 500 }) {
    $global:InfrastructureTestState.CreateStatus = $status
    { Initialize-MaesterInfrastructureOwnership @parameters } | Should -Throw '*201 Created*'
    (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json).state | Should -BeExactly 'Pending'
    { Initialize-MaesterInfrastructureOwnership @parameters } | Should -Throw '*unresolved pending*'
    { Complete-MaesterInfrastructureOwnership @parameters } | Should -Throw '*Unresolved*'
    (Test-MaesterInfrastructureOwnership @parameters).SafeToDelete | Should -BeFalse
    Should -Invoke Invoke-MaesterInfrastructureArm -ModuleName Maester-InfrastructureOwnership -Times 1 -Exactly -ParameterFilter { $Method -eq 'PUT' }
  }

  It 'leaves a timeout or wrong returned resource ID unresolved' -ForEach @(@{ timeout = $true; wrong = $false }, @{ timeout = $false; wrong = $true }) {
    $global:InfrastructureTestState.CreateThrow = $timeout
    $global:InfrastructureTestState.WrongId = $wrong
    { Initialize-MaesterInfrastructureOwnership @parameters } | Should -Throw
    (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json).state | Should -BeExactly 'Pending'
    (Test-MaesterInfrastructureOwnership @parameters).SafeToDelete | Should -BeFalse
  }

  It 'does not create when the pending checkpoint fails' {
    Mock Write-MaesterInfrastructureReceipt -ModuleName Maester-InfrastructureOwnership { throw 'Synthetic disk failure' }
    { Initialize-MaesterInfrastructureOwnership @parameters } | Should -Throw '*disk failure*'
    Should -Invoke Invoke-MaesterInfrastructureArm -ModuleName Maester-InfrastructureOwnership -Times 0 -Exactly -ParameterFilter { $Method -eq 'PUT' }
  }

  It 'retains pending evidence when the 201 checkpoint fails' {
    Mock Write-MaesterInfrastructureReceipt -ModuleName Maester-InfrastructureOwnership {
      param($Session, $Receipt)
      if ($Receipt.state -eq 'Created') { throw 'Synthetic final checkpoint failure' }
      $Receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Session.path
    }
    { Initialize-MaesterInfrastructureOwnership @parameters } | Should -Throw '*checkpoint failure*'
    (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json).state | Should -BeExactly 'Pending'
  }

  It 'completes only exact declared outputs and allows matching live resources' {
    Complete-TestInfrastructure
    $result = Test-MaesterInfrastructureOwnership @parameters
    $result.SafeToDelete | Should -BeTrue
    $result.OwnedResourceIds | Should -Be @($resourceId)
    $result.DeletionWarning | Should -Match 'all their child resources and data'
    (Resolve-MaesterInfrastructureBinding @parameters).ResourceGroupId | Should -BeExactly $groupId
  }

  It 'preserves proven Automation runbook and schedule IDs across ordinary and runtime-only repeat outputs' -ForEach @(@{ runtimeOnly = $false }, @{ runtimeOnly = $true }) {
    $parameters.SolutionName = 'automation-account'
    Initialize-MaesterInfrastructureOwnership @parameters | Out-Null
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
    $accountId = "$groupId/providers/Microsoft.Automation/automationAccounts/aa-fresh"
    $runtimeId = "$accountId/runtimeEnvironments/maester-pwsh76"
    $runbookId = "$accountId/runbooks/maester-runbook"
    $scheduleId = "$accountId/schedules/maester-weekly-sunday"
    $original = @($resourceId, $accountId, $runtimeId, $runbookId, $scheduleId, $lockId)
    $global:InfrastructureTestState.Values.MAESTER_INFRASTRUCTURE_OWNERSHIP_ID = $receipt.ownershipId
    $global:InfrastructureTestState.Values.MAESTER_OWNED_RESOURCE_IDS = ConvertTo-Json -InputObject $original -Compress
    $global:InfrastructureTestState.Values.MAESTER_OWNED_LOCK_IDS = ConvertTo-Json -InputObject @($lockId) -Compress
    Complete-MaesterInfrastructureOwnership @parameters
    $subset = @($resourceId, $accountId, $runtimeId, $lockId); $subsetLocks = @($lockId)
    if ($runtimeOnly) { $subset = @($runtimeId); $subsetLocks = @() }
    $global:InfrastructureTestState.Values.MAESTER_OWNED_RESOURCE_IDS = ConvertTo-Json -InputObject $subset -Compress
    $global:InfrastructureTestState.Values.MAESTER_OWNED_LOCK_IDS = ConvertTo-Json -InputObject $subsetLocks -Compress
    Complete-MaesterInfrastructureOwnership @parameters
    $after = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
    $after.resourceIds | Should -Be $original
    $after.lockIds | Should -Be @($lockId)
    $after.lockStates[$lockId] | Should -BeExactly 'Present'
  }

  It 'rejects duplicate or unproven repeat-output IDs while retaining the original receipt' -ForEach @(@{ addedId = 'foreign' }, @{ addedId = 'duplicate' }) {
    Complete-TestInfrastructure
    $before = Get-Content -LiteralPath $receiptPath -Raw
    $ids = if ($addedId -eq 'foreign') { @($resourceId, "$groupId/providers/Microsoft.Storage/storageAccounts/foreign") } else { @($resourceId, $resourceId) }
    $global:InfrastructureTestState.Values.MAESTER_OWNED_RESOURCE_IDS = ConvertTo-Json -InputObject $ids -Compress
    { Complete-MaesterInfrastructureOwnership @parameters } | Should -Throw
    (Get-Content -LiteralPath $receiptPath -Raw) | Should -BeExactly $before
  }

  It 'durably marks external setup before it starts and never resets the marker on repeated completion' {
    Complete-TestInfrastructure
    (Resolve-MaesterInfrastructureBinding @parameters).ExternalSetupStarted | Should -BeFalse
    (Register-MaesterExternalSetupStarted @parameters).Tracked | Should -BeTrue
    (Resolve-MaesterInfrastructureBinding @parameters).ExternalSetupStarted | Should -BeTrue
    Complete-MaesterInfrastructureOwnership @parameters
    (Resolve-MaesterInfrastructureBinding @parameters).ExternalSetupStarted | Should -BeTrue
    Register-MaesterExternalSetupStarted @parameters | Out-Null
    (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String).externalSetupStarted | Should -BeTrue
  }

  It 'reports untracked legacy setup without manufacturing infrastructure ownership' {
    (Register-MaesterExternalSetupStarted @parameters).Tracked | Should -BeFalse
    Test-Path -LiteralPath $receiptPath | Should -BeFalse
    (Test-MaesterInfrastructureOwnership @parameters).SafeToDelete | Should -BeFalse
  }

  It 'blocks external setup when its started checkpoint fails or infrastructure is incomplete' {
    Initialize-MaesterInfrastructureOwnership @parameters | Out-Null
    { Register-MaesterExternalSetupStarted @parameters } | Should -Throw '*Complete infrastructure ownership*'
    Complete-TestInfrastructure
    Mock Write-MaesterInfrastructureReceipt -ModuleName Maester-InfrastructureOwnership { throw 'Synthetic marker checkpoint failure' }
    { Register-MaesterExternalSetupStarted @parameters } | Should -Throw '*marker checkpoint failure*'
    (Resolve-MaesterInfrastructureBinding @parameters).ExternalSetupStarted | Should -BeFalse
  }

  It 'rejects a matching-name foreign resource without ever blessing the ARM inventory' {
    Complete-TestInfrastructure
    $global:InfrastructureTestState.ResourceIds += "$groupId/providers/Microsoft.Storage/storageAccounts/stmaesterforeign"
    $result = Test-MaesterInfrastructureOwnership @parameters
    $result.SafeToDelete | Should -BeFalse
    $result.SafeToUnlock | Should -BeFalse
    $result.BlockingReason | Should -Match 'Unowned resource'
    (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json).resourceIds | Should -Be @($resourceId)
  }

  It 'rejects foreign locks, changed lock levels, and incomplete inventories' -ForEach @(
    @{ mutation = 'foreignLock' }, @{ mutation = 'lockLevel' }, @{ mutation = 'resourcePage' }, @{ mutation = 'lockPage' }
  ) {
    Complete-TestInfrastructure -WithLocks
    switch ($mutation) {
      foreignLock { $global:InfrastructureTestState.LockIds += "$groupId/providers/Microsoft.Authorization/locks/lock-cannot-delete-storage" }
      lockLevel { $global:InfrastructureTestState.LockLevel = 'ReadOnly' }
      resourcePage { $global:InfrastructureTestState.ResourceNextLink = 'https://management.azure.com/next' }
      lockPage { $global:InfrastructureTestState.LockNextLink = 'https://management.azure.com/next' }
    }
    (Test-MaesterInfrastructureOwnership @parameters).SafeToUnlock | Should -BeFalse
  }

  It 'requires exact separate lock approval and records each verified removal' {
    Complete-TestInfrastructure -WithLocks
    $plan = Test-MaesterInfrastructureOwnership @parameters
    $plan.SafeToDelete | Should -BeFalse
    $plan.SafeToUnlock | Should -BeTrue
    { Unlock-MaesterInfrastructureLocks @parameters -ApprovedPlanHash ('0' * 64) } | Should -Throw '*plan changed*'
    Should -Invoke Invoke-MaesterInfrastructureArm -ModuleName Maester-InfrastructureOwnership -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    (Unlock-MaesterInfrastructureLocks @parameters -ApprovedPlanHash $plan.PlanHash).SafeToDelete | Should -BeTrue
    (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String).lockStates[$lockId] | Should -BeExactly 'Removed'
    Should -Invoke Invoke-MaesterInfrastructureArm -ModuleName Maester-InfrastructureOwnership -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
  }

  It 'does not delete an exact-GET lock absent from the approved list or previously removed' -ForEach @(@{ lockState = 'Present' }, @{ lockState = 'Removed' }) {
    Complete-TestInfrastructure -WithLocks
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
    $receipt.lockStates[$lockId] = $lockState
    $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath
    $global:InfrastructureTestState.LockIds = @()
    $global:InfrastructureTestState.UnlistedExactLock = $true
    $plan = Test-MaesterInfrastructureOwnership @parameters
    $plan.PresentOwnedLockIds.Count | Should -Be 0
    { Unlock-MaesterInfrastructureLocks @parameters -ApprovedPlanHash $plan.PlanHash } | Should -Throw '*not present in the approved*'
    Should -Invoke Invoke-MaesterInfrastructureArm -ModuleName Maester-InfrastructureOwnership -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String).lockStates[$lockId] | Should -BeExactly $lockState
  }

  It 'keeps unknown lock removal pending and safely reconciles exact absence' {
    Complete-TestInfrastructure -WithLocks
    $plan = Test-MaesterInfrastructureOwnership @parameters
    $global:InfrastructureTestState.DeleteThrow = $true
    { Unlock-MaesterInfrastructureLocks @parameters -ApprovedPlanHash $plan.PlanHash } | Should -Throw '*timeout*'
    (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String).lockStates[$lockId] | Should -BeExactly 'PendingRemoval'
    $global:InfrastructureTestState.LockIds = @()
    $retry = Test-MaesterInfrastructureOwnership @parameters
    $retry.SafeToDelete | Should -BeFalse
    (Unlock-MaesterInfrastructureLocks @parameters -ApprovedPlanHash $retry.PlanHash).SafeToDelete | Should -BeTrue
    Should -Invoke Invoke-MaesterInfrastructureArm -ModuleName Maester-InfrastructureOwnership -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
  }

  It 'does not clear pending or removed lock history by repeating completion' -ForEach @(@{ state = 'PendingRemoval' }, @{ state = 'Removed' }) {
    Complete-TestInfrastructure -WithLocks
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
    $receipt.lockStates[$lockId] = $state
    $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath
    Complete-MaesterInfrastructureOwnership @parameters
    (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String).lockStates[$lockId] | Should -BeExactly $state
    if ($state -eq 'PendingRemoval') {
      $global:InfrastructureTestState.LockIds = @()
      (Test-MaesterInfrastructureOwnership @parameters).SafeToDelete | Should -BeFalse
    } else {
      (Test-MaesterInfrastructureOwnership @parameters).BlockingReason | Should -Match 'recreated'
    }
  }

  It 'never reports an accepted delete as absence when the lock remains live' {
    Complete-TestInfrastructure -WithLocks
    $plan = Test-MaesterInfrastructureOwnership @parameters
    $global:InfrastructureTestState.DeletePersists = $true
    { Unlock-MaesterInfrastructureLocks @parameters -ApprovedPlanHash $plan.PlanHash } | Should -Throw '*not verified absent*'
    (Test-MaesterInfrastructureOwnership @parameters).SafeToDelete | Should -BeFalse
  }

  It 'rejects a recreated RG or a recreated removed lock' {
    Complete-TestInfrastructure -WithLocks
    $plan = Test-MaesterInfrastructureOwnership @parameters
    Unlock-MaesterInfrastructureLocks @parameters -ApprovedPlanHash $plan.PlanHash | Out-Null
    $global:InfrastructureTestState.LockIds = @($lockId)
    (Test-MaesterInfrastructureOwnership @parameters).BlockingReason | Should -Match 'recreated'
    $global:InfrastructureTestState.Group.tags['maester-ownership-id'] = [guid]::NewGuid().ToString()
    (Test-MaesterInfrastructureOwnership @parameters).SafeToDelete | Should -BeFalse
  }

  It 'rejects stale outputs and a changed source binding' {
    Initialize-MaesterInfrastructureOwnership @parameters | Out-Null
    $global:InfrastructureTestState.Values.MAESTER_INFRASTRUCTURE_OWNERSHIP_ID = [guid]::NewGuid().ToString()
    { Complete-MaesterInfrastructureOwnership @parameters } | Should -Throw '*incarnation*'
    Add-Content (Join-Path $root 'infra/main.bicep') '// changed'
    { Complete-MaesterInfrastructureOwnership @parameters } | Should -Throw '*source changed*'
  }

  It 'rejects out-of-group or duplicate declared IDs and unexpected fields' -ForEach @(@{ mutation = 'foreign' }, @{ mutation = 'duplicate' }, @{ mutation = 'field' }) {
    Complete-TestInfrastructure
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
    switch ($mutation) {
      foreign { $receipt.resourceIds += '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/other/providers/Microsoft.Storage/storageAccounts/stforeign' }
      duplicate { $receipt.resourceIds += $resourceId }
      field { $receipt['accessToken'] = 'must-not-be-accepted' }
    }
    $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath
    (Test-MaesterInfrastructureOwnership @parameters).SafeToDelete | Should -BeFalse
  }

  It 'rejects target retargeting and unsafe environment paths before any ARM mutation' {
    $parameters.ResourceGroupName = 'other'
    { Initialize-MaesterInfrastructureOwnership @parameters } | Should -Throw '*differs*'
    $parameters.EnvironmentName = '../other'
    { Initialize-MaesterInfrastructureOwnership @parameters } | Should -Throw '*safe*'
    Should -Invoke Invoke-MaesterInfrastructureArm -ModuleName Maester-InfrastructureOwnership -Times 0 -Exactly
  }

  It 'holds an exclusive lifecycle lock and rejects a symlink receipt' {
    Complete-TestInfrastructure
    $lock = [IO.FileStream]::new("$receiptPath.lock", [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { (Test-MaesterInfrastructureOwnership @parameters).BlockingReason | Should -Match 'lifecycle lock' }
    finally { $lock.Dispose() }
    if (-not $IsWindows) {
      $target = Join-Path $root 'elsewhere.json'
      Move-Item -LiteralPath $receiptPath -Destination $target
      New-Item -ItemType SymbolicLink -Path $receiptPath -Target $target | Out-Null
      (Test-MaesterInfrastructureOwnership @parameters).BlockingReason | Should -Match 'symbolic links'
    }
  }
}

Describe 'Infrastructure ARM transport preserves exact HTTP outcomes' {
  BeforeEach {
    Mock Get-AzCliAccessToken -ModuleName Maester-InfrastructureOwnership { 'synthetic-not-a-real-token' }
    Mock Invoke-WebRequest -ModuleName Maester-InfrastructureOwnership { @{ StatusCode = 201; Content = '{"id":"exact"}' } }
  }
  It 'uses the exact ARM host, no redirects, and the actual status code without a create-only claim' {
    InModuleScope Maester-InfrastructureOwnership {
      $context = @{ binding = @{ resourceGroupId = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test';
        subscriptionId = '11111111-1111-4111-8111-111111111111'; tenantId = '22222222-2222-4222-8222-222222222222' } }
      $result = Invoke-MaesterInfrastructureArm $context PUT "$($context.binding.resourceGroupId)?api-version=2021-04-01" @{ location = 'eastus2' }
      $result.StatusCode | Should -Be 201
      $result.Value.id | Should -BeExactly 'exact'
      Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
        $Method -eq 'PUT' -and $Uri -eq 'https://management.azure.com/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test?api-version=2021-04-01' -and
        $MaximumRedirection -eq 0 -and $SkipHttpErrorCheck -and -not $Headers.ContainsKey('If-None-Match')
      }
    }
  }
  It 'rejects malformed JSON, transport uncertainty, or missing token without exposing credentials' -ForEach @(
    @{ failure = 'json' }, @{ failure = 'transport' }, @{ failure = 'token' }
  ) {
    if ($failure -eq 'json') { Mock Invoke-WebRequest -ModuleName Maester-InfrastructureOwnership { @{ StatusCode = 201; Content = 'not-json' } } }
    if ($failure -eq 'transport') { Mock Invoke-WebRequest -ModuleName Maester-InfrastructureOwnership { throw 'remote failure synthetic-not-a-real-token' } }
    if ($failure -eq 'token') { Mock Get-AzCliAccessToken -ModuleName Maester-InfrastructureOwnership { $null } }
    InModuleScope Maester-InfrastructureOwnership {
      $context = @{ binding = @{ resourceGroupId = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test';
        subscriptionId = '11111111-1111-4111-8111-111111111111'; tenantId = '22222222-2222-4222-8222-222222222222' } }
      try { Invoke-MaesterInfrastructureArm $context PUT "$($context.binding.resourceGroupId)?api-version=2021-04-01" @{ location = 'eastus2' }; throw 'Expected transport rejection.' }
      catch { $_.Exception.Message | Should -Not -Match 'synthetic-not-a-real-token'; $_.Exception.Message | Should -Not -Be 'Expected transport rejection.' }
    }
    if ($failure -eq 'token') { Should -Invoke Invoke-WebRequest -ModuleName Maester-InfrastructureOwnership -Times 0 -Exactly }
  }
}

Describe 'Infrastructure selected-environment working directory' {
  It 'pins both azd read and write to ProjectRoot and restores the calling directory' {
    $root = Join-Path $TestDrive 'project with spaces'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    InModuleScope Maester-InfrastructureOwnership -Parameters @{ ProjectRoot = $root } {
      param($ProjectRoot)
      $before = (Get-Location).Path
      $global:InfrastructureSeenLocations = [Collections.Generic.List[string]]::new()
      function azd {
        $global:InfrastructureSeenLocations.Add((Get-Location).Path)
        $global:LASTEXITCODE = 0
        if ($args[1] -eq 'get-values') { '{"AZURE_ENV_NAME":"fresh"}' }
      }
      try {
        (Get-MaesterInfrastructureEnvironment 'fresh' $ProjectRoot).AZURE_ENV_NAME | Should -BeExactly 'fresh'
        Set-MaesterInfrastructureResourceGroup 'fresh' 'rg-fresh' $ProjectRoot
        $global:InfrastructureSeenLocations.ToArray() | Should -Be @($ProjectRoot, $ProjectRoot)
        (Get-Location).Path | Should -BeExactly $before
      } finally { Remove-Variable InfrastructureSeenLocations -Scope Global -ErrorAction SilentlyContinue }
    }
  }
}
