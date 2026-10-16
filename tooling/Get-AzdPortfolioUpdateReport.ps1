[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $StatusPath,

    [string] $CandidatesPath,

    [string] $SelectionDiagnosticsPath,

    [string] $ConsumerId,

    [string] $SummaryPath,

    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Project recorded observations only. Do not query GitHub, read credentials,
# discover releases, or repeat the selector's eligibility decisions here.
$status = @(Get-Content -LiteralPath $StatusPath -Raw | ConvertFrom-Json)
if ($ConsumerId) { $status = @($status | Where-Object { $_.consumer -ceq $ConsumerId }) }
$selection = if ($SelectionDiagnosticsPath -and (Test-Path -LiteralPath $SelectionDiagnosticsPath -PathType Leaf)) {
    try { Get-Content -LiteralPath $SelectionDiagnosticsPath -Raw | ConvertFrom-Json }
    catch { $null }
} else { $null }
$hasPlan = $CandidatesPath -and (Test-Path -LiteralPath $CandidatesPath -PathType Leaf)
$selectionMatchesScope = $null -ne $selection -and
    $selection.PSObject.Properties.Name -contains 'state' -and $selection.state -is [string] -and
    $selection.PSObject.Properties.Name -contains 'consumer' -and $selection.consumer -is [string] -and
    $selection.consumer -ceq $ConsumerId
$selectionState = if ($selectionMatchesScope -and $selection.state -ceq 'failed') { 'failed' }
    elseif ($selectionMatchesScope -and $selection.state -ceq 'completed' -and $hasPlan) { 'completed' }
    else { 'unknown' }
$candidates = @(if ($selectionState -eq 'completed') {
    Get-Content -LiteralPath $CandidatesPath -Raw | ConvertFrom-Json |
        Where-Object { -not $ConsumerId -or $_.consumer -ceq $ConsumerId }
})
$suppressed = @(if ($selectionState -eq 'completed' -and
        $selection.PSObject.Properties.Name -contains 'excludeOpenPullRequests' -and
        $selection.excludeOpenPullRequests -is [bool] -and $selection.excludeOpenPullRequests -and
        $selection.PSObject.Properties.Name -contains 'suppressed') {
    $selection.suppressed | Where-Object { $null -ne $_ } | Where-Object {
        $names = @($_.PSObject.Properties.Name)
        @('consumer', 'component', 'version', 'repository', 'branch', 'base', 'title', 'pullRequestUrls' | Where-Object { $_ -notin $names }).Count -eq 0
    } | Where-Object { -not $ConsumerId -or $_.consumer -ceq $ConsumerId }
})

$records = @(
    foreach ($entry in $status) {
        $findings = @($entry.findings)
        $blockingFindings = @($findings | Where-Object {
            $_ -ne 'pendingAdoption' -and $_ -notlike 'solutionFileRecommended:*'
        })
        $reasons = [System.Collections.Generic.List[string]]::new()
        $nextActions = [System.Collections.Generic.List[string]]::new()
        $state = [string] $entry.state
        switch ($state) {
            'current' {
                $reasons.Add('The installed version matches the registry pin, or this consumer declares no components.')
                $nextActions.Add('No version update is needed for the current registry declaration.')
            }
            'versionAhead' {
                $reasons.Add('The installed version is ahead of the registry pin.')
                $nextActions.Add('Review the registry pin against the intended reviewed release; never downgrade to manufacture a candidate.')
            }
            'notAdopted' {
                $reasons.Add('The declared component has not been adopted in the consumer lock.')
                $nextActions.Add('Review the explicit adoption and desired version, then clear blockers before preparing adoption.')
            }
            'outdated' {
                $reasons.Add('The installed version is below the approved registry pin.')
                $nextActions.Add('Clear any blockers and review the final candidate before preparation.')
            }
            'unmanagedTargets' {
                $reasons.Add('Canonical targets exist without managed component adoption.')
                $nextActions.Add('Review ownership and reconcile unmanaged targets before adoption.')
            }
            default {
                $reasons.Add("Status prevents automatic selection: $state.")
                $nextActions.Add('Resolve the reported checkout, lock, provenance, or managed-file condition and rerun the audit.')
            }
        }

        foreach ($finding in $blockingFindings) {
            $reasons.Add([string] $finding)
            if ($finding -match '^(desired|installed)ReleaseTag(Missing|Invalid):(?<id>[^@]+)@(?<version>.+)$') {
                $tag = "component/$($Matches.id)/v$($Matches.version)"
                $nextActions.Add("Verify exact tag '$tag' and its committed component manifest using the component release procedure; do not create or move a tag to clear this report.")
            }
            elseif ($finding -like 'installedSourceRevisionMismatch:*') {
                $nextActions.Add("Reconcile the lock sourceRevision with the exact installed tag commit: $finding.")
            }
            else {
                $nextActions.Add("Resolve audit finding '$finding' before treating this record as ready.")
            }
        }

        $candidate = @($candidates | Where-Object {
            $_.consumer -ceq $entry.consumer -and $_.component -ceq $entry.component -and $_.version -ceq $entry.desiredVersion
        })
        $existing = @($suppressed | Where-Object {
            $_.consumer -ceq $entry.consumer -and $_.component -ceq $entry.component -and $_.version -ceq $entry.desiredVersion -and
            $_.repository -ceq $entry.repository -and
            $_.branch -ceq "codex/update-$($entry.consumer)-$($entry.component)-v$($entry.desiredVersion)" -and
            $_.title -ceq "chore: update $($entry.component) to $($entry.desiredVersion)" -and @($_.pullRequestUrls).Count -gt 0
        })
        $decision = if ($candidate.Count -gt 0) { 'candidate' }
            elseif ($blockingFindings.Count -gt 0) { 'blocked' }
            elseif ($state -eq 'current') { 'current' }
            elseif ($state -eq 'versionAhead') { 'registryPinReview' }
            elseif ($state -in 'outdated', 'notAdopted' -and $existing.Count -gt 0) { 'existingPullRequest' }
            elseif ($state -in 'outdated', 'notAdopted') { 'notSelected' }
            else { 'blocked' }
        if ($decision -eq 'existingPullRequest') {
            $reasons.Add('Successful selection observed an open pull request with the exact expected head, base, and title.')
            $nextActions.Add('Review the existing pull request rather than creating a duplicate.')
        }
        elseif ($decision -eq 'notSelected') {
            $reasons.Add('This record is absent from the final candidates; exact existing-PR suppression is not established.')
            $nextActions.Add('Inspect the selection result or error; do not infer suppression from an empty or missing plan.')
        }

        $component = [string] $entry.component
        $desiredTag = if ($component) { "component/$component/v$($entry.desiredVersion)" } else { $null }
        $installedTag = if ($component -and $entry.installedVersion) { "component/$component/v$($entry.installedVersion)" } else { $null }
        $desiredProvenance = if (-not $component) { 'notApplicable' }
            elseif (@($findings | Where-Object { $_ -like 'desiredReleaseTagMissing:*' }).Count) { 'missing' }
            elseif (@($findings | Where-Object { $_ -like 'desiredReleaseTagInvalid:*' }).Count) { 'invalid' }
            else { 'valid' }
        $installedProvenance = if (-not $installedTag) { 'notApplicable' }
            elseif (@($findings | Where-Object { $_ -like 'installedReleaseTagMissing:*' }).Count) { 'missing' }
            elseif (@($findings | Where-Object { $_ -like 'installedReleaseTagInvalid:*' }).Count) { 'invalid' }
            elseif ($state -in 'current', 'outdated', 'versionAhead', 'sourceRevisionMismatch') { 'valid' }
            else { 'notAssessed' }
        $installedRevision = if (@($findings | Where-Object { $_ -like 'installedSourceRevisionMismatch:*' }).Count) { 'mismatch' }
            elseif ($installedProvenance -eq 'valid') { 'matchesTag' }
            else { 'notAssessed' }

        [pscustomobject] [ordered]@{
            consumer = $entry.consumer
            repository = $entry.repository
            component = $entry.component
            desiredVersion = $entry.desiredVersion
            installedVersion = $entry.installedVersion
            state = $state
            findings = $findings
            decision = $decision
            reasons = @($reasons.ToArray())
            nextActions = @($nextActions.ToArray() | Select-Object -Unique)
            localProvenance = [ordered]@{
                desiredTag = $desiredTag
                desiredTagAndManifest = $desiredProvenance
                installedTag = $installedTag
                installedTagAndManifest = $installedProvenance
                installedRevision = $installedRevision
            }
            existingPullRequests = @(if ($decision -eq 'existingPullRequest') { $existing })
        }
    }
)

$report = [pscustomobject] [ordered]@{
    schemaVersion = '1.0'
    consumer = $ConsumerId
    selectionState = $selectionState
    selectionError = if ($selectionMatchesScope -and $selection.PSObject.Properties.Name -contains 'error') { $selection.error } else { $null }
    candidateCount = if ($selectionState -eq 'completed') { $candidates.Count } else { $null }
    candidates = $candidates
    records = $records
    evidenceLimits = [ordered]@{
        sourceAvailability = 'notAssessed: canonical source on main is not a release or consumer adoption; only registry declarations are covered.'
        localProvenance = 'Local tag and committed-manifest observations from Get-AzdPortfolioStatus only.'
        signedReleaseAcceptance = 'unverified: verify the signed annotated tag and exact attestation workflow using docs/component-releases.md.'
        appReadiness = 'unknown: no credentials or installation permissions were inspected.'
        reviewerReadiness = 'unknown: the effective required-reviewer gate was not inspected.'
        publicationProof = 'notEstablished: a plan, current version, or zero candidates does not prove preparation or App publication.'
    }
}

if ($SummaryPath) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('## Portfolio update readiness')
    $scope = if ($ConsumerId) { $ConsumerId } else { 'all registered consumers' }
    $lines.Add("Scope: $scope. Candidate selection: $selectionState.")
    if ($selectionState -eq 'completed') { $lines.Add("Final candidate count: $($candidates.Count).") }
    else { $lines.Add('No completed final candidate list is available; this is not a successful zero-candidate result.') }
    if ($report.selectionError) { $lines.Add("Selection error: $($report.selectionError)") }
    if ($records.Count -eq 0) { $lines.Add('No status records were available in this scope; readiness is unknown.') }
    foreach ($record in $records) {
        $label = if ($record.component) { "$($record.consumer)/$($record.component)" } else { [string] $record.consumer }
        $lines.Add("- ${label}: $($record.state); $($record.decision). Installed: $($record.installedVersion); desired: $($record.desiredVersion).")
        foreach ($reason in $record.reasons) { $lines.Add("  - $reason") }
        foreach ($action in $record.nextActions) { $lines.Add("  - Next: $action") }
        foreach ($pullRequest in $record.existingPullRequests) {
            foreach ($url in $pullRequest.pullRequestUrls) { $lines.Add("  - Existing PR: $url") }
        }
    }
    $lines.Add('')
    foreach ($limit in $report.evidenceLimits.Values) { $lines.Add("- $limit") }
    $lines | Set-Content -LiteralPath $SummaryPath -Encoding utf8NoBOM
}

if ($AsJson) { $report | ConvertTo-Json -Depth 12 }
else { $report }
