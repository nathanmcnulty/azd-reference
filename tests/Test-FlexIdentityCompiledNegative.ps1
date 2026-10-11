#Requires -Version 7.6
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PimTemplatePath,[Parameter(Mandatory)][string]$RiskTemplatePath,[Parameter(Mandatory)][string]$LegacyTemplatePath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$assert=Join-Path $PSScriptRoot 'Assert-FlexIdentityCompiledTemplate.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($assert,[ref]$tokens,[ref]$errors)
$argumentParser=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-FlexArmArguments'},$true))[0]
. ([scriptblock]::Create($argumentParser.Extent.Text))
function Invoke-FlexGuard([string]$Expression,[string]$Name,[bool]$Identity){
 if($Expression -ceq "parameters('identityOnlyStorage')"){return $Identity}
 if($Expression -in @("lambdaVariables('setting').key","lambdaVariables('setting').name")){return $Name}
 if($Expression.StartsWith("'")){return $Expression.Substring(1,$Expression.Length-2)}
 $operation=$Expression.Substring(0,$Expression.IndexOf('('));$args=Get-FlexArmArguments $Expression
 $values=@(foreach($arg in $args){Invoke-FlexGuard $arg $Name $Identity})
 switch -CaseSensitive ($operation){
  'not' {return !$values[0]}
  'or' {return $values[0] -or $values[1]}
  'and' {return $values[0] -and $values[1]}
  'equals' {return [string]$values[0] -ceq [string]$values[1]}
  'toLower' {return ([string]$values[0]).ToLowerInvariant()}
  'replace' {return ([string]$values[0]).Replace([string]$values[1],[string]$values[2])}
  'startsWith' {return ([string]$values[0]).StartsWith([string]$values[1],[StringComparison]::OrdinalIgnoreCase)}
  default {throw 'Unsupported compiled predicate operation'}
 }
}
$t=Get-Content $PimTemplatePath -Raw|ConvertFrom-Json -AsHashtable -DateKind String -Depth 100
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('flex-negative-'+[guid]::NewGuid().ToString('N'))
$scratch=[IO.Path]::GetFullPath($scratch)
if(!$scratch.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture directory'}
New-Item -ItemType Directory $scratch|Out-Null
try {
 foreach($shape in @('Pim','Risk')){& $assert -Shape $shape -TemplatePath $(if($shape -eq 'Pim'){$PimTemplatePath}else{$RiskTemplatePath})|Out-Null}
 $legacy=Get-Content $LegacyTemplatePath -Raw|ConvertFrom-Json -AsHashtable -DateKind String -Depth 100
 $new=$t.resources[0].properties.template
 $oldSite=@($legacy.resources|Where-Object type -eq 'Microsoft.Web/sites')[0]
 $newSite=@($new.resources|Where-Object type -eq 'Microsoft.Web/sites')[0]
 $appArgs=Get-FlexArmArguments $newSite.properties.siteConfig.appSettings
 $storageBranches=Get-FlexArmArguments $appArgs[2]
 $legacyEntries=Get-FlexArmArguments $storageBranches[2]
 $entries=@(foreach($entry in $legacyEntries){$entryArgs=Get-FlexArmArguments $entry;$valueBranches=Get-FlexArmArguments $entryArgs[3];$entryArgs[3]=$valueBranches[2];'createObject('+($entryArgs -join ', ')+')'})
 $genericEntries=Get-FlexArmArguments $appArgs[3]
 $entries+=$genericEntries
 $defaultApp='[concat('+ $appArgs[0]+', '+$appArgs[1]+', createArray('+($entries -join ', ')+'))]'
 if($defaultApp -cne $oldSite.properties.siteConfig.appSettings){throw 'Default app settings parity failed'}
 foreach($old in $legacy.resources){
  $current=@($new.resources|Where-Object {$_.type -ceq $old.type -and $_.name -ceq $old.name})[0]
  $copy=$current|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable -DateKind String -Depth 100
  if($copy.type -eq 'Microsoft.Storage/storageAccounts'){$copy.properties.allowSharedKeyAccess=$true}
  if($copy.type -eq 'Microsoft.Authorization/roleAssignments'){$copy.Remove('condition')}
  if($copy.type -eq 'Microsoft.Web/sites'){$copy.properties.siteConfig.appSettings=$defaultApp;$auth=Get-FlexArmArguments $copy.properties.functionAppConfig.deployment.storage.authentication;$copy.properties.functionAppConfig.deployment.storage.authentication=$old.properties.functionAppConfig.deployment.storage.authentication;if($auth[2] -cne "createObject('type', 'StorageAccountConnectionString', 'storageAccountConnectionStringName', 'DEPLOYMENT_STORAGE_CONNECTION_STRING')"){throw 'Default deployment parity failed'}}
  if(($copy|ConvertTo-Json -Depth 100 -Compress) -cne ($old|ConvertTo-Json -Depth 100 -Compress)){throw 'Default resource parity failed'}
 }
 $mutations=@(
  {param($n) $n.parameters.identityOnlyStorage.defaultValue=$true},
  {param($n) @($n.resources|Where-Object type -eq 'Microsoft.Storage/storageAccounts')[0].properties.allowSharedKeyAccess=$true},
  {param($n) @($n.resources|Where-Object type -eq 'Microsoft.Web/sites')[0].properties.functionAppConfig.deployment.storage.authentication="[createObject('type', 'StorageAccountConnectionString')]"},
  {param($n) $s=@($n.resources|Where-Object type -eq 'Microsoft.Web/sites')[0];$s.properties.siteConfig.appSettings=$s.properties.siteConfig.appSettings.Replace("createObject('name', 'AzureWebJobsStorage__credential', 'value', 'managedidentity')","createObject('name', 'AzureWebJobsStorage__credential', 'value', listKeys('forbidden', '2023-05-01'))")},
  {param($n) $s=@($n.resources|Where-Object type -eq 'Microsoft.Web/sites')[0];$s.properties.siteConfig.appSettings=$s.properties.siteConfig.appSettings.Replace("'AZURE_ENV_NAME'","'AzureWebJobsStorage'")},
  {param($n) $n.variables.compatibilitySettings=$n.variables.compatibilitySettings.Replace('toLower(replace(','replace(')},
  {param($n) $n.variables.compatibilitySettings=$n.variables.compatibilitySettings.Replace("'azurewebjobsstorage'","'unreserved'")},
  {param($n) $n.variables.copy[0].count=$n.variables.copy[0].count.Replace("':', '__'","':', ':'")},
  {param($n) @($n.resources|Where-Object type -eq 'Microsoft.Authorization/roleAssignments')[0].scope='[resourceGroup().id]'},
  {param($n) @($n.resources|Where-Object type -eq 'Microsoft.Authorization/roleAssignments')[0].properties.roleDefinitionId='wrong-role'},
  {param($n) @($n.resources|Where-Object type -eq 'Microsoft.Authorization/roleAssignments')[0].condition="[not(parameters('identityOnlyStorage'))]"},
  {param($n) @($n.resources|Where-Object type -eq 'Microsoft.Authorization/roleAssignments')[1].condition="[parameters('identityOnlyStorage')]"},
  {param($n) @($n.resources|Where-Object type -eq 'Microsoft.Authorization/roleAssignments')[0].scope=$true}
 )
 $count=0
 foreach($mutation in $mutations){$copy=$t|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable -DateKind String -Depth 100;& $mutation $copy.resources[0].properties.template;$file=Join-Path $scratch "$count.json";$copy|ConvertTo-Json -Depth 100|Set-Content $file -Encoding utf8NoBOM;$refused=$false;try{& $assert -Shape Pim -TemplatePath $file|Out-Null}catch{$refused=$true};if(!$refused){throw "Compiled negative accepted: $count"};$count++}
 $variables=$t.resources[0].properties.template.variables
 $countArgs=Get-FlexArmArguments $variables.copy[0].count
 $filters=@($countArgs[0],$variables.compatibilitySettings.Trim('[',']'))
 $guardCases=0
 foreach($filter in $filters){
  $filterArgs=Get-FlexArmArguments $filter;$lambdaArgs=Get-FlexArmArguments $filterArgs[1];$predicate=$lambdaArgs[1]
  foreach($name in @('AzureWebJobsStorage','azurewebjobsstorage','AZUREWEBJOBSSTORAGE__accountName','AzureWebJobsStorage:clientId','AzureWebJobsStorage::credential','DEPLOYMENT_STORAGE_CONNECTION_STRING','deployment_storage_connection_string__alias','AZD_POLLER_STATE_CONTAINER','azd_poller_state_container','AZURE_ENV_NAME','AzureWebJobsDashboard','AZUREWEBJOBSDASHBOARD','WEBSITE_CONTENTAZUREFILECONNECTIONSTRING','website_contentazurefileconnectionstring','WEBSITE_RUN_FROM_PACKAGE','website_run_from_package')){
   if(Invoke-FlexGuard $predicate $name $true){throw 'Reserved compiled predicate bypass'}
   if(!(Invoke-FlexGuard $predicate $name $false)){throw 'Legacy guard changed'}
   $guardCases+=2
  }
  foreach($name in @('AZD_PIM_STORAGE_ACCOUNT_NAME','AZD_CA_STATE_CONTAINER','AZD_CA_POLLING_SCHEDULE','WEBSITE_TIME_ZONE')){if(!(Invoke-FlexGuard $predicate $name $true)){throw 'Real consumer setting lost'};$guardCases++}
 }
 Write-Output "$count compiled security negatives refused; $guardCases actual compiled predicate cases passed; both real consumer shapes and exact default resource/settings parity passed."
}finally{Remove-Item -LiteralPath $scratch -Recurse -Force}
