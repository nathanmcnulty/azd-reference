[CmdletBinding()]
param(
    [string[]] $Repository,

    [string] $PolicyPath,

    [string] $RegistryPath,

    [switch] $AsJson,

    [switch] $FailOnFindings,

    [switch] $CatalogValidationOnly,

    [switch] $CheckPublicRegistryCoverage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Azd.GitHubGovernance.psm1') -Force

function Invoke-GhJson {
    param([Parameter(Mandatory)][string] $Endpoint)

    $raw = @(& gh api --method GET $Endpoint 2>$null)
    if ($LASTEXITCODE -ne 0 -or $raw.Count -eq 0) { return $null }
    try { return (($raw -join "`n") | ConvertFrom-Json -Depth 100) }
    catch { return $null }
}

function Get-GhContentResult {
    param(
        [Parameter(Mandatory)][string] $Repository,
        [Parameter(Mandatory)][string] $Path
    )

    $encoded = @(& gh api "repos/$Repository/contents/$Path" --jq .content 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $detail = $encoded -join "`n"
        return [pscustomobject]@{
            status = if ($detail -match '(?i)(HTTP\s+404|404\s+Not\s+Found)') { 'missing' } else { 'unavailable' }
            content = $null
        }
    }
    if ($encoded.Count -eq 0) {
        return [pscustomobject]@{ status = 'unavailable'; content = $null }
    }
    try {
        $content = [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String(($encoded -join '' -replace '\s', ''))
        )
        return [pscustomobject]@{ status = 'present'; content = $content }
    }
    catch { return [pscustomobject]@{ status = 'unavailable'; content = $null } }
}

function Get-ExpectedCatalogCaller {
    param(
        [Parameter(Mandatory)] $Policy,
        [Parameter(Mandatory)][string] $DefaultBranch,
        [Parameter(Mandatory)][string] $CatalogPath
    )

    $lines = @(
        'name: azd catalog metadata',
        '',
        'on:',
        '  pull_request:',
        '  push:',
        "    branches: [$DefaultBranch]",
        '  workflow_dispatch:',
        '',
        'permissions:',
        '  contents: read',
        '',
        'jobs:',
        '  catalog:',
        '    name: azd catalog metadata',
        "    uses: $($Policy.workflow)@$($Policy.desiredWorkflowRevision)",
        '    permissions:',
        '      contents: read'
    )
    if ($CatalogPath -ne '.azd/catalog.json') {
        $lines += @(
            '    with:',
            "      catalog-path: $CatalogPath"
        )
    }
    $lines -join "`n"
}

function Get-CatalogValidationSignal {
    param(
        [Parameter(Mandatory)][string] $Repository,
        [Parameter(Mandatory)] $Policy,
        [Parameter(Mandatory)] $Enrollment,
        [Parameter(Mandatory)][string] $DefaultBranch
    )

    $callerResult = Get-GhContentResult -Repository $Repository -Path ([string] $Policy.callerPath)
    $caller = $callerResult.content
    $revision = $null
    if ($null -ne $caller) {
        $workflowPattern = [Regex]::Escape([string] $Policy.workflow)
        $match = [Regex]::Match(
            $caller,
            "(?im)^\s*uses:\s*$workflowPattern@([0-9a-f]{40})\s*(?:#.*)?$"
        )
        if ($match.Success) { $revision = $match.Groups[1].Value.ToLowerInvariant() }
    }

    $catalogPath = if ($Enrollment.PSObject.Properties.Name -contains 'catalogPath') {
        [string] $Enrollment.catalogPath
    }
    else {
        '.azd/catalog.json'
    }
    $catalogStatus = 'notChecked'
    if ([string] $Enrollment.state -in @('pilot', 'required')) {
        $catalogResult = Get-GhContentResult -Repository $Repository -Path $catalogPath
        $catalogStatus = $catalogResult.status
    }
    $callerContractValid = $false
    if ($null -ne $caller) {
        $expectedCaller = Get-ExpectedCatalogCaller `
            -Policy $Policy `
            -DefaultBranch $DefaultBranch `
            -CatalogPath $catalogPath
        $normalizedCaller = ($caller -replace "`r`n", "`n").TrimEnd("`r", "`n")
        $callerContractValid = $normalizedCaller -ceq $expectedCaller
    }

    [pscustomobject]@{
        callerPresent = $null -ne $caller
        callerStatus = $callerResult.status
        callerRevision = $revision
        callerContractValid = $callerContractValid
        catalogPath = $catalogPath
        catalogStatus = $catalogStatus
    }
}

function Get-WorkflowSignal {
    param(
        [Parameter(Mandatory)][string] $Repository,
        [Parameter(Mandatory)] $Metadata,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][string[]] $AllowedActionPatterns,
        [Parameter(Mandatory)][string] $RepositoryOwner,
        [Parameter(Mandatory)][bool] $GitHubOwnedActionsAllowed
    )

    $tree = Invoke-GhJson "repos/$Repository/git/trees/$($Metadata.default_branch)?recursive=1"
    if ($null -eq $tree) {
        return [pscustomobject]@{
            available = $false
            codeql = $false
            dependencyReview = $false
            actionInventoryComplete = $false
            actionReferencesScanned = 0
            actionFindings = @()
        }
    }

    $codeql = $false
    $dependencyReview = $false
    $workflowContents = [System.Collections.Generic.List[object]]::new()
    $actionFindings = [System.Collections.Generic.List[string]]::new()
    $actionInventoryComplete = -not [bool] $tree.truncated
    if (-not $actionInventoryComplete) { $actionFindings.Add('workflowInventoryTruncated') }
    foreach ($path in @(
            $tree.tree |
                Where-Object {
                    $_.type -eq 'blob' -and
                    ($_.path -match '^\.github/workflows/.*\.(?:yml|yaml)$' -or
                    $_.path -match '(^|/)action\.(?:yml|yaml)$')
                } |
                ForEach-Object { [string] $_.path }
        )) {
        $contentResult = Get-GhContentResult -Repository $Repository -Path $path
        if ($contentResult.status -ne 'present') {
            $actionFindings.Add("workflowContentUnavailable:$path")
            $actionInventoryComplete = $false
            continue
        }
        $content = [string] $contentResult.content
        $workflowContents.Add([pscustomobject]@{ path = $path; content = $content })
        if ($content -match '(?i)github/codeql-action/') { $codeql = $true }
        if ($content -match '(?i)actions/dependency-review-action@') { $dependencyReview = $true }
    }
    $actionPolicy = Test-AzdGitHubWorkflowActionPolicy `
        -WorkflowContents @($workflowContents) `
        -AllowedActionPatterns $AllowedActionPatterns `
        -RepositoryOwner $RepositoryOwner `
        -GitHubOwnedActionsAllowed $GitHubOwnedActionsAllowed
    foreach ($finding in @($actionPolicy.findings)) { $actionFindings.Add([string] $finding) }

    [pscustomobject]@{
        available = $true
        codeql = $codeql
        dependencyReview = $dependencyReview
        actionInventoryComplete = $actionInventoryComplete
        actionReferencesScanned = [int] $actionPolicy.actionReferenceCount
        actionFindings = @($actionFindings)
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
$requiredCatalogRepositories = @($registry.repositories | Where-Object {
        [string] $_.catalogValidation.state -eq 'required'
    })
if ([string] $registry.catalogValidationPolicy.enforcementMode -eq 'non-required' -and
    $requiredCatalogRepositories.Count -gt 0) {
    throw 'Catalog validation enforcement is non-required, but the registry contains required repositories.'
}
$canonicalWorkflowRepository = @(([string] $registry.catalogValidationPolicy.workflow -split '/')[0..1]) -join '/'
$expectedStatusChecks = @{}
$expectedReleaseTagPatterns = @{}
$catalogEnrollments = @{}
$registryEntries = @{}
foreach ($entry in @($registry.repositories)) {
    $repositoryUrl = [string] $entry.repository
    $repositoryName = $repositoryUrl -replace '^https://github\.com/', ''
    $expectedStatusChecks[$repositoryName] = @($entry.requiredStatusChecks)
    $catalogEnrollments[$repositoryName] = $entry.catalogValidation
    $registryEntries[$repositoryName] = $entry
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
            actionInventoryComplete = $false
            actionReferencesScanned = 0
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
    if ($registryEntries.ContainsKey($repositoryName) -and
        [string] $metadata.visibility -ne [string] $registryEntries[$repositoryName].visibility) {
        $findings.Add("repositoryVisibilityMismatch:$($metadata.visibility)")
    }
    if ($registryEntries.ContainsKey($repositoryName) -and
        [string] $metadata.default_branch -ne [string] $registryEntries[$repositoryName].defaultBranch) {
        $findings.Add("defaultBranchMismatch:$($metadata.default_branch)")
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
        if ($registryEntries.ContainsKey($repositoryName)) {
            $expectedPatterns = @($registryEntries[$repositoryName].allowedActionPatterns | ForEach-Object { [string] $_ })
            $actualPatterns = @($selected.patterns_allowed | ForEach-Object { [string] $_ })
            foreach ($expectedPattern in $expectedPatterns) {
                if ($expectedPattern -notin $actualPatterns) {
                    $findings.Add("selectedActionAllowlistEntryMissing:$expectedPattern")
                }
            }
            foreach ($actualPattern in $actualPatterns) {
                if ($actualPattern -notin $expectedPatterns) {
                    $findings.Add("selectedActionAllowlistEntryUnexpected:$actualPattern")
                }
            }
            $seenPatterns = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            foreach ($actualPattern in $actualPatterns) {
                if (-not $seenPatterns.Add($actualPattern)) {
                    $findings.Add("selectedActionAllowlistEntryDuplicate:$actualPattern")
                }
            }
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

    $allowedActionPatterns = if ($registryEntries.ContainsKey($repositoryName)) {
        @($registryEntries[$repositoryName].allowedActionPatterns | ForEach-Object { [string] $_ })
    }
    else {
        @()
    }
    $signals = Get-WorkflowSignal `
        -Repository $repositoryName `
        -Metadata $metadata `
        -AllowedActionPatterns $allowedActionPatterns `
        -RepositoryOwner (($repositoryName -split '/', 2)[0]) `
        -GitHubOwnedActionsAllowed ([bool] $policy.actions.githubOwnedAllowed)
    if (-not $signals.available) { $findings.Add('workflowInventoryUnavailable') }
    foreach ($actionFinding in @($signals.actionFindings)) { $findings.Add([string] $actionFinding) }

    $catalogState = 'unregistered'
    $catalogRevision = $null
    if ($catalogEnrollments.ContainsKey($repositoryName)) {
        $enrollment = $catalogEnrollments[$repositoryName]
        $catalogState = [string] $enrollment.state
        $catalogSignal = Get-CatalogValidationSignal `
            -Repository $repositoryName `
            -Policy $registry.catalogValidationPolicy `
            -Enrollment $enrollment `
            -DefaultBranch ([string] $registryEntries[$repositoryName].defaultBranch)
        $catalogRevision = $catalogSignal.callerRevision

        switch ($catalogState) {
            'pending' {
                if ($catalogSignal.callerStatus -eq 'unavailable') { $findings.Add('catalogCallerAuditUnavailable') }
                elseif ($catalogSignal.callerPresent) { $findings.Add('catalogCallerUnexpected') }
            }
            'pilot' {
                if ($catalogSignal.callerStatus -eq 'unavailable') { $findings.Add('catalogCallerAuditUnavailable') }
                elseif (-not $catalogSignal.callerPresent) { $findings.Add('catalogCallerMissing') }
                elseif ($null -eq $catalogRevision) { $findings.Add('catalogCallerPinUnreadable') }
                elseif ($catalogRevision -ne [string] $registry.catalogValidationPolicy.desiredWorkflowRevision) {
                    $findings.Add("catalogCallerRevision:$catalogRevision")
                }
                elseif (-not $catalogSignal.callerContractValid) { $findings.Add('catalogCallerContractMismatch') }
                if ($catalogSignal.catalogStatus -eq 'unavailable') { $findings.Add('catalogMetadataAuditUnavailable') }
                elseif ($catalogSignal.catalogStatus -eq 'missing') { $findings.Add("catalogMetadataMissing:$($catalogSignal.catalogPath)") }
            }
            'required' {
                if ($catalogSignal.callerStatus -eq 'unavailable') { $findings.Add('catalogCallerAuditUnavailable') }
                elseif (-not $catalogSignal.callerPresent) { $findings.Add('catalogCallerMissing') }
                elseif ($null -eq $catalogRevision) { $findings.Add('catalogCallerPinUnreadable') }
                elseif ($catalogRevision -ne [string] $registry.catalogValidationPolicy.desiredWorkflowRevision) {
                    $findings.Add("catalogCallerRevision:$catalogRevision")
                }
                elseif (-not $catalogSignal.callerContractValid) { $findings.Add('catalogCallerContractMismatch') }
                if ($catalogSignal.catalogStatus -eq 'unavailable') { $findings.Add('catalogMetadataAuditUnavailable') }
                elseif ($catalogSignal.catalogStatus -eq 'missing') { $findings.Add("catalogMetadataMissing:$($catalogSignal.catalogPath)") }
                $catalogContext = [string] $registry.catalogValidationPolicy.requiredStatusCheck.context
                if ($catalogContext -notin @($expectedStatusChecks[$repositoryName])) {
                    $findings.Add("catalogRequiredStatusCheckNotDeclared:$catalogContext")
                }
            }
            'exempt' {
                if ($catalogSignal.callerStatus -eq 'unavailable') { $findings.Add('catalogCallerAuditUnavailable') }
                elseif ($catalogSignal.callerPresent -and $repositoryName -ne $canonicalWorkflowRepository) {
                    $findings.Add('catalogCallerUnexpected')
                }
            }
            default { $findings.Add("catalogEnrollmentStateInvalid:$catalogState") }
        }
    }

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
        if ($CatalogValidationOnly -and $catalogState -eq 'required') {
            $findings.Add('catalogRequiredStatusCheckMissing')
        }
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
            if ($CatalogValidationOnly -and $catalogState -eq 'required') {
                $findings.Add('catalogRequiredStatusCheckMissing')
            }
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
            if ($catalogEnrollments.ContainsKey($repositoryName)) {
                $catalogContext = [string] $registry.catalogValidationPolicy.requiredStatusCheck.context
                $catalogIntegrationId = [int64] $registry.catalogValidationPolicy.requiredStatusCheck.integrationId
                $actualCatalogChecks = @($statusRule.parameters.required_status_checks | Where-Object {
                        [string] $_.context -eq $catalogContext
                    })
                if ($catalogState -eq 'required') {
                    if (@($actualCatalogChecks | Where-Object {
                                [int64] $_.integration_id -eq $catalogIntegrationId
                            }).Count -eq 0) {
                        $findings.Add("catalogRequiredStatusCheckSourceMismatch:$catalogContext@$catalogIntegrationId")
                    }
                }
                elseif ($actualCatalogChecks.Count -gt 0) {
                    $findings.Add("catalogStatusCheckUnexpectedlyRequired:$catalogContext")
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

    if ($CatalogValidationOnly) {
        $catalogFindings = @($findings | Where-Object { [string] $_ -like 'catalog*' })
        $findings.Clear()
        foreach ($finding in $catalogFindings) { $findings.Add($finding) }
    }

    $results += [pscustomobject] [ordered]@{
        repository = $repositoryName
        visibility = [string] $metadata.visibility
        actionInventoryComplete = [bool] $signals.actionInventoryComplete
        actionReferencesScanned = [int] $signals.actionReferencesScanned
        catalogValidationState = $catalogState
        catalogWorkflowRevision = $catalogRevision
        state = if ($findings.Count -eq 0) { 'current' } else { 'findings' }
        findings = @($findings)
    }
}

if ($CheckPublicRegistryCoverage) {
    $discoveryOwner = [string] $registry.publicRepositoryDiscovery.owner
    $endpoint = "users/$discoveryOwner/repos?type=owner&per_page=100"
    $publicRepositoryNames = @(& gh api --paginate --jq '.[].name' $endpoint 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to enumerate public repositories for '$discoveryOwner'."
    }
    $results += Compare-AzdGitHubPublicRepositoryRegistry `
        -Registry $registry `
        -PublicRepositoryNames $publicRepositoryNames
}

if ($AsJson) { $results | ConvertTo-Json -Depth 10 }
else { $results }

if ($FailOnFindings -and @($results | Where-Object state -ne 'current').Count -gt 0) {
    throw 'GitHub governance findings were detected.'
}
