[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $PimTemplatePath,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $RiskTemplatePath,

    [string] $AssertionScriptPath = (Join-Path $PSScriptRoot 'Assert-AzureMonitorCompiledTemplate.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NegativeCase {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('Pim', 'Risk')]
        [string] $Shape,

        [Parameter(Mandatory)]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [scriptblock] $Mutation,

        [Parameter(Mandatory)]
        [string] $ExpectedMessage,

        [Parameter(Mandatory)]
        [string] $CaseRoot
    )

    $caseTemplate = Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json -Depth 100
    & $Mutation $caseTemplate
    $casePath = Join-Path $CaseRoot "$Name.json"
    $caseTemplate | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $casePath -Encoding utf8NoBOM

    $caughtMessage = $null
    try {
        & $AssertionScriptPath -Shape $Shape -TemplatePath $casePath | Out-Null
    }
    catch {
        $caughtMessage = $_.Exception.Message
    }

    if (-not $caughtMessage) {
        throw "Negative case '$Name' unexpectedly passed."
    }
    if ($caughtMessage -notlike "*$ExpectedMessage*") {
        throw "Negative case '$Name' failed for the wrong reason: $caughtMessage"
    }
    Write-Output "Negative case '$Name' was rejected as expected."
}

if (-not (Test-Path -LiteralPath $AssertionScriptPath -PathType Leaf)) {
    throw "Compiled-template assertion script was not found: $AssertionScriptPath"
}

$caseRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('azd-reference-negative-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $caseRoot | Out-Null
try {
    Invoke-NegativeCase `
        -Name 'alias-variable-indirection' `
        -Shape Pim `
        -SourcePath $PimTemplatePath `
        -ExpectedMessage 'Pim wrapper must expose exactly 0 output(s); found 1.' `
        -CaseRoot $caseRoot `
        -Mutation {
            param($template)
            $template | Add-Member -NotePropertyName variables -NotePropertyValue ([pscustomobject]@{
                    callbackAlias = "[listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', 'fixture', 'manual'), '2019-05-01').value]"
                })
            $template | Add-Member -NotePropertyName outputs -NotePropertyValue ([pscustomobject]@{
                    notificationEndpointAlias = [pscustomobject]@{
                        type = 'string'
                        value = "[variables('callbackAlias')]"
                    }
                })
        }

    Invoke-NegativeCase `
        -Name 'whole-resource-reference' `
        -Shape Risk `
        -SourcePath $RiskTemplatePath `
        -ExpectedMessage "output 'actionGroupResourceId' value expression must be exactly" `
        -CaseRoot $caseRoot `
        -Mutation {
            param($template)
            $actionGroup = @($template.resources | Where-Object {
                    [string] $_.type -eq 'Microsoft.Resources/deployments' -and [string] $_.name -eq 'risk-action-group-fixture'
                })[0]
            $actionGroup.properties.template.outputs.actionGroupResourceId.value = "[reference(resourceId('Microsoft.Insights/actionGroups', parameters('actionGroupName')), '2023-01-01', 'full')]"
        }
}
finally {
    if (Test-Path -LiteralPath $caseRoot) {
        [System.IO.Directory]::Delete($caseRoot, $true)
    }
}
