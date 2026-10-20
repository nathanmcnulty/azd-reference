Describe 'Maester preflight before native azd initialization (offline)' {
  BeforeAll {
    $hooksRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'components/powershell/maester-azd-hooks'
    Import-Module (Join-Path $hooksRoot 'Maester-PreProvision.psm1') -Force
    Import-Module (Join-Path $hooksRoot 'Maester-PreUp.psm1') -Force
    Import-Module (Join-Path $hooksRoot 'Maester-InfrastructureOwnership.psm1')

    # The hook, selected-environment resolver, wizard, ARM client and durable
    # receipt implementation are real. Only process/HTTP transports and terminal
    # availability/input are doubled. Unexpected transport calls always fail.
    function global:az {
      $arguments = @($args)
      $state = $global:MaesterPreflightTest
      $state.AzCalls.Add(($arguments -join ' '))
      $global:LASTEXITCODE = 0
      if ($arguments[0] -eq 'rest') {
        ($arguments -join ' ') | Should -BeLike "*--subscription $($state.Subscription)*"
        ($arguments -join ' ') | Should -BeLike "*https://management.azure.com/subscriptions/$($state.Subscription)?api-version=2022-12-01*"
        return ($state.Metadata | ConvertTo-Json -Compress)
      }
      if ($arguments[0] -eq 'account' -and $arguments[1] -eq 'get-access-token') {
        ($arguments -join ' ') | Should -BeLike "*--subscription $($state.Subscription)*"
        $arguments | Should -Not -Contain '--tenant'
        return (@{ accessToken = 'offline-token'; tenant = $state.Tenant; subscription = $state.Subscription } | ConvertTo-Json -Compress)
      }
      throw "Unexpected Azure CLI operation in offline preflight: $($arguments -join ' ')"
    }
    function global:azd {
      $arguments = @($args)
      $state = $global:MaesterPreflightTest
      $state.AzdCalls.Add(($arguments -join ' '))
      $global:LASTEXITCODE = 0
      if ($arguments[0] -eq 'version') { return 'azd version 1.23.5 (offline)' }
      if ($arguments[0] -eq 'env' -and $arguments[1] -in @('get-values', 'set')) {
        $selector = [Array]::IndexOf($arguments, '-e')
        if ($selector -lt 0) { $selector = [Array]::IndexOf($arguments, '--environment') }
        $selector | Should -BeGreaterThan 0
        $arguments[$selector + 1] | Should -BeExactly $state.EnvironmentName
        (Get-Location).Path | Should -BeExactly $state.Root
        if ($arguments[1] -eq 'get-values') {
          return ($state.Values | ConvertTo-Json -Compress)
        }
        $state.Values[[string]$arguments[2]] = [string]$arguments[3]
        $state.Events.Add("Saved:$($arguments[2])")
        # The fixture's Function option write is an adversarial boundary: simulate
        # another actor replacing the selected target before initialization.
        if ($state.ChangeAfterWizard -and $arguments[2] -eq 'VALIDATE_FUNCTION_ON_PROVISION') {
          $state.Values[$state.ChangeAfterWizard] = $state.ChangedValue
        }
        return
      }
      throw "Unexpected azd operation in offline preflight: $($arguments -join ' ')"
    }
    function Invoke-NativeAzdInitializeDouble {
      $state = $global:MaesterPreflightTest
      $state.Events.Add('NativeInitialize')
      $state.NativeInitializations++
      if (Test-Path -LiteralPath $state.ReceiptPath) {
        $state.ReceiptAtNativeInit = Get-Content -LiteralPath $state.ReceiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
      }
      # Native provider initialization creates a missing RG without our receipt.
      # The successful test must prevent this branch, not simply omit this phase.
      if ($null -eq $state.Group) {
        $state.NativeCreates++
        $state.Events.Add('NativeUnreceiptedCreate')
        $state.Group = @{ id = $state.GroupId; tags = @{ 'azd-env-name' = $state.EnvironmentName }; properties = @{ provisioningState = 'Succeeded' } }
        $state.GetStatus = 200
      }
    }
    function Invoke-OfflineAzdUp {
      param([hashtable]$Parameters)
      Invoke-MaesterPreUp @Parameters
      Invoke-NativeAzdInitializeDouble
      Invoke-MaesterPreProvision @Parameters
    }
    $savedEnvironment = @{}
    foreach ($name in @('AZURE_RESOURCE_GROUP', 'AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID', 'AZURE_LOCATION',
        'AZURE_ENV_NAME', 'AZD_NON_INTERACTIVE', 'CI', 'AUTOMATION_UPGRADE_PRESERVE_ACCESS')) {
      $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    }
  }
  AfterAll {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    Remove-Module Maester-PreUp, Maester-PreProvision, Maester-InfrastructureOwnership, Maester-UpWizard, Maester-SetupHelpers, Maester-Helpers -Force -ErrorAction SilentlyContinue
    Remove-Item function:az, function:azd
    Remove-Variable MaesterPreflightTest -Scope Global -ErrorAction SilentlyContinue
  }
  BeforeEach {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $null) }
    $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    New-Item (Join-Path $root 'infra') -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $root 'infra/main.bicep') "targetScope = 'resourceGroup'"
    $subscription = '11111111-1111-4111-8111-111111111111'
    $tenant = '22222222-2222-4222-8222-222222222222'
    $script:parameters = @{ ProjectRoot = $root; EnvironmentName = 'target'; SolutionName = 'function-app' }
    $global:MaesterPreflightTest = @{
      Root = $root; EnvironmentName = 'target'; Subscription = $subscription; Tenant = $tenant
      GroupId = "/subscriptions/$subscription/resourceGroups/rg-target"; Group = $null
      ReceiptPath = Join-Path $root '.azure/target/maester-infrastructure-ownership.json'
      GetStatus = 404; CreateStatus = 201; Interactive = $true; ChangeAfterWizard = ''; ChangedValue = ''
      NativeInitializations = 0; NativeCreates = 0; ReceiptAtNativeInit = $null
      Events = [Collections.Generic.List[string]]::new(); Prompts = [Collections.Generic.List[string]]::new()
      AzCalls = [Collections.Generic.List[string]]::new(); AzdCalls = [Collections.Generic.List[string]]::new()
      HttpCalls = [Collections.Generic.List[object]]::new()
      Metadata = @{ id = "/subscriptions/$subscription"; subscriptionId = $subscription; tenantId = $tenant; displayName = 'Selected subscription'; state = 'Enabled' }
      Values = @{
        AZURE_ENV_NAME = 'target'; AZURE_SUBSCRIPTION_ID = $subscription; AZURE_TENANT_ID = $tenant; AZURE_LOCATION = 'eastus2'
        MAESTER_SETUP_CLIENT_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; MAESTER_SETUP_ACCOUNT = 'operator@example.com'
        INCLUDE_WEB_APP = 'false'; INCLUDE_EXCHANGE = 'false'; INCLUDE_TEAMS = 'false'; INCLUDE_AZURE = 'false'; INCLUDE_ACR = 'false'
        AZDO_ORGANIZATION = 'offline-organization'; AZDO_PROJECT = 'offline-project'; AZDO_REPOSITORY = 'offline-repository'
      }
    }
    Mock Test-InteractiveWizard -ModuleName Maester-PreProvision { $global:MaesterPreflightTest.Interactive }
    Mock Test-InteractiveWizard -ModuleName Maester-UpWizard { $global:MaesterPreflightTest.Interactive }
    Mock Read-Host -ModuleName Maester-UpWizard {
      param($Prompt)
      $global:MaesterPreflightTest.Prompts.Add([string]$Prompt)
      return ''
    }
    Mock Invoke-RestMethod -ModuleName Maester-UpWizard { throw 'No external wizard network calls are permitted in this fixture.' }
    Mock Invoke-WebRequest -ModuleName Maester-InfrastructureOwnership {
      param($Method, $Uri, $Body, $Headers, $MaximumRedirection)
      $state = $global:MaesterPreflightTest
      $Uri | Should -BeExactly "https://management.azure.com$($state.GroupId)?api-version=2021-04-01"
      $Headers.Authorization | Should -BeExactly 'Bearer offline-token'
      $MaximumRedirection | Should -Be 0
      $state.HttpCalls.Add(@{ Method = $Method; Uri = $Uri })
      if ($Method -eq 'GET') {
        $state.Events.Add("GET:$($state.GetStatus)")
        $content = if ($null -eq $state.Group) { '{"error":{"code":"ResourceGroupNotFound"}}' } else { $state.Group | ConvertTo-Json -Depth 8 }
        return @{ StatusCode = $state.GetStatus; Content = $content }
      }
      if ($Method -eq 'PUT') {
        # Inspect the actual on-disk checkpoint at the moment of the only
        # permissible ARM write, rather than mocking receipt persistence.
        @($state.HttpCalls | Where-Object { $_.Method -eq 'GET' }).Count | Should -Be 1
        $state.Events | Should -Contain 'GET:404'
        $pending = Get-Content -LiteralPath $state.ReceiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
        $pending.state | Should -BeExactly 'Pending'
        $pending.preexistenceStatus | Should -Be 404
        $pending.createStatus | Should -Be 0
        $pending.binding.resourceGroupId | Should -BeExactly $state.GroupId
        $pending.binding.environmentName | Should -BeExactly $state.EnvironmentName
        $pending.sourceHash | Should -Match '^[0-9a-f]{64}$'
        $state.Events.Add('DurablePending')
        $payload = $Body | ConvertFrom-Json -AsHashtable
        $payload.location | Should -BeExactly $state.Values.AZURE_LOCATION
        $payload.tags['maester-ownership-id'] | Should -BeExactly $pending.ownershipId
        $state.Group = @{ id = $state.GroupId; tags = $payload.tags; properties = @{ provisioningState = 'Succeeded' } }
        $state.GetStatus = 200
        $state.Events.Add("PUT:$($state.CreateStatus)")
        return @{ StatusCode = $state.CreateStatus; Content = ($state.Group | ConvertTo-Json -Depth 8) }
      }
      throw "Unexpected HTTP mutation in offline preflight: $Method $Uri"
    }
  }

  It 'requires explicit project, environment and solution on <entryPoint>' -ForEach @(
    @{ entryPoint = 'Invoke-MaesterPreUp' }, @{ entryPoint = 'Invoke-MaesterPreProvision' }
  ) {
    foreach ($name in @('ProjectRoot', 'EnvironmentName', 'SolutionName')) {
      $attributes = (Get-Command $entryPoint).Parameters[$name].Attributes
      @($attributes | Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -Be 1
    }
  }

  It 'models the native provider hazard: absent groups are created without a receipt' {
    Invoke-NativeAzdInitializeDouble
    $global:MaesterPreflightTest.NativeCreates | Should -Be 1
    $global:MaesterPreflightTest.ReceiptAtNativeInit | Should -BeNullOrEmpty
    Test-Path -LiteralPath $global:MaesterPreflightTest.ReceiptPath | Should -BeFalse
  }

  It 'creates and durably receipts <solution> before native initialization, then reuses saved choices' -ForEach @(
    @{ solution = 'function-app' }, @{ solution = 'container-app-job' },
    @{ solution = 'automation-account' }, @{ solution = 'azure-devops' }
  ) {
    $parameters.SolutionName = $solution
    Invoke-MaesterPreUp @parameters
    $state = $global:MaesterPreflightTest
    $promptsAfterPreUp = $state.Prompts.ToArray()
    $promptsAfterPreUp.Count | Should -BeGreaterThan 0
    @($promptsAfterPreUp | Where-Object { $_ -like 'Include Web App?*' }).Count | Should -Be 1
    $receipt = Get-Content -LiteralPath $state.ReceiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
    $receipt.state | Should -BeExactly 'Created'
    $receipt.createStatus | Should -Be 201
    $receipt.preexistenceStatus | Should -Be 404
    $receipt.binding.solutionName | Should -BeExactly $solution
    $state.Values.AZURE_RESOURCE_GROUP | Should -BeExactly 'rg-target'

    Invoke-NativeAzdInitializeDouble
    $state.NativeCreates | Should -Be 0
    $state.ReceiptAtNativeInit.state | Should -BeExactly 'Created'
    $state.ReceiptAtNativeInit.createStatus | Should -Be 201
    $state.Events.IndexOf('GET:404') | Should -BeLessThan $state.Events.IndexOf('DurablePending')
    $state.Events.IndexOf('DurablePending') | Should -BeLessThan $state.Events.IndexOf('PUT:201')
    $state.Events.IndexOf('PUT:201') | Should -BeLessThan $state.Events.IndexOf('NativeInitialize')

    Invoke-MaesterPreProvision @parameters
    Invoke-MaesterPreProvision @parameters
    $state.Prompts.ToArray() | Should -Be $promptsAfterPreUp
    @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 1
    (Get-Content -LiteralPath $state.ReceiptPath -Raw | ConvertFrom-Json).ownershipId | Should -BeExactly $receipt.ownershipId
    @($state.AzCalls | Where-Object { $_ -like 'group *' -or $_ -like 'account set*' }).Count | Should -Be 0
  }

  It 'runs direct provision through the same real initializer without option prompts' {
    Invoke-MaesterPreProvision @parameters
    $state = $global:MaesterPreflightTest
    $state.NativeInitializations | Should -Be 0
    $state.Prompts.Count | Should -Be 0
    @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 1
    (Get-Content -LiteralPath $state.ReceiptPath -Raw | ConvertFrom-Json).state | Should -BeExactly 'Created'
    Invoke-NativeAzdInitializeDouble
    $state.NativeInitializations | Should -Be 1
    $state.NativeCreates | Should -Be 0
    $state.ReceiptAtNativeInit.state | Should -BeExactly 'Created'
    $state.ReceiptAtNativeInit.createStatus | Should -Be 201
  }

  It 'persists the approved default location before creating a group when none was saved' {
    $state = $global:MaesterPreflightTest
    $state.Values.Remove('AZURE_LOCATION')
    Invoke-OfflineAzdUp -Parameters $parameters
    $state.Values.AZURE_LOCATION | Should -BeExactly 'eastus2'
    $state.Events.IndexOf('Saved:AZURE_LOCATION') | Should -BeLessThan $state.Events.IndexOf('PUT:201')
    $state.NativeCreates | Should -Be 0
    $state.ReceiptAtNativeInit.state | Should -BeExactly 'Created'
    @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 1
  }

  It 'preserves a selected legacy resource-group name when existing is <existing>' -ForEach @(
    @{ existing = $false }, @{ existing = $true }
  ) {
    $state = $global:MaesterPreflightTest
    $state.Values.AZURE_RESOURCE_GROUP = 'maester-existing-custom-name'
    $state.GroupId = "/subscriptions/$($state.Subscription)/resourceGroups/maester-existing-custom-name"
    if ($existing) {
      $state.GetStatus = 200
      $state.Group = @{ id = $state.GroupId; tags = @{ 'azd-env-name' = 'target' }; properties = @{ provisioningState = 'Succeeded' } }
    }
    Invoke-OfflineAzdUp -Parameters $parameters
    $state.Values.AZURE_RESOURCE_GROUP | Should -BeExactly 'maester-existing-custom-name'
    $state.NativeCreates | Should -Be 0
    if ($existing) {
      Test-Path -LiteralPath $state.ReceiptPath | Should -BeFalse
      $state.ReceiptAtNativeInit | Should -BeNullOrEmpty
      @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 0
    } else {
      $state.ReceiptAtNativeInit.binding.resourceGroupId | Should -BeExactly $state.GroupId
      $state.ReceiptAtNativeInit.state | Should -BeExactly 'Created'
      @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 1
    }
  }

  It 'uses the same case-preserving default group for a mixed-case selected environment' {
    $state = $global:MaesterPreflightTest
    $parameters.EnvironmentName = 'Target-QA'
    $state.EnvironmentName = 'Target-QA'
    $state.Values.AZURE_ENV_NAME = 'Target-QA'
    $state.GroupId = "/subscriptions/$($state.Subscription)/resourceGroups/rg-Target-QA"
    $state.ReceiptPath = Join-Path $state.Root '.azure/Target-QA/maester-infrastructure-ownership.json'
    Invoke-OfflineAzdUp -Parameters $parameters
    $state.Values.AZURE_RESOURCE_GROUP | Should -BeExactly 'rg-Target-QA'
    $state.NativeCreates | Should -Be 0
    $state.ReceiptAtNativeInit.binding.environmentName | Should -BeExactly 'Target-QA'
    $state.ReceiptAtNativeInit.binding.resourceGroupId | Should -BeExactly $state.GroupId
    @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 1
  }

  It 'fails before ARM writes and native initialization for missing <field>' -ForEach @(
    @{ field = 'MAESTER_SETUP_CLIENT_ID' }, @{ field = 'MAESTER_SETUP_ACCOUNT' }
  ) {
    $state = $global:MaesterPreflightTest
    $state.Values[$field] = ''
    { Invoke-OfflineAzdUp -Parameters $parameters } | Should -Throw '*required*'
    $state.HttpCalls.Count | Should -Be 0
    $state.NativeInitializations | Should -Be 0
    Test-Path -LiteralPath $state.ReceiptPath | Should -BeFalse
  }

  It 'rejects an invalid saved setup identity before direct provisioning writes' {
    $state = $global:MaesterPreflightTest
    $state.Values.MAESTER_SETUP_CLIENT_ID = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
    { Invoke-MaesterPreProvision @parameters } | Should -Throw '*tenant-owned*'
    $state.Prompts.Count | Should -Be 0
    $state.HttpCalls.Count | Should -Be 0
  }

  It 'fails without required interactivity for <solution> before native initialization' -ForEach @(
    @{ solution = 'function-app' }, @{ solution = 'container-app-job' },
    @{ solution = 'automation-account' }, @{ solution = 'azure-devops' }
  ) {
    $parameters.SolutionName = $solution
    $state = $global:MaesterPreflightTest
    $state.Interactive = $false
    { Invoke-OfflineAzdUp -Parameters $parameters } | Should -Throw '*interactive login approval*'
    $state.HttpCalls.Count | Should -Be 0
    $state.NativeInitializations | Should -Be 0
    $state.Prompts.Count | Should -Be 0
    Test-Path -LiteralPath $state.ReceiptPath | Should -BeFalse
  }

  It 'does not let a complete saved configuration bypass direct-provision interactivity' {
    $global:MaesterPreflightTest.Interactive = $false
    { Invoke-MaesterPreProvision @parameters } | Should -Throw '*interactive login approval*'
    $global:MaesterPreflightTest.HttpCalls.Count | Should -Be 0
  }

  It 'retains saved Automation preservation choices without prompts when interactive is <interactive>' -ForEach @(
    @{ interactive = $false }, @{ interactive = $true }
  ) {
    $parameters.SolutionName = 'automation-account'
    $state = $global:MaesterPreflightTest
    $state.Values.AUTOMATION_UPGRADE_PRESERVE_ACCESS = 'true'
    $state.Values.PERMISSION_PROFILE = 'Minimal'
    $state.Values.INCLUDE_MAIL_SEND = 'false'
    $state.Values.INCLUDE_REPORT_SETTINGS_WRITE = 'false'
    $state.Interactive = $interactive
    $state.GetStatus = 200
    $state.Group = @{ id = $state.GroupId; tags = @{ 'azd-env-name' = 'target' }; properties = @{ provisioningState = 'Succeeded' } }
    Invoke-OfflineAzdUp -Parameters $parameters
    $state.Prompts.Count | Should -Be 0
    $state.NativeCreates | Should -Be 0
    $state.ReceiptAtNativeInit | Should -BeNullOrEmpty
    Test-Path -LiteralPath $state.ReceiptPath | Should -BeFalse
    @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 0
    $state.Values.PERMISSION_PROFILE | Should -BeExactly 'Minimal'
    foreach ($field in @('INCLUDE_WEB_APP', 'INCLUDE_EXCHANGE', 'INCLUDE_TEAMS', 'INCLUDE_AZURE', 'INCLUDE_MAIL_SEND', 'INCLUDE_REPORT_SETTINGS_WRITE')) {
      $state.Values[$field] | Should -BeExactly 'false'
    }
  }

  It 'does not create a fresh group by opting into noninteractive Automation preservation' {
    $parameters.SolutionName = 'automation-account'
    $state = $global:MaesterPreflightTest
    $state.Values.AUTOMATION_UPGRADE_PRESERVE_ACCESS = 'true'
    $state.Interactive = $false
    { Invoke-OfflineAzdUp -Parameters $parameters } | Should -Throw '*requires an existing resource group*'
    $state.Prompts.Count | Should -Be 0
    $state.NativeInitializations | Should -Be 0
    Test-Path -LiteralPath $state.ReceiptPath | Should -BeFalse
    @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 0
  }

  It 'does not allow an ambient preservation flag to override selected Automation configuration' {
    $parameters.SolutionName = 'automation-account'
    $state = $global:MaesterPreflightTest
    $state.Values.AUTOMATION_UPGRADE_PRESERVE_ACCESS = 'false'
    $state.Interactive = $false
    $env:AUTOMATION_UPGRADE_PRESERVE_ACCESS = 'true'
    { Invoke-OfflineAzdUp -Parameters $parameters } | Should -Throw '*differs from the selected azd environment*'
    $state.HttpCalls.Count | Should -Be 0
    $state.NativeInitializations | Should -Be 0
  }

  It 'never adopts an existing group even when its name and tags look template-created' {
    $state = $global:MaesterPreflightTest
    $state.GetStatus = 200
    $state.Group = @{ id = $state.GroupId; tags = @{ 'azd-env-name' = 'target'; workload = 'maester' }; properties = @{ provisioningState = 'Succeeded' } }
    Invoke-OfflineAzdUp -Parameters $parameters
    $state.NativeCreates | Should -Be 0
    $state.ReceiptAtNativeInit | Should -BeNullOrEmpty
    Test-Path -LiteralPath $state.ReceiptPath | Should -BeFalse
    @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 0
    (Test-MaesterInfrastructureOwnership @parameters).SafeToDelete | Should -BeFalse
  }

  It 'leaves a raced HTTP 200 create Pending and cannot promote it on a later GET' {
    $state = $global:MaesterPreflightTest
    $state.CreateStatus = 200
    { Invoke-OfflineAzdUp -Parameters $parameters } | Should -Throw '*201 Created*'
    $pending = Get-Content -LiteralPath $state.ReceiptPath -Raw
    ($pending | ConvertFrom-Json).state | Should -BeExactly 'Pending'
    $state.NativeInitializations | Should -Be 0
    { Invoke-MaesterPreProvision @parameters } | Should -Throw '*unresolved pending*'
    (Get-Content -LiteralPath $state.ReceiptPath -Raw) | Should -BeExactly $pending
    @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 1
    @($state.HttpCalls | Where-Object { $_.Method -eq 'GET' }).Count | Should -Be 1
    (Test-MaesterInfrastructureOwnership @parameters).SafeToDelete | Should -BeFalse
  }

  It 'does not create on an unknown preexistence result' {
    $state = $global:MaesterPreflightTest
    $state.GetStatus = 403
    { Invoke-OfflineAzdUp -Parameters $parameters } | Should -Throw '*prove*absent*'
    @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 0
    $state.NativeInitializations | Should -Be 0
    Test-Path -LiteralPath $state.ReceiptPath | Should -BeFalse
  }

  It 'rejects selected-environment identity mismatch instead of reading an ambient selection' {
    $state = $global:MaesterPreflightTest
    $state.Values.AZURE_ENV_NAME = 'other'
    { Invoke-OfflineAzdUp -Parameters $parameters } | Should -Throw '*identity does not match*'
    $state.AzCalls.Count | Should -Be 0
    $state.HttpCalls.Count | Should -Be 0
    $state.NativeInitializations | Should -Be 0
  }

  It 'rejects ambient <field> mismatch before any Azure operation' -ForEach @(
    @{ field = 'AZURE_ENV_NAME'; value = 'other' }
    @{ field = 'AZURE_SUBSCRIPTION_ID'; value = '44444444-4444-4444-8444-444444444444' }
    @{ field = 'AZURE_TENANT_ID'; value = '33333333-3333-4333-8333-333333333333' }
    @{ field = 'AZURE_RESOURCE_GROUP'; value = 'other-group' }
    @{ field = 'AZURE_LOCATION'; value = 'westus' }
  ) {
    [Environment]::SetEnvironmentVariable($field, $value)
    $state = $global:MaesterPreflightTest
    { Invoke-OfflineAzdUp -Parameters $parameters } | Should -Throw '*differs from the selected azd environment*'
    $state.AzCalls.Count | Should -Be 0
    $state.HttpCalls.Count | Should -Be 0
    $state.NativeInitializations | Should -Be 0
  }

  It 'rejects explicit <selector> mismatch before provisioning writes' -ForEach @(
    @{ selector = 'SubscriptionId'; value = '44444444-4444-4444-8444-444444444444' }
    @{ selector = 'TenantId'; value = '33333333-3333-4333-8333-333333333333' }
    @{ selector = 'Location'; value = 'westus' }
  ) {
    $parameters[$selector] = $value
    { Invoke-MaesterPreProvision @parameters } | Should -Throw '*differs from the selected azd environment*'
    $global:MaesterPreflightTest.HttpCalls.Count | Should -Be 0
    $global:MaesterPreflightTest.Prompts.Count | Should -Be 0
  }

  It 'revalidates changed <field> after the real wizard and before ARM creation' -ForEach @(
    @{ field = 'AZURE_RESOURCE_GROUP'; value = 'replacement-group' }
    @{ field = 'AZURE_SUBSCRIPTION_ID'; value = '44444444-4444-4444-8444-444444444444' }
    @{ field = 'AZURE_TENANT_ID'; value = '33333333-3333-4333-8333-333333333333' }
  ) {
    $state = $global:MaesterPreflightTest
    $state.ChangeAfterWizard = $field
    $state.ChangedValue = $value
    { Invoke-OfflineAzdUp -Parameters $parameters } | Should -Throw '*target differs*'
    $state.Events | Should -Contain 'Saved:MAESTER_SETUP_CLIENT_ID'
    $state.Events | Should -Not -Contain 'Saved:AZURE_TENANT_ID'
    $state.HttpCalls.Count | Should -Be 0
    $state.NativeInitializations | Should -Be 0
    Test-Path -LiteralPath $state.ReceiptPath | Should -BeFalse
  }

  It 'rejects post-wizard location drift before ARM creation or native initialization' {
    $state = $global:MaesterPreflightTest
    $state.ChangeAfterWizard = 'AZURE_LOCATION'
    $state.ChangedValue = 'westus'
    { Invoke-OfflineAzdUp -Parameters $parameters } | Should -Throw '*changed the selected deployment location*'
    $state.Events | Should -Contain 'Saved:MAESTER_SETUP_CLIENT_ID'
    $state.Events | Should -Not -Contain 'Saved:AZURE_TENANT_ID'
    $state.HttpCalls.Count | Should -Be 0
    $state.NativeInitializations | Should -Be 0
    Test-Path -LiteralPath $state.ReceiptPath | Should -BeFalse
  }

  It 'refuses a changed source hash on repeated preprovision without altering ownership evidence' {
    Invoke-MaesterPreUp @parameters
    $state = $global:MaesterPreflightTest
    $receipt = Get-Content -LiteralPath $state.ReceiptPath -Raw
    Add-Content (Join-Path $state.Root 'infra/main.bicep') '// source drift after preup'
    { Invoke-MaesterPreProvision @parameters } | Should -Throw '*sources differ*'
    (Get-Content -LiteralPath $state.ReceiptPath -Raw) | Should -BeExactly $receipt
    @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 1
  }

  It 'refuses a receipt bound to another target without adopting or creating infrastructure' {
    Invoke-MaesterPreUp @parameters
    $state = $global:MaesterPreflightTest
    $receipt = Get-Content -LiteralPath $state.ReceiptPath -Raw | ConvertFrom-Json -AsHashtable -DateKind String
    $receipt.binding.resourceGroupId = "$($state.GroupId)-other"
    $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $state.ReceiptPath
    $before = Get-Content -LiteralPath $state.ReceiptPath -Raw
    { Invoke-MaesterPreProvision @parameters } | Should -Throw '*receipt target binding differs*'
    (Get-Content -LiteralPath $state.ReceiptPath -Raw) | Should -BeExactly $before
    @($state.HttpCalls | Where-Object { $_.Method -eq 'PUT' }).Count | Should -Be 1
  }
}

Describe 'Maester native no-prompt invocation detection (offline)' {
  BeforeAll {
    $hooksRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'components/powershell/maester-azd-hooks'
    Import-Module (Join-Path $hooksRoot 'Maester-UpWizard.psm1') -Force
    function global:ps {
      $arguments = @($args)
      $state = $global:MaesterInvocationTest
      $arguments[0] | Should -BeExactly '-p'
      $arguments[2] | Should -BeExactly '-o'
      $global:LASTEXITCODE = 0
      if ($arguments[3] -eq 'command=') {
        if ([int]$arguments[1] -eq $PID) { return 'pwsh -NoProfile -File preup.ps1' }
        return $state.CommandLine
      }
      if ($arguments[3] -eq 'ppid=') {
        if ([int]$arguments[1] -eq $PID) { return '424242' }
        return '0'
      }
      throw 'Unexpected process-inspection command.'
    }
  }
  AfterAll {
    Remove-Item function:ps
    Remove-Module Maester-UpWizard, Maester-SetupHelpers, Maester-Helpers -Force -ErrorAction SilentlyContinue
    Remove-Variable MaesterInvocationTest -Scope Global -ErrorAction SilentlyContinue
  }
  BeforeEach {
    $global:MaesterInvocationTest = @{ CommandLine = 'azd up --no-prompt'; ProcessName = 'azd'; ProbeThrows = $false }
    if ($IsWindows) {
      Mock Get-CimInstance -ModuleName Maester-UpWizard {
        param($ClassName, $Filter)
        $state = $global:MaesterInvocationTest
        if ($state.ProbeThrows) { throw 'Process unavailable' }
        if ($Filter -eq "ProcessId = $PID") {
          return [pscustomobject]@{ Name = 'pwsh.exe'; CommandLine = 'pwsh -NoProfile -File preup.ps1'; ParentProcessId = 424242 }
        }
        return [pscustomobject]@{ Name = "$($state.ProcessName).exe"; CommandLine = $state.CommandLine; ParentProcessId = 0 }
      }
    } else {
      Mock Get-Process -ModuleName Maester-UpWizard {
        param($Id)
        $state = $global:MaesterInvocationTest
        if ($state.ProbeThrows) { throw 'Process unavailable' }
        return [pscustomobject]@{ ProcessName = $(if ($Id -eq $PID) { 'pwsh' } else { $state.ProcessName }) }
      }
    }
  }

  It 'recognizes a native azd ancestor with <flag>' -ForEach @(
    @{ flag = '--no-prompt' }, @{ flag = '--no-prompt=true' }, @{ flag = '--no-prompt=T' }, @{ flag = '--no-prompt=1' }
    @{ flag = '--non-interactive' }, @{ flag = '--non-interactive=true' }, @{ flag = '--non-interactive=T' }, @{ flag = '--non-interactive=1' }
  ) {
    $global:MaesterInvocationTest.CommandLine = "azd up $flag --environment target"
    InModuleScope Maester-UpWizard { Test-AzdNoPromptInvocation } | Should -BeTrue
  }

  It 'does not mistake disabled or unrelated argument <flag> for native no-prompt mode' -ForEach @(
    @{ flag = '--no-prompt=false' }, @{ flag = '--no-prompt=F' }, @{ flag = '--no-prompt=0' }
    @{ flag = '--non-interactive=false' }, @{ flag = '--non-interactive=F' }, @{ flag = '--non-interactive=0' }
    @{ flag = '--no-prompting' }, @{ flag = '--environment=--no-prompt' }
  ) {
    $global:MaesterInvocationTest.CommandLine = "azd up $flag"
    InModuleScope Maester-UpWizard { Test-AzdNoPromptInvocation } | Should -BeFalse
  }

  It 'does not treat another process mentioning no-prompt as native azd' {
    $global:MaesterInvocationTest.ProcessName = 'unrelated'
    InModuleScope Maester-UpWizard { Test-AzdNoPromptInvocation } | Should -BeFalse
  }

  It 'returns false instead of treating an unavailable process record as proof' {
    $global:MaesterInvocationTest.ProbeThrows = $true
    InModuleScope Maester-UpWizard { Test-AzdNoPromptInvocation } | Should -BeFalse
  }
}
