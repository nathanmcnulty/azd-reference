Set-StrictMode -Version Latest

function Invoke-ProjectDeploymentValidationChecks {
    [CmdletBinding()]
    param(
        [switch] $Plan,
        [switch] $TestDelivery
    )

    $repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

    Invoke-AzdValidationCheck `
        -Id 'context.template-root' `
        -Phase context `
        -Title 'Template root is complete' `
        -Summary 'azure.yaml exists at the repository root.' `
        -SideEffect none `
        -Plan:$Plan `
        -Action {
            if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot 'azure.yaml') -PathType Leaf)) {
                throw 'azure.yaml was not found.'
            }
        }

    Invoke-AzdValidationCheck `
        -Id 'context.azure-cli-session' `
        -Phase context `
        -Title 'Azure CLI context is available' `
        -Summary 'An existing Azure CLI session is available for read-only validation.' `
        -SideEffect readOnly `
        -Plan:$Plan `
        -Remediation 'Run az login using the normal broker or browser flow, then rerun validation.' `
        -Action {
            & az account show --only-show-errors --output none
            if ($LASTEXITCODE -ne 0) { throw 'No usable cached Azure CLI context was found.' }
        }

    Invoke-AzdValidationCheck `
        -Id 'infrastructure.resource-group' `
        -Phase infrastructure `
        -Title 'Resource group exists' `
        -Summary 'The deployed resource group is readable in the selected subscription.' `
        -SideEffect readOnly `
        -Plan:$Plan `
        -Remediation 'Confirm AZURE_RESOURCE_GROUP and the selected Azure subscription, then rerun validation.' `
        -Action {
            if (-not $env:AZURE_RESOURCE_GROUP) { throw 'AZURE_RESOURCE_GROUP is missing.' }
            & az group show --name $env:AZURE_RESOURCE_GROUP --only-show-errors --output none
            if ($LASTEXITCODE -ne 0) { throw 'The deployed resource group could not be read.' }
        }

    Invoke-AzdValidationCheck `
        -Id 'delivery.not-configured' `
        -Phase delivery `
        -Title 'Synthetic delivery test' `
        -Summary 'The solution-specific delivery test succeeded.' `
        -SideEffect syntheticDelivery `
        -Plan:$Plan `
        -AllowSyntheticDelivery:$TestDelivery `
        -SkipReason 'No solution-specific delivery test has been configured in this skeleton.' `
        -Action { throw 'Replace this placeholder with the solution delivery adapter.' }
}

Export-ModuleMember -Function 'Invoke-ProjectDeploymentValidationChecks'
