[CmdletBinding(DefaultParameterSetName = 'StaticAudit')]
param(
    [string] $RepositoryRoot,

    [Parameter(ParameterSetName = 'StaticAudit')]
    [string] $PolicyPath,

    [Parameter(ParameterSetName = 'StaticAudit')]
    [string] $Tag,

    [Parameter(Mandatory, ParameterSetName = 'ComponentRelease')]
    [switch] $AcceptComponentRelease,

    [Parameter(Mandatory, ParameterSetName = 'ComponentRelease')]
    [ValidateNotNullOrEmpty()]
    [string] $ExpectedRepository,

    [Parameter(Mandatory, ParameterSetName = 'ComponentRelease')]
    [ValidateNotNullOrEmpty()]
    [string] $ExpectedTag,

    [Parameter(Mandatory, ParameterSetName = 'ComponentRelease')]
    [ValidatePattern('(?-i)^[0-9a-f]{40}\z')]
    [string] $ExpectedCommit,

    [Parameter(Mandatory, ParameterSetName = 'ComponentRelease')]
    [ValidateNotNullOrEmpty()]
    [string] $BundlePath,

    [switch] $AsJson,

    [Parameter(ParameterSetName = 'StaticAudit')]
    [switch] $FailOnFindings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

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

# This opt-in gate is shared by release publication and adoption preflight. It
# consumes an already supplied bundle; it never discovers/downloads a release,
# creates a tag, changes a consumer, or treats a green workflow as acceptance.
if ($PSCmdlet.ParameterSetName -eq 'ComponentRelease') {
    if (-not $AcceptComponentRelease) { throw '-AcceptComponentRelease must be enabled.' }
    if ($ExpectedRepository -cne 'nathanmcnulty/azd-reference') {
        throw 'Component release acceptance requires the exact repository nathanmcnulty/azd-reference.'
    }
    if ($env:GH_HOST -and $env:GH_HOST -cne 'github.com') {
        throw 'Component release acceptance requires GH_HOST to be unset or github.com.'
    }
    # SemVer identifiers may not be empty and numeric prerelease identifiers may
    # not have leading zeroes. Keep the entire Git ref under this validated tag.
    $number = '(?:0|[1-9][0-9]*)'
    $prerelease = '(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
    $versionPattern = "$number\.$number\.$number(?:-$prerelease(?:\.$prerelease)*)?"
    if ($ExpectedTag -cnotmatch "^component/(?<component>[a-z][a-z0-9-]{1,62}[a-z0-9])/v(?<version>$versionPattern)\z") {
        throw 'ExpectedTag must be component/<component-id>/v<valid-semantic-version>.'
    }
    $component = $Matches.component
    $version = $Matches.version
    $tagReference = "refs/tags/$ExpectedTag"
    $bundleFull = [System.IO.Path]::GetFullPath($BundlePath)
    if (-not (Test-Path -LiteralPath $bundleFull -PathType Leaf)) {
        throw "The supplied release bundle is unavailable: '$bundleFull'."
    }
    $bundleHash = (Get-FileHash -LiteralPath $bundleFull -Algorithm SHA256).Hash.ToLowerInvariant()

    function Invoke-ReleaseGit {
        param([Parameter(Mandatory)][string[]] $Arguments)

        $output = @(& git --no-replace-objects -C $repositoryRootFull @Arguments 2>$null)
        if ($LASTEXITCODE -ne 0) {
            throw "Local release evidence is unavailable: git $($Arguments -join ' ')."
        }
        $output
    }

    function ConvertFrom-ReleaseJson {
        param([Parameter(Mandatory)][string] $Text)

        $value = ConvertFrom-Json -InputObject $Text -AsHashtable -NoEnumerate -ErrorAction Stop
        if ($value -isnot [System.Collections.IDictionary]) {
            throw 'Release evidence must be a JSON object.'
        }
        $value
    }

    function Get-ReleaseApiObject {
        param([Parameter(Mandatory)][string] $Endpoint)

        $output = @(& gh api --hostname github.com $Endpoint 2>$null)
        if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) {
            throw "GitHub release evidence is unavailable: '$Endpoint'."
        }
        ConvertFrom-ReleaseJson -Text ($output -join "`n")
    }

    $localTagObject = @(Invoke-ReleaseGit -Arguments @('rev-parse', '--verify', '--quiet', '--end-of-options', "$tagReference^{tag}"))
    $localCommit = @(Invoke-ReleaseGit -Arguments @('rev-parse', '--verify', '--quiet', '--end-of-options', "$tagReference^{commit}"))
    if ($localTagObject.Count -ne 1 -or [string] $localTagObject[0] -cnotmatch '^[0-9a-f]{40}$' -or
        $localCommit.Count -ne 1 -or [string] $localCommit[0] -cne $ExpectedCommit) {
        throw 'The local annotated tag does not match the expected release commit.'
    }

    # Read manifests from the reviewed immutable commit, never the working tree.
    $manifestPaths = @(Invoke-ReleaseGit -Arguments @('ls-tree', '-r', '--name-only', $ExpectedCommit, '--', 'components') |
        Where-Object { $_ -cmatch '^components/(?:[^/]+/)+component\.json$' })
    $matchingManifests = @(
        foreach ($path in $manifestPaths) {
            $manifestText = @(Invoke-ReleaseGit -Arguments @('show', "${ExpectedCommit}:$path")) -join "`n"
            $manifest = ConvertFrom-ReleaseJson -Text $manifestText
            if ($manifest.id -is [string] -and $manifest.id -ceq $component) {
                if ($manifest.version -isnot [string] -or $manifest.version -cne $version) {
                    throw 'The tagged component manifest version does not match the expected tag.'
                }
                [string] $path
            }
        }
    )
    if ($matchingManifests.Count -ne 1) {
        throw 'The release commit must contain exactly one matching component manifest.'
    }

    $tagRef = Get-ReleaseApiObject -Endpoint "repos/$ExpectedRepository/git/ref/tags/$ExpectedTag"
    if ($tagRef.ref -isnot [string] -or $tagRef.ref -cne $tagReference -or
        $tagRef.object -isnot [System.Collections.IDictionary] -or
        $tagRef.object.type -isnot [string] -or $tagRef.object.type -cne 'tag' -or
        $tagRef.object.sha -isnot [string] -or $tagRef.object.sha -cne [string] $localTagObject[0]) {
        throw 'The remote reference does not match the local annotated release tag.'
    }
    $tagObject = Get-ReleaseApiObject -Endpoint "repos/$ExpectedRepository/git/tags/$($tagRef.object.sha)"
    if ($tagObject.sha -isnot [string] -or $tagObject.sha -cne $tagRef.object.sha -or
        $tagObject.tag -isnot [string] -or $tagObject.tag -cne $ExpectedTag -or
        $tagObject.object -isnot [System.Collections.IDictionary] -or
        $tagObject.object.type -isnot [string] -or $tagObject.object.type -cne 'commit' -or
        $tagObject.object.sha -isnot [string] -or $tagObject.object.sha -cne $ExpectedCommit -or
        $tagObject.verification -isnot [System.Collections.IDictionary] -or
        $tagObject.verification.verified -isnot [bool] -or $tagObject.verification.verified -ne $true) {
        throw 'GitHub did not verify the exact signed tag and expected release commit.'
    }

    & gh attestation verify $bundleFull `
        --hostname github.com `
        --repo $ExpectedRepository `
        --signer-workflow "$ExpectedRepository/.github/workflows/release-attestation.yml" `
        --signer-digest $ExpectedCommit `
        --source-ref $tagReference `
        --source-digest $ExpectedCommit `
        --predicate-type 'https://slsa.dev/provenance/v1' `
        --cert-oidc-issuer 'https://token.actions.githubusercontent.com' `
        --deny-self-hosted-runners 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Release bundle attestation verification failed or is unavailable.'
    }
    if ((Get-FileHash -LiteralPath $bundleFull -Algorithm SHA256).Hash.ToLowerInvariant() -cne $bundleHash) {
        throw 'The supplied release bundle changed during attestation verification.'
    }

    $result = [pscustomobject] [ordered]@{
        repositoryRoot = $repositoryRootFull
        repository = $ExpectedRepository
        tag = $ExpectedTag
        component = $component
        version = $version
        revision = $ExpectedCommit
        manifest = $matchingManifests[0]
        tagObject = [string] $tagRef.object.sha
        bundlePath = $bundleFull
        bundleSha256 = $bundleHash
        attestationVerified = $true
        evidenceScope = 'signed-tag-and-attested-bundle'
        state = 'accepted'
    }
    if ($AsJson) { $result | ConvertTo-Json -Depth 10 }
    else { $result }
    return
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
