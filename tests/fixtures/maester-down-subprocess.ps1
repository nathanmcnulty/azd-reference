# Real canonical modules and entrypoint; only external provider boundaries are fixtures.
param(
  [Parameter(Mandatory)][string]$RepositoryRoot,
  [Parameter(Mandatory)][string]$ProjectRoot,
  [Parameter(Mandatory)][ValidateSet('PreInteractive','PreInteractiveUnlocked','PrePlan','PreNoJournal','PreDeleted','PreEmpty','PreExplicitHash','PostInteractiveUnavailable','PostMissingContext','PostFreshLogin','PostExistingContext','PostModuleExisting','PostTerminal')][string]$Scenario,
  [ValidateSet('automation-account','function-app','container-app-job','azure-devops')][string]$SolutionName = 'automation-account'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$hookRoot = Join-Path $RepositoryRoot 'components/powershell/maester-azd-hooks'
$tenant='11111111-1111-4111-8111-111111111111'; $subscription='22222222-2222-4222-8222-222222222222'
$client='33333333-3333-4333-8333-333333333333'; $principal='44444444-4444-4444-8444-444444444444'
$groupId="/subscriptions/$subscription/resourceGroups/rg-down-child"
$provider=switch ($SolutionName) {
  'function-app' { 'Microsoft.Web/sites' }
  'container-app-job' { 'Microsoft.App/jobs' }
  default { 'Microsoft.Automation/automationAccounts' }
}
$runtimeId="$groupId/providers/$provider/runtime"; $lockId="$runtimeId/providers/Microsoft.Authorization/locks/owned-lock"
$global:DownChildState=@{
  Tenant=$tenant; Client=$client; Principal=$principal; GroupId=$groupId; RuntimeId=$runtimeId; Group=$null; ArmPresent=$false
  Locks=@($lockId); LockDeletes=0; GraphDeletes=0; Connections=@(); Context=$null
  Values=@{AZURE_ENV_NAME='down-child';AZURE_TENANT_ID=$tenant;AZURE_SUBSCRIPTION_ID=$subscription;AZURE_RESOURCE_GROUP='rg-down-child';AZURE_LOCATION='eastus2'}
}
foreach ($name in @('AZURE_ENV_NAME','AZURE_TENANT_ID','AZURE_SUBSCRIPTION_ID','AZURE_RESOURCE_GROUP','SECURITY_GROUP_OBJECT_ID','EASY_AUTH_SECURITY_GROUP_OBJECT_ID')) { [Environment]::SetEnvironmentVariable($name,$null) }
$env:MAESTER_SETUP_CLIENT_ID=$client; $env:MAESTER_SETUP_ACCOUNT='admin@example.com'
[IO.Directory]::CreateDirectory((Join-Path $ProjectRoot 'infra')) | Out-Null
Set-Content (Join-Path $ProjectRoot 'infra/main.bicep') "targetScope = 'resourceGroup'"
Import-Module (Join-Path $hookRoot 'Maester-InfrastructureOwnership.psm1')
Import-Module (Join-Path $hookRoot 'Maester-PreDownCleanup.psm1')
Import-Module (Join-Path $hookRoot 'Maester-OwnershipJournal.psm1')

# Provider requests are replaced within the actual modules. Ownership, planning,
# authentication coordination, approvals, state transitions and entrypoint remain real.
& (Get-Module Maester-InfrastructureOwnership) {
  function script:Get-MaesterInfrastructureEnvironment { param($EnvironmentName,$ProjectRoot) return $global:DownChildState.Values }
  function script:Set-MaesterInfrastructureResourceGroup { param($EnvironmentName,$ResourceGroupName,$ProjectRoot) }
  function script:Get-AzCliSubscriptionContext { param($SubscriptionId,$TenantId) }
  function script:Invoke-MaesterInfrastructureArm {
    param($Context,$Method,$Path,$Body)
    $s=$global:DownChildState
    if ($Method -eq 'PUT') { $s.Group=@{id=$s.GroupId;tags=$Body.tags;properties=@{provisioningState='Succeeded'}}; $s.ArmPresent=$true; return @{StatusCode=201;Value=$s.Group} }
    if ($Path -match '/resources\?') { return @{StatusCode=200;Value=@{value=@(@{id=$s.RuntimeId})}} }
    if ($Path -match '/providers/Microsoft.Authorization/locks\?') { return @{StatusCode=200;Value=@{value=@($s.Locks | ForEach-Object { @{id=$_;properties=@{level='CanNotDelete'}} })}} }
    if ($Path -match '/providers/Microsoft.Authorization/locks/') {
      $id=$Path.Split('?')[0]
      if ($Method -eq 'DELETE') { $s.LockDeletes++; $s.Locks=@($s.Locks | Where-Object {$_ -ne $id}); return @{StatusCode=204;Value=$null} }
      if ($id -in $s.Locks) { return @{StatusCode=200;Value=@{id=$id;properties=@{level='CanNotDelete'}}} }
      return @{StatusCode=404;Value=$null}
    }
    if ($Method -ne 'GET') { throw 'Unexpected infrastructure provider request.' }
    return @{StatusCode=if($s.ArmPresent){200}else{404};Value=$s.Group}
  }
}
& (Get-Module Maester-PreDownCleanup) {
  function script:Get-AzCliSubscriptionContext { param($SubscriptionId,$TenantId) }
  function script:Invoke-MaesterCleanupArmRequest {
    param($Binding,$Method,$ResourceId,$ApiVersion,$Query)
    if ($Method -ne 'GET') { throw 'Unexpected ARM authorization mutation.' }
    $s=$global:DownChildState
    return @{StatusCode=if($s.ArmPresent){200}else{404};Value=@{id=$ResourceId}}
  }
}
function global:Get-MgEnvironment { [pscustomobject]@{Name='Global'} }
function global:Get-MgContext { $global:DownChildState.Context }
function New-ChildGraphContext {
  param([string[]]$Scopes)
  return [pscustomobject]@{TenantId=$tenant;ClientId=$client;Account='admin@example.com';Environment='Global';AuthType='Delegated';ContextScope='Process';Scopes=$Scopes}
}
function global:Connect-MgGraph {
  [CmdletBinding()]
  param($TenantId,$ClientId,$Environment,$Scopes,$ContextScope,$ClientTimeout,[switch]$NoWelcome)
  $s=$global:DownChildState
  $s.Connections+=,@{TenantId=$TenantId;ClientId=$ClientId;Environment=$Environment;Scopes=@($Scopes);ContextScope=$ContextScope;Parameters=@($PSBoundParameters.Keys)}
  $s.Context=New-ChildGraphContext $Scopes
}
Add-Type 'public class MaesterDownFixtureNotFound : System.Exception { public int ResponseStatusCode { get { return 404; } } }'
function global:Invoke-MgGraphRequest {
  [CmdletBinding()]
  param($Method,$Uri,$OutputType,$Body,$ContentType)
  $s=$global:DownChildState
  if ($Method -ne 'GET') { $s.GraphDeletes++; throw 'Unexpected Graph mutation.' }
  if ($Uri -match '/organization\?') { return [pscustomobject]@{value=@([pscustomobject]@{id=$s.Tenant})} }
  if ($Uri -match '/servicePrincipals\?') { return [pscustomobject]@{value=@([pscustomobject]@{id='55555555-5555-4555-8555-555555555555';appId=$s.Client;appOwnerOrganizationId=$s.Tenant})} }
  if ($Uri -match '/applications\?') { return [pscustomobject]@{value=@([pscustomobject]@{id='66666666-6666-4666-8666-666666666666';appId=$s.Client;signInAudience='AzureADMyOrg';isFallbackPublicClient=$true;publicClient=@{redirectUris=@('http://localhost')}})} }
  if ($Uri -match '/servicePrincipals/44444444-4444-4444-8444-444444444444/appRoleAssignments/owned-role$') { throw [MaesterDownFixtureNotFound]::new() }
  throw "Unexpected Graph fixture route: $Uri"
}

$infraArgs=@{ProjectRoot=$ProjectRoot;EnvironmentName='down-child';SolutionName=$SolutionName;TenantId=$tenant;SubscriptionId=$subscription;ResourceGroupName='rg-down-child'}
Initialize-MaesterInfrastructureOwnership @infraArgs | Out-Null
$receiptPath=Join-Path $ProjectRoot '.azure/down-child/maester-infrastructure-ownership.json'
$receipt=Get-Content $receiptPath -Raw | ConvertFrom-Json
$s=$global:DownChildState
$s.Values.MAESTER_INFRASTRUCTURE_OWNERSHIP_ID=$receipt.ownershipId
if ($Scenario -in @('PreInteractiveUnlocked','PreNoJournal','PreDeleted','PreEmpty')) { $s.Locks=@() }
$s.Values.MAESTER_OWNED_RESOURCE_IDS=ConvertTo-Json -InputObject (@($runtimeId)+@($s.Locks)) -Compress
$s.Values.MAESTER_OWNED_LOCK_IDS=ConvertTo-Json -InputObject @($s.Locks) -Compress
Complete-MaesterInfrastructureOwnership @infraArgs | Out-Null
$binding=@{environmentName='down-child';solutionName=$SolutionName;tenantId=$tenant;subscriptionId=$subscription;resourceGroupId=$groupId;setupClientId=$client;runtimeResourceId=$runtimeId;runtimePrincipalId=$principal}
if ($Scenario -ne 'PreNoJournal') {
  Register-MaesterExternalSetupStarted @infraArgs | Out-Null
  $session=Open-MaesterOwnershipJournal -ProjectRoot $ProjectRoot -Binding $binding
  try {
    if ($Scenario -ne 'PreEmpty') {
      $record=Start-MaesterOwnedOperation -Session $session -Key 'owned-role' -Kind GraphAppRoleAssignment -Ownership Created -PlanHash ('a'*64) -Expected @{principalId=$principal;resourceId='77777777-7777-4777-8777-777777777777';appRoleId='88888888-8888-4888-8888-888888888888'}
      Complete-MaesterOwnedOperation -Session $session -OperationId $record.operationId -ExactIds @{assignmentId='owned-role'} | Out-Null
      if ($Scenario -in @('PreDeleted','PostTerminal')) {
        Set-MaesterOwnedOperationState -Session $session -OperationId $record.operationId -State deleting | Out-Null
        Set-MaesterOwnedOperationState -Session $session -OperationId $record.operationId -State deleted | Out-Null
      }
    }
  } finally { $session.Dispose() }
}
$journalPath=Join-Path $ProjectRoot '.azure/down-child/maester-setup-ownership.json'
$journalBefore=if(Test-Path $journalPath){[IO.File]::ReadAllText($journalPath)}else{''}
$scopes=@('Application.Read.All','AppRoleAssignment.ReadWrite.All','Directory.Read.All')
if ($Scenario -in @('PostExistingContext','PostModuleExisting')) { $s.Context=New-ChildGraphContext $scopes }
$initialContextAbsent=$null -eq $s.Context
if ($Scenario.StartsWith('Post')) { $s.ArmPresent=$false }
$options=@{}
if ($Scenario -in @('PreInteractive','PreInteractiveUnlocked','PrePlan','PreNoJournal','PreDeleted','PreEmpty','PostInteractiveUnavailable','PostTerminal')) { $options.InteractiveConsent=$true }
if ($Scenario -eq 'PrePlan' -or $Scenario -in @('PostMissingContext','PostFreshLogin','PostExistingContext')) { $options.PlanOnly=$true }
if ($Scenario -eq 'PostFreshLogin') { $options.AllowInteractiveGraphLogin=$true }
if ($Scenario -in @('PreInteractive','PreExplicitHash')) {
  $plan=Test-MaesterOwnedCleanupPreDown -ProjectRoot $ProjectRoot -Binding $binding -PlanOnly
  $options.ApprovedUnlockPlanHash=$plan.UnlockPlanHash
}
$success=$false; $message=''; $result=$null
try {
  if ($Scenario -eq 'PostModuleExisting') {
    $plan=Get-MaesterOwnedCleanupPlan -ProjectRoot $ProjectRoot -Binding $binding
    $result=Invoke-MaesterOwnedCleanupPostDown -ProjectRoot $ProjectRoot -Binding $binding -ApprovedPlanHash $plan.PlanHash
  } else {
    $phase=if($Scenario.StartsWith('Pre')){'PreDown'}else{'PostDown'}
    $result=& (Join-Path $hookRoot 'Invoke-MaesterDown.ps1') -Phase $phase @infraArgs @options
  }
  $success=$true
} catch { $message=$_.Exception.Message }
$journalAfter=if(Test-Path $journalPath){[IO.File]::ReadAllText($journalPath)}else{''}
$states=@()
if ($journalAfter) { $states=@(($journalAfter | ConvertFrom-Json).records | ForEach-Object state) }
$report=@{
  Success=$success;Message=$message;InputRedirected=[Console]::IsInputRedirected;CiSelected=($env:CI -eq 'true');NoninteractiveSelected=($env:AZD_NON_INTERACTIVE -eq 'true')
  InitialContextAbsent=$initialContextAbsent;Connections=@($s.Connections);LockDeletes=$s.LockDeletes;GraphDeletes=$s.GraphDeletes;JournalUnchanged=($journalBefore -ceq $journalAfter);States=$states
  Entries=@();Completed=$false
}
if ($result -is [Collections.IDictionary]) {
  if ($result.Contains('Entries')) { $report.Entries=@($result.Entries) }
  if ($result.Contains('Completed')) { $report.Completed=[bool]$result.Completed }
}
$report | ConvertTo-Json -Depth 12 -Compress | Write-Output
