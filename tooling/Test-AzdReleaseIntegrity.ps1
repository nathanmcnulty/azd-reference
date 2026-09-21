[CmdletBinding()]
param(
    [string] $RepositoryRoot,

    [string] $PolicyPath,

    [string] $Tag,

    [switch] $AsJson,

    [switch] $FailOnFindings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-Finding {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]] $Findings,
        [Parameter(Mandatory)][string] $Finding
    )

    $Findings.Add($Finding)
}

$referenceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $RepositoryRoot) { $RepositoryRoot = $referenceRoot }
$repositoryRootFull = [System.IO.Path]::GetFullPath($RepositoryRoot)
if (-not (Test-Path -LiteralPath $repositoryRootFull -PathType Container)) {
    throw "RepositoryRoot must be an existing directory: '$repositoryRootFull'."
}

if (-not $PolicyPath) { $PolicyPath = Join-Path $referenceRoot 'portfolio/release-integrity.json' }
$policyFull = [System.IO.Path]::GetFullPath($PolicyPath)
$policySchema = Join-Path $referenceRoot 'schemas/release-integrity.schema.json'
$policyRaw = Get-Content -LiteralPath $policyFull -Raw
if (-not ($policyRaw | Test-Json -SchemaFile $policySchema -ErrorAction Stop)) {
    throw 'The release integrity contract does not satisfy its schema.'
}
$policy = $policyRaw | ConvertFrom-Json
$findings = [System.Collections.Generic.List[string]]::new()

$securityPath = Join-Path $repositoryRootFull ([string] $policy.securityPolicy.path)
if (-not (Test-Path -LiteralPath $securityPath -PathType Leaf)) {
    Add-Finding -Findings $findings -Finding 'securityPolicyMissing'
}
else {
    $securityText = Get-Content -LiteralPath $securityPath -Raw
    foreach ($heading in @($policy.securityPolicy.requiredHeadings)) {
        $headingPattern = '(?m)^\s*' + [regex]::Escape([string] $heading) + '\s*$'
        if ($securityText -notmatch $headingPattern) {
            Add-Finding -Findings $findings -Finding "securityPolicyHeadingMissing:$heading"
        }
    }
}

$workflowPath = Join-Path $repositoryRootFull ([string] $policy.artifacts.workflowPath)
if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
    Add-Finding -Findings $findings -Finding 'releaseAttestationWorkflowMissing'
}
else {
    $workflowText = Get-Content -LiteralPath $workflowPath -Raw
    if ($workflowText -notmatch '(?m)^\s*on:\s*$' -or $workflowText -notmatch '(?m)^\s+tags:\s*$') {
        Add-Finding -Findings $findings -Finding 'releaseTagTriggerMissing'
    }
    if ($workflowText -notmatch '(?m)^\s*uses:\s*actions/attest@[0-9a-f]{40}\s+#') {
        Add-Finding -Findings $findings -Finding 'attestationActionUnpinnedOrMissing'
    }
    if ($workflowText -notmatch '(?m)^\s*uses:\s*actions/upload-artifact@[0-9a-f]{40}\s+#') {
        Add-Finding -Findings $findings -Finding 'releaseBundleUploadUnpinnedOrMissing'
    }
    foreach ($permission in 'contents: read', 'id-token: write', 'attestations: write') {
        if ($workflowText -notmatch ('(?m)^\s*' + [regex]::Escape($permission) + '\s*$')) {
            Add-Finding -Findings $findings -Finding "releaseWorkflowPermissionMissing:$permission"
        }
    }
    if ($workflowText -notmatch '(?m)^\s*subject-path:\s*') {
        Add-Finding -Findings $findings -Finding 'attestationSubjectMissing'
    }
    if ($workflowText -notmatch 'git/tags/|verification\.verified') {
        Add-Finding -Findings $findings -Finding 'signedTagVerificationMissing'
    }
    if ($workflowText -notmatch 'git merge-base --is-ancestor') {
        Add-Finding -Findings $findings -Finding 'releaseBranchAncestryVerificationMissing'
    }

    foreach ($match in [regex]::Matches($workflowText, '(?im)^\s*uses:\s*([^@\s]+)@([^\s#]+)')) {
        $action = [string] $match.Groups[1].Value
        $revision = [string] $match.Groups[2].Value
        if ($revision -notmatch '^[0-9a-f]{40}$') {
            Add-Finding -Findings $findings -Finding "workflowActionUnpinned:$action@$revision"
        }
    }
}

if ($Tag) {
    $tagObject = @(& git -C $repositoryRootFull rev-parse --verify "$Tag^{tag}" 2>$null)
    if ($LASTEXITCODE -ne 0 -or $tagObject.Count -eq 0) {
        Add-Finding -Findings $findings -Finding "annotatedTagMissing:$Tag"
    }
    else {
        & git -C $repositoryRootFull tag -v $Tag 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Add-Finding -Findings $findings -Finding "tagSignatureUnverified:$Tag"
        }
    }
}

$result = [pscustomobject] [ordered]@{
    repositoryRoot = $repositoryRootFull
    tag = if ($Tag) { $Tag } else { $null }
    enforcement = [string] $policy.enforcement
    state = if ($findings.Count -eq 0) { 'current' } else { 'findings' }
    findings = @($findings)
}

if ($AsJson) { $result | ConvertTo-Json -Depth 10 }
else { $result }

if ($FailOnFindings -and $findings.Count -gt 0) {
    throw 'Release integrity findings were detected.'
}
