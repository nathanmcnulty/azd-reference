Set-StrictMode -Version Latest

function Test-AzdGitHubWorkflowActionPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $WorkflowContents,

        [AllowNull()][AllowEmptyCollection()][string[]] $AllowedActionPatterns = @(),

        [AllowEmptyString()][string] $RepositoryOwner = '',

        [bool] $GitHubOwnedActionsAllowed = $true
    )

    $findings = [System.Collections.Generic.List[string]]::new()
    $allowedPatterns = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $actionReferenceCount = 0

    foreach ($pattern in $AllowedActionPatterns) {
        if ($pattern -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@\*$') {
            $findings.Add("invalidActionAllowlistPattern:$pattern")
            continue
        }
        if (-not $allowedPatterns.Add($pattern)) {
            $findings.Add("duplicateActionAllowlistPattern:$pattern")
        }
    }

    foreach ($workflow in $WorkflowContents) {
        $path = [string] $workflow.path
        $lineNumber = 0
        $runBlockIndent = -1
        foreach ($line in ([string] $workflow.content -split "`r?`n")) {
            $lineNumber++
            if ($runBlockIndent -ge 0) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $lineIndent = ([regex]::Match($line, '^\s*')).Value.Length
                if ($lineIndent -gt $runBlockIndent) { continue }
                $runBlockIndent = -1
            }
            if ($line -match '^(?<indent>\s*)run\s*:\s*[|>]') {
                $runBlockIndent = $Matches.indent.Length
                continue
            }
            if ($line -notmatch '^\s*uses\s*:\s*(?<reference>.*)$') { continue }
            $actionReferenceCount++

            $reference = [string] $Matches.reference
            $reference = $reference -replace '\s+#.*$', ''
            $reference = $reference.Trim()
            if ($reference.Length -ge 2 -and
                (($reference.StartsWith('"') -and $reference.EndsWith('"')) -or
                ($reference.StartsWith("'") -and $reference.EndsWith("'")))) {
                $reference = $reference.Substring(1, $reference.Length - 2)
            }
            if ([string]::IsNullOrWhiteSpace($reference)) {
                $findings.Add("emptyActionReference:$path`:$lineNumber")
                continue
            }

            if ($reference.StartsWith('./', [System.StringComparison]::Ordinal) -or
                $reference.StartsWith('$/', [System.StringComparison]::Ordinal)) {
                continue
            }

            if ($reference.StartsWith('docker://', [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($reference -notmatch '@sha256:[0-9a-fA-F]{64}$') {
                    $findings.Add("containerActionImageNotDigestPinned:$path`:$lineNumber`:$reference")
                }
                continue
            }

            $separator = $reference.LastIndexOf('@')
            if ($separator -lt 1) {
                $findings.Add("unpinnedActionReference:$path`:$lineNumber`:$reference")
                continue
            }

            $actionPath = $reference.Substring(0, $separator)
            $revision = $reference.Substring($separator + 1)
            if ($revision -notmatch '^[0-9a-fA-F]{40}$') {
                $findings.Add("unpinnedActionReference:$path`:$lineNumber`:$reference")
            }

            $segments = $actionPath.Split('/')
            if ($segments.Count -lt 2 -or
                [string]::IsNullOrWhiteSpace($segments[0]) -or
                [string]::IsNullOrWhiteSpace($segments[1])) {
                $findings.Add("malformedActionReference:$path`:$lineNumber`:$reference")
                continue
            }

            $actionRepository = "$($segments[0])/$($segments[1])"
            $expectedPattern = "$actionRepository@*"
            $githubOwned = $segments[0] -in @('actions', 'github')
            if ($githubOwned -and $GitHubOwnedActionsAllowed) { continue }
            if (-not [string]::IsNullOrWhiteSpace($RepositoryOwner) -and
                $segments[0].Equals($RepositoryOwner, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            if (-not $allowedPatterns.Contains($expectedPattern)) {
                $findings.Add("actionNotExplicitlyAllowed:$path`:$lineNumber`:$actionRepository")
            }
        }
    }
    [pscustomobject]@{
        state = if ($findings.Count -eq 0) { 'current' } else { 'findings' }
        actionReferenceCount = $actionReferenceCount
        findings = @($findings)
    }
}

function Compare-AzdGitHubPublicRepositoryRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Registry,

        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $PublicRepositoryNames
    )

    $discovery = $Registry.publicRepositoryDiscovery
    $owner = [string] $discovery.owner
    $prefix = [string] $discovery.namePrefix
    $findings = [System.Collections.Generic.List[string]]::new()
    $registered = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $allRegistered = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $registeredIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($entry in @($Registry.repositories)) {
        $uri = [uri] $entry.repository
        $repositoryOwner = [string] $uri.AbsolutePath.Trim('/').Split('/')[0]
        $repositoryName = [string] $uri.AbsolutePath.Trim('/').Split('/')[1]
        if (-not $registeredIds.Add([string] $entry.id)) {
            $findings.Add("duplicateRepositoryId:$($entry.id)")
        }
        if (-not $repositoryOwner.Equals($owner, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not $repositoryName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $findings.Add("repositoryOutsideDiscoveryScope:$($entry.repository)")
            continue
        }
        if (-not ([string] $entry.id).Equals($repositoryName, [System.StringComparison]::OrdinalIgnoreCase)) {
            $findings.Add("repositoryIdMismatch:$($entry.id):$repositoryName")
        }
        if (-not $allRegistered.Add($repositoryName)) {
            $findings.Add("duplicateRepository:$($entry.repository)")
        }
        if ([string] $entry.visibility -eq 'public') { [void] $registered.Add($repositoryName) }
    }

    $discovered = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($value in $PublicRepositoryNames) {
        $name = [string] $value
        if ($name.Contains('/')) {
            $parts = $name.Trim('/').Split('/')
            if ($parts.Count -ne 2 -or
                -not $parts[0].Equals($owner, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $name = $parts[1]
        }
        if ($name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void] $discovered.Add($name)
        }
    }
    if ($discovered.Count -eq 0) {
        $findings.Add('publicRepositoryDiscoveryReturnedNoMatches')
    }

    $unregistered = @(
        foreach ($name in $discovered) {
            if (-not $registered.Contains($name)) { $name }
        }
    ) | Sort-Object

    foreach ($name in $unregistered) {
        $findings.Add("publicRepositoryUnregistered:$owner/$name")
    }
    $covered = @(
        foreach ($name in $discovered) {
            if ($registered.Contains($name)) { $name }
        }
    ) | Sort-Object

    [pscustomobject][ordered]@{
        repository = 'public-repository-registry'
        visibility = 'public'
        scopeOwner = $owner
        namePrefix = $prefix
        discoveredPublicRepositories = @($discovered | Sort-Object)
        registeredPublicRepositories = @($covered)
        unregisteredPublicRepositories = @($unregistered)
        state = if ($findings.Count -eq 0) { 'current' } else { 'findings' }
        findings = @($findings)
    }
}

Export-ModuleMember -Function Test-AzdGitHubWorkflowActionPolicy, Compare-AzdGitHubPublicRepositoryRegistry
