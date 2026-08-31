[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Pim', 'Risk')]
    [string] $Shape,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $TemplatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Condition {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-NestedDeployment {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Template,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $deploymentMatches = @($Template.resources | Where-Object {
            [string] $_.type -eq 'Microsoft.Resources/deployments' -and [string] $_.name -eq $Name
        })
    Assert-Condition ($deploymentMatches.Count -eq 1) "Expected exactly one nested deployment named '$Name'."
    return $deploymentMatches[0]
}

function Assert-NoCallbackOutput {
    param(
        [AllowNull()]
        [object] $Node,

        [string] $Path = '$'
    )

    if ($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]) {
        return
    }

    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            $value = $Node[$key]
            if ([string] $key -eq 'outputs') {
                $serialized = $value | ConvertTo-Json -Depth 100 -Compress
                Assert-Condition ($serialized -notmatch '(?i)listCallbackUrl|callbackUrl|/triggers/') "Callback material was exposed under $Path.outputs."
            }
            Assert-NoCallbackOutput -Node $value -Path "$Path.$key"
        }
        return
    }

    if ($Node -is [System.Collections.IEnumerable]) {
        $index = 0
        foreach ($item in $Node) {
            Assert-NoCallbackOutput -Node $item -Path "$Path[$index]"
            $index++
        }
        return
    }

    foreach ($property in $Node.PSObject.Properties) {
        if ($property.Name -eq 'outputs') {
            $serialized = $property.Value | ConvertTo-Json -Depth 100 -Compress
            Assert-Condition ($serialized -notmatch '(?i)listCallbackUrl|callbackUrl|/triggers/') "Callback material was exposed under $Path.outputs."
        }
        Assert-NoCallbackOutput -Node $property.Value -Path "$Path.$($property.Name)"
    }
}

$expected = if ($Shape -eq 'Pim') {
    [ordered]@{
        prefix = 'pim'
        workflowName = 'pim-fixture-workflow'
        actionGroupName = 'pim-fixture-action-group'
        alertRuleName = 'pim-fixture-alert'
        displayName = 'Microsoft Entra PIM activation completed'
        queryMarker = 'AuditLogs'
        autoMitigate = $true
        evaluationFrequency = 'PT5M'
        windowSize = 'PT5M'
        dimensions = @('ActivationEventId', 'CorrelationId', 'Actor', 'Role')
    }
}
else {
    [ordered]@{
        prefix = 'risk'
        workflowName = 'risk-fixture-workflow'
        actionGroupName = 'risk-fixture-action-group'
        alertRuleName = 'risk-fixture-alert'
        displayName = 'Microsoft Entra risk detection'
        queryMarker = 'AADRiskyUsers'
        autoMitigate = $false
        evaluationFrequency = 'PT5M'
        windowSize = 'PT10M'
        dimensions = @('Envelope')
    }
}

$template = Get-Content -LiteralPath $TemplatePath -Raw | ConvertFrom-Json -Depth 100
$actionGroup = Get-NestedDeployment -Template $template -Name "$($expected.prefix)-action-group-fixture"
$alert = Get-NestedDeployment -Template $template -Name "$($expected.prefix)-alert-fixture"

$actionParameters = $actionGroup.properties.parameters
$alertParameters = $alert.properties.parameters

Assert-Condition ([string] $actionParameters.actionGroupName.value -eq $expected.actionGroupName) 'Action-group name was not passed exactly.'
Assert-Condition ([string] $actionParameters.logicAppResourceId.value -match "Microsoft\.Logic/workflows.*$([regex]::Escape($expected.workflowName))") 'Logic App resource ID was not derived from the wrapper resource.'
Assert-Condition ((@($actionGroup.dependsOn) -join ' ') -match "Microsoft\.Logic/workflows.*$([regex]::Escape($expected.workflowName))") 'Action-group module does not depend on its Logic App resource.'

Assert-Condition ([string] $alertParameters.alertRuleName.value -eq $expected.alertRuleName) 'Alert-rule name was not passed exactly.'
Assert-Condition ([string] $alertParameters.displayName.value -eq $expected.displayName) 'Alert display name was not passed exactly.'
Assert-Condition ([string] $alertParameters.query.value -match [regex]::Escape($expected.queryMarker)) 'Representative query was not passed to the alert module.'
Assert-Condition ([bool] $alertParameters.autoMitigate.value -eq $expected.autoMitigate) 'autoMitigate does not match the consumer shape.'
Assert-Condition ([string] $alertParameters.evaluationFrequency.value -eq $expected.evaluationFrequency) 'Evaluation frequency does not match the consumer shape.'
Assert-Condition ([string] $alertParameters.windowSize.value -eq $expected.windowSize) 'Window size does not match the consumer shape.'
Assert-Condition ([string] $alertParameters.workspaceResourceId.value -match 'Microsoft\.OperationalInsights/workspaces.*fixture-workspace') 'Workspace resource ID was not derived from the wrapper resource.'
Assert-Condition ([string] $alertParameters.actionGroupResourceId.value -match "Microsoft\.Resources/deployments.*$($expected.prefix)-action-group-fixture.*outputs.*actionGroupResourceId") 'Alert action-group ID was not derived from the action-group module output.'
Assert-Condition ((@($alert.dependsOn) -join ' ') -match "Microsoft\.Resources/deployments.*$($expected.prefix)-action-group-fixture") 'Alert module does not depend on the action-group module.'

$actualDimensionObjects = @($alertParameters.dimensions.value)
$actualDimensions = @($actualDimensionObjects | ForEach-Object { [string] $_.name })
Assert-Condition ($actualDimensionObjects.Count -eq $expected.dimensions.Count) 'Alert dimension count does not match the consumer shape.'
for ($index = 0; $index -lt $expected.dimensions.Count; $index++) {
    Assert-Condition ($actualDimensions[$index] -eq $expected.dimensions[$index]) "Alert dimension $index does not match the consumer shape."
    Assert-Condition ([string] $actualDimensionObjects[$index].operator -eq 'Include') "Alert dimension $index does not use the Include operator."
    $dimensionValues = @($actualDimensionObjects[$index].values)
    Assert-Condition ($dimensionValues.Count -eq 1 -and [string] $dimensionValues[0] -eq '*') "Alert dimension $index does not include exactly the wildcard value."
}

$actionResource = @($actionGroup.properties.template.resources | Where-Object type -eq 'Microsoft.Insights/actionGroups')[0]
$alertResource = @($alert.properties.template.resources | Where-Object type -eq 'Microsoft.Insights/scheduledQueryRules')[0]
Assert-Condition ($null -ne $actionResource) 'Compiled action-group module does not contain the expected resource.'
Assert-Condition ($null -ne $alertResource) 'Compiled alert module does not contain the expected resource.'
Assert-Condition ([string] $actionResource.properties.logicAppReceivers[0].callbackUrl -match 'listCallbackUrl') 'Logic App callback is not consumed by the receiver property.'
Assert-Condition ([bool] $actionResource.properties.logicAppReceivers[0].useCommonAlertSchema) 'Common alert schema is not enabled.'
Assert-Condition ([string] $alertResource.properties.displayName -eq "[parameters('displayName')]") 'displayName is not consumed by the alert property.'
Assert-Condition ([string] $alertResource.properties.description -eq "[parameters('alertDescription')]") 'alertDescription is not consumed by the alert property.'
Assert-Condition ([string] $alertResource.properties.evaluationFrequency -eq "[parameters('evaluationFrequency')]") 'evaluationFrequency is not consumed by the alert property.'
Assert-Condition ([string] $alertResource.properties.windowSize -eq "[parameters('windowSize')]") 'windowSize is not consumed by the alert property.'
Assert-Condition ([string] $alertResource.properties.autoMitigate -eq "[parameters('autoMitigate')]") 'autoMitigate is not consumed by the alert property.'
Assert-Condition ([string] $alertResource.properties.scopes[0] -eq "[parameters('workspaceResourceId')]") 'workspaceResourceId is not consumed by the alert scope.'
Assert-Condition ([string] $alertResource.properties.criteria.allOf[0].query -eq "[parameters('query')]") 'query is not consumed by the alert criteria.'
Assert-Condition ([string] $alertResource.properties.criteria.allOf[0].dimensions -eq "[parameters('dimensions')]") 'dimensions are not consumed by the alert criteria.'
Assert-Condition ([string] $alertResource.properties.actions.actionGroups[0] -eq "[parameters('actionGroupResourceId')]") 'actionGroupResourceId is not consumed by the alert action.'

Assert-NoCallbackOutput -Node $template
Write-Output "$Shape compiled wrapper assertions passed."
