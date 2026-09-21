[CmdletBinding()]
param(
    [string[]] $Repository,

    [string] $PolicyPath,

    [string] $RegistryPath,

    [switch] $AsJson,

    [switch] $FailOnFindings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GhJson {
    param([Parameter(Mandatory)][string] $Endpoint)

    $raw = @(& gh api --method GET $Endpoint 2>$null)
    if ($LASTEXITCODE -ne 0 -or $raw.Count -eq 0) { return $null }
    try { return (($raw -join "`n") | ConvertFrom-Json -Depth 100) }
    catch { return $null }
}

function Get-GhContent {
    param(
        [Parameter(Mandatory)][string] $Repository,
        [Parameter(Mandatory)][string] $Path
    )

    $encoded = @(& gh api "repos/$Repository/contents/$Path" --jq .content 2>$null)
    if ($LASTEXITCODE -ne 0 -or $encoded.Count -eq 0) { return $null }
    try {
        return [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String(($encoded -join '' -replace '\s', ''))
        )
    }
    catch { return $null }
}

function Get-WorkflowSignal {
    param(
        [Parameter(Mandatory)][string] $Repository,
        [Parameter(Mandatory)] $Metadata
    )

    $tree = Invoke-GhJson "repos/$Repository/git/trees/$($Metadata.default_branch)?recursive=1"
    if ($null -eq $tree) {
        return [pscustomobject]@{
            available = $false
            codeql = $false
            dependencyReview = $false
        }
    }

    $codeql = $false
    $dependencyReview = $false
    foreach ($path in @(
            $tree.tree |
                Where-Object {
                    $_.type -eq 'blob' -and
                    $_.path -match '^\.github/workflows/.*\.(?:yml|yaml)$'
                } |
                ForEach-Object { [string] $_.path }
        )) {
        $content = Get-GhContent -Repository $Repository -Path $path
        if ($null -eq $content) { continue }
        if ($content -match '(?i)github/codeql-action/') { $codeql = $true }
        if ($content -match '(?i)actions/dependency-review-action@') { $dependencyReview = $true }
    }

    [pscustomobject]@{
        available = $true
        codeql = $codeql
        dependencyReview = $dependencyReview
    }
}

function Get-ActiveRuleset {
    param(
        [Parameter(Mandatory)][string] $Repository,
        [Parameter(Mandatory)][ValidateSet('branch', 'tag')][string] $Target,
        [Parameter(Mandatory)][string] $Include
    )

    $rulesets = @(Invoke-GhJson "repos/$Repository/rulesets")
    foreach ($summary in $rulesets) {
        $detail = Invoke-GhJson "repos/$Repository/rulesets/$($summary.id)"
        if ($null -eq $detail -or $detail.enforcement -ne 'active' -or $detail.target -ne $Target) {
            continue
        }
        if (@($detail.conditions.ref_name.include) -contains $Include) { return $detail }
    }
    $null
}

$referenceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $PolicyPath) { $PolicyPath = Join-Path $referenceRoot 'portfolio/github-governance.json' }
$policyFull = [System.IO.Path]::GetFullPath($PolicyPath)
$policySchema = Join-Path $referenceRoot 'schemas/github-governance.schema.json'
$policyRaw = Get-Content -LiteralPath $policyFull -Raw
if (-not ($policyRaw | Test-Json -SchemaFile $policySchema -ErrorAction Stop)) {
    throw 'The GitHub governance policy does not satisfy its schema.'
}
$policy = $policyRaw | ConvertFrom-Json

if (-not $RegistryPath) { $RegistryPath = Join-Path $referenceRoot 'portfolio/github-governance-repositories.json' }
$registryFull = [System.IO.Path]::GetFullPath($RegistryPath)
$registrySchema = Join-Path $referenceRoot 'schemas/github-governance-repositories.schema.json'
$registryRaw = Get-Content -LiteralPath $registryFull -Raw
if (-not ($registryRaw | Test-Json -SchemaFile $registrySchema -ErrorAction Stop)) {
    throw 'The GitHub governance repository registry does not satisfy its schema.'
}
$registry = $registryRaw | ConvertFrom-Json
$expectedStatusChecks = @{}
$expectedReleaseTagPatterns = @{}
foreach ($entry in @($registry.repositories)) {
    $repositoryUrl = [string] $entry.repository
    $repositoryName = $repositoryUrl -replace '^https://github\.com/', ''
    $expectedStatusChecks[$repositoryName] = @($entry.requiredStatusChecks)
    $expectedReleaseTagPatterns[$repositoryName] = if ($entry.PSObject.Properties.Name -contains 'releaseTagPattern') {
        [string] $entry.releaseTagPattern
    }
    else {
        [string] $policy.releaseTags.pattern
    }
}
if (-not $Repository -or $Repository.Count -eq 0) {
    $Repository = @($expectedStatusChecks.Keys | Sort-Object)
}

$results = @()
foreach ($repositoryName in $Repository) {
    $repositoryName = $repositoryName.Trim()
    if ($repositoryName -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        throw "Repository must be owner/name: '$repositoryName'."
    }

    $findings = [System.Collections.Generic.List[string]]::new()
    $metadata = Invoke-GhJson "repos/$repositoryName"
    if ($null -eq $metadata) {
        $findings.Add('repositoryUnavailable')
        $results += [pscustomobject]@{
            repository = $repositoryName
            state = 'unavailable'
            findings = @($findings)
        }
        continue
    }

    if ($metadata.PSObject.Properties.Name -notcontains 'is_template') {
        $findings.Add('githubTemplateRepositoryMetadataUnavailable')
    }
    elseif ([string] $policy.repositoryMetadata.githubTemplateRepository -eq 'disabled' -and [bool] $metadata.is_template) {
        $findings.Add('githubTemplateRepositoryEnabled')
    }

    $actions = Invoke-GhJson "repos/$repositoryName/actions/permissions"
    if ($null -eq $actions) {
        $findings.Add('actionsPolicyUnavailable')
    }
    else {
        if ([string] $actions.allowed_actions -ne [string] $policy.actions.allowedActions) {
            $findings.Add("actionsAllowed:$($actions.allowed_actions)")
        }
        if ([bool] $actions.sha_pinning_required -ne [bool] $policy.actions.shaPinningRequired) {
            $findings.Add('actionsShaPinningNotRequired')
        }
    }

    $selected = Invoke-GhJson "repos/$repositoryName/actions/permissions/selected-actions"
    if ($null -eq $selected) {
        $findings.Add('selectedActionsUnavailable')
    }
    else {
        if ([bool] $selected.github_owned_allowed -ne [bool] $policy.actions.githubOwnedAllowed) {
            $findings.Add('githubOwnedActionsPolicyMismatch')
        }
        if ([bool] $selected.verified_allowed -ne [bool] $policy.actions.verifiedAllowed) {
            $findings.Add('verifiedActionsPolicyMismatch')
        }
        if (@($selected.patterns_allowed | Where-Object { [string] $_ -match '(^|/)\*@\*$' }).Count -gt 0) {
            $findings.Add('thirdPartyWildcardPattern')
        }
    }

    $workflowPermissions = Invoke-GhJson "repos/$repositoryName/actions/permissions/workflow"
    if ($null -eq $workflowPermissions) {
        $findings.Add('workflowPermissionsUnavailable')
    }
    elseif ([string] $workflowPermissions.default_workflow_permissions -ne [string] $policy.workflow.defaultPermissions) {
        $findings.Add("workflowDefaultPermissions:$($workflowPermissions.default_workflow_permissions)")
    }

    $securityFixes = Invoke-GhJson "repos/$repositoryName/automated-security-fixes"
    if ($null -eq $securityFixes -or -not [bool] $securityFixes.enabled) {
        $findings.Add('dependabotSecurityUpdatesDisabled')
    }

    $signals = Get-WorkflowSignal -Repository $repositoryName -Metadata $metadata
    if (-not $signals.available) { $findings.Add('workflowInventoryUnavailable') }

    $isPublic = -not [bool] $metadata.private
    $security = if ($metadata.PSObject.Properties.Name -contains 'security_and_analysis') {
        $metadata.security_and_analysis
    }
    else {
        $null
    }
    if ($isPublic) {
        if ($null -eq $security -or [string] $security.secret_scanning.status -ne 'enabled') {
            $findings.Add('secretScanningDisabled')
        }
        if ($null -eq $security -or [string] $security.secret_scanning_push_protection.status -ne 'enabled') {
            $findings.Add('secretScanningPushProtectionDisabled')
        }

        $defaultSetup = Invoke-GhJson "repos/$repositoryName/code-scanning/default-setup"
        if ((-not $signals.codeql) -and
            ($null -eq $defaultSetup -or [string] $defaultSetup.state -ne 'configured')) {
            $findings.Add('codeScanningMissing')
        }
        if (-not $signals.dependencyReview) { $findings.Add('dependencyReviewMissing') }
    }

    $mainRuleset = Get-ActiveRuleset -Repository $repositoryName -Target branch -Include '~DEFAULT_BRANCH'
    if ($null -eq $mainRuleset) {
        $findings.Add('defaultBranchRulesetMissing')
    }
    else {
        $rules = @($mainRuleset.rules)
        $ruleTypes = @($rules.type)
        foreach ($requiredType in 'deletion', 'non_fast_forward', 'pull_request', 'required_status_checks') {
            if ($requiredType -notin $ruleTypes) { $findings.Add("defaultBranchRuleMissing:$requiredType") }
        }
        $pullRequestRule = $rules | Where-Object type -eq 'pull_request' | Select-Object -First 1
        if ($pullRequestRule) {
            if ([int] $pullRequestRule.parameters.required_approving_review_count -ne [int] $policy.defaultBranch.requiredApprovingReviewCount) {
                $findings.Add('defaultBranchApprovalCountMismatch')
            }
            if (-not [bool] $pullRequestRule.parameters.required_review_thread_resolution) {
                $findings.Add('defaultBranchConversationResolutionDisabled')
            }
        }
        $statusRule = $rules | Where-Object type -eq 'required_status_checks' | Select-Object -First 1
        if ($null -eq $statusRule) {
            $findings.Add('defaultBranchRequiredStatusChecksMissing')
        }
        else {
            if (-not [bool] $statusRule.parameters.strict_required_status_checks_policy) {
                $findings.Add('defaultBranchStatusChecksNotStrict')
            }
            $actualChecks = @($statusRule.parameters.required_status_checks | ForEach-Object { [string] $_.context })
            if ($expectedStatusChecks.ContainsKey($repositoryName)) {
                $expectedChecks = @($expectedStatusChecks[$repositoryName])
                foreach ($expectedCheck in $expectedChecks) {
                    if ($expectedCheck -notin $actualChecks) {
                        $findings.Add("requiredStatusCheckMissing:$expectedCheck")
                    }
                }
                foreach ($actualCheck in $actualChecks) {
                    if ($actualCheck -notin $expectedChecks) {
                        $findings.Add("unexpectedRequiredStatusCheck:$actualCheck")
                    }
                }
            }
        }
        if ([string] $mainRuleset.current_user_can_bypass -ne 'always') {
            $findings.Add('defaultBranchRecoveryBypassMissing')
        }
    }

    $legacyProtection = Invoke-GhJson "repos/$repositoryName/branches/$($metadata.default_branch)/protection"
    if ($null -ne $legacyProtection) { $findings.Add('legacyBranchProtectionPresent') }

    if ($isPublic) {
        $tagPattern = if ($expectedReleaseTagPatterns.ContainsKey($repositoryName)) {
            [string] $expectedReleaseTagPatterns[$repositoryName]
        }
        else {
            [string] $policy.releaseTags.pattern
        }
        $tagRuleset = Get-ActiveRuleset -Repository $repositoryName -Target tag -Include $tagPattern
        if ($null -eq $tagRuleset) {
            $findings.Add('releaseTagRulesetMissing')
        }
        else {
            $tagTypes = @($tagRuleset.rules.type)
            if ('deletion' -notin $tagTypes) { $findings.Add('releaseTagDeletionNotBlocked') }
            if ('update' -notin $tagTypes) { $findings.Add('releaseTagUpdateNotBlocked') }
        }
    }

    $results += [pscustomobject] [ordered]@{
        repository = $repositoryName
        visibility = [string] $metadata.visibility
        state = if ($findings.Count -eq 0) { 'current' } else { 'findings' }
        findings = @($findings)
    }
}

if ($AsJson) { $results | ConvertTo-Json -Depth 10 }
else { $results }

if ($FailOnFindings -and @($results | Where-Object state -ne 'current').Count -gt 0) {
    throw 'GitHub governance findings were detected.'
}
