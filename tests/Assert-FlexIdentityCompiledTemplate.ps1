#Requires -Version 7.6
[CmdletBinding()]
param([Parameter(Mandatory)][string]$TemplatePath,[Parameter(Mandatory)][ValidateSet('Pim','Risk')][string]$Shape)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Assert-FlexCondition([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
function Get-FlexArmArguments([string]$Expression){
 $text=$Expression.Trim('[',']');$start=$text.IndexOf('(');$depth=0;$quoted=$false;$part=$start+1;$args=[Collections.Generic.List[string]]::new()
 for($i=$start+1;$i -lt $text.Length;$i++){
  $c=$text[$i]
  if($c -eq "'"){if($quoted -and $i+1 -lt $text.Length -and $text[$i+1] -eq "'"){$i++;continue};$quoted=!$quoted;continue}
  if($quoted){continue}
  if($c -eq '('){$depth++}elseif($c -eq ')'){if($depth -eq 0){$args.Add($text.Substring($part,$i-$part).Trim());break};$depth--}
  elseif($c -eq ',' -and $depth -eq 0){$args.Add($text.Substring($part,$i-$part).Trim());$part=$i+1}
 }
 return ,$args.ToArray()
}
$t=Get-Content -LiteralPath $TemplatePath -Raw|ConvertFrom-Json -AsHashtable -DateKind String -Depth 100
$d=@($t.resources|Where-Object type -eq 'Microsoft.Resources/deployments')[0]
$n=$d.properties.template;$p=$d.properties.parameters
$site=@($n.resources|Where-Object type -eq 'Microsoft.Web/sites')[0]
$storage=@($n.resources|Where-Object type -eq 'Microsoft.Storage/storageAccounts')[0]
$roles=@($n.resources|Where-Object type -eq 'Microsoft.Authorization/roleAssignments')
Assert-FlexCondition ($n.parameters.identityOnlyStorage.defaultValue -ceq $false) 'Compatibility default changed.'
Assert-FlexCondition ($p.identityOnlyStorage.value -ceq "[parameters('identityOnlyStorage')]") 'Wrapper selector missing.'
Assert-FlexCondition ($storage.properties.allowSharedKeyAccess -is [string] -and $storage.properties.allowSharedKeyAccess -ceq "[not(parameters('identityOnlyStorage'))]") 'Shared key gate changed.'
Assert-FlexCondition ($site.identity.type -ceq 'SystemAssigned') 'System identity missing.'
$auth=$site.properties.functionAppConfig.deployment.storage.authentication
Assert-FlexCondition ($auth -ceq "[if(parameters('identityOnlyStorage'), createObject('type', 'SystemAssignedIdentity'), createObject('type', 'StorageAccountConnectionString', 'storageAccountConnectionStringName', 'DEPLOYMENT_STORAGE_CONNECTION_STRING'))]") 'Deployment authentication branches differ.'
$app=[string]$site.properties.siteConfig.appSettings
$appArgs=Get-FlexArmArguments $app
$storageArgs=Get-FlexArmArguments $appArgs[2]
Assert-FlexCondition ($appArgs.Count -eq 4 -and $appArgs[2].StartsWith('if(') -and $storageArgs.Count -eq 3 -and $storageArgs[0] -ceq "parameters('identityOnlyStorage')") 'Host storage gate changed.'
$identity=$storageArgs[1];$legacySettings=$storageArgs[2]
# ARM if evaluates only its selected branch: identity true must select a literal
# empty string before any listKeys/reference evaluation in the compatibility branch.
Assert-FlexCondition (([regex]::Matches($legacySettings,"if\(parameters\('identityOnlyStorage'\), '', format\(")).Count -eq 2) 'Key lookup is not confined to the unselected compatibility branch.'
Assert-FlexCondition (([regex]::Matches($legacySettings,'listKeys\(')).Count -eq 2) 'Unexpected key lookup count.'
Assert-FlexCondition ($legacySettings.Contains("'AzureWebJobsStorage'") -and $legacySettings.Contains("'DEPLOYMENT_STORAGE_CONNECTION_STRING'")) 'Legacy settings missing.'
foreach($key in @('blobServiceUri','queueServiceUri','tableServiceUri','credential')){Assert-FlexCondition ($identity.Contains("AzureWebJobsStorage__$key")) 'Identity host setting missing.'}
Assert-FlexCondition ($identity.Contains('primaryEndpoints.blob') -and $identity.Contains('primaryEndpoints.queue') -and $identity.Contains('primaryEndpoints.table')) 'Service endpoint binding changed.'
Assert-FlexCondition (!$identity.Contains('listKeys') -and !$identity.Contains('storageConnectionString')) 'Identity host branch evaluates credentials.'
Assert-FlexCondition ($appArgs[0] -ceq "variables('solutionSettings')" -and $appArgs[1] -ceq "variables('compatibilitySettings')") 'Unfiltered or extra app-setting layer.'
Assert-FlexCondition (!$appArgs[3].Contains("'AzureWebJobsStorage'") -and !$appArgs[3].Contains('DEPLOYMENT_STORAGE_CONNECTION_STRING')) 'Connection-string bypass appended to host.'
foreach($variable in @('solutionSettings','compatibilitySettings')){
 $expr=if($variable -eq 'solutionSettings'){[string]@($n.variables.copy|Where-Object name -eq solutionSettings)[0].count}else{[string]$n.variables[$variable]}
 Assert-FlexCondition ($expr.Contains("not(parameters('identityOnlyStorage'))")) 'Legacy settings behavior narrowed.'
 foreach($prefix in @('azurewebjobsstorage','deployment_storage_connection_string','azd_poller_','azure_env_name')){Assert-FlexCondition ($expr.Contains("'$prefix'")) 'Reserved prefix guard missing.'}
 foreach($name in @('azurewebjobsdashboard','website_contentazurefileconnectionstring','website_run_from_package')){Assert-FlexCondition ($expr.Contains("'$name'")) 'Reserved legacy/deployment name missing.'}
 Assert-FlexCondition ($expr.Contains('toLower(replace(') -and $expr.Contains("':', '__'")) 'Case/separator bypass permitted.'
}
$owner=@($roles|Where-Object { $_.condition -ceq "[parameters('identityOnlyStorage')]" })
$legacy=@($roles|Where-Object { $_.condition -ceq "[not(parameters('identityOnlyStorage'))]" })
Assert-FlexCondition ($roles.Count -eq 2 -and $owner.Count -eq 1 -and $legacy.Count -eq 1) 'Role partition changed.'
Assert-FlexCondition ($owner[0].properties.roleDefinitionId.Contains('b7e6dc6d-f1e8-4753-8033-0f276bb0955b')) 'Host owner role wrong.'
Assert-FlexCondition ($legacy[0].properties.roleDefinitionId.Contains('ba92f5b4-2d11-453d-a403-e96b0029c9fe')) 'Legacy state role changed.'
foreach($role in $roles){Assert-FlexCondition ($role.scope -is [string] -and $role.scope -ceq "[resourceId('Microsoft.Storage/storageAccounts', parameters('storageAccountName'))]") 'Role escaped shared storage scope.'}
Assert-FlexCondition ($p.stateContainerName.value -ceq ($Shape.ToLowerInvariant()+'-state')) 'State container changed.'
Assert-FlexCondition ($p.deadLetterContainerName.value -ceq ($Shape.ToLowerInvariant()+'-dead-letter')) 'Dead-letter container changed.'
Assert-FlexCondition ($p.deploymentContainerName.value -ceq 'function-releases') 'Deployment container changed.'
Assert-FlexCondition ($p.blobDeleteRetentionDays.value -eq $(if($Shape -eq 'Pim'){7}else{14})) 'Retention changed.'
Assert-FlexCondition ($p.instanceMemoryMB.value -eq 512 -and $p.maximumInstanceCount.value -eq 1) 'Right sizing changed.'
Assert-FlexCondition (@($site.properties.functionAppConfig.scaleAndConcurrency.alwaysReady).Count -eq 0) 'Always-ready cost added.'
Assert-FlexCondition ($p.storageAccountSettingAliases.value[0] -ceq $(if($Shape -eq 'Pim'){'AZD_PIM_STORAGE_ACCOUNT_NAME'}else{'AZD_CA_STORAGE_ACCOUNT_NAME'})) 'Consumer aliases changed.'
Assert-FlexCondition ($p.applicationSettings.value.Contains($(if($Shape -eq 'Pim'){'AZD_PIM_POLLING_SCHEDULE'}else{'AZD_CA_POLLING_SCHEDULE'}))) 'Consumer schedule lost.'
Assert-FlexCondition (@($n.resources|Where-Object type -match 'Insights').Count -eq 0) 'Forced telemetry added.'
Write-Output "$Shape compiled identity/compatibility contracts passed."
