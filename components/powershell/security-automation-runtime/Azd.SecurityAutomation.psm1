Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SecurityAccessToken {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('https://graph.microsoft.com','https://management.azure.com/','https://storage.azure.com/','https://api.security.microsoft.com')][string]$Resource,
        [ValidateSet('AzureCli','ManagedIdentity')][string]$AuthMode = 'ManagedIdentity', [string]$TenantId)
    if ($AuthMode -eq 'AzureCli') {
        $arguments = @('account','get-access-token','--resource',$Resource,'--output','json','--only-show-errors')
        if ($TenantId) { $arguments += @('--tenant',$TenantId) }
        $raw = & az @arguments 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'No usable Azure CLI session. Authenticate through the normal browser or account broker.' }
        $result = ($raw -join "`n") | ConvertFrom-Json
        if ($TenantId -and $result.tenant -ne $TenantId) { throw 'Token tenant does not match the selected tenant.' }
        return $result.accessToken
    }
    if (-not $env:IDENTITY_ENDPOINT -or -not $env:IDENTITY_HEADER) { throw 'Managed identity endpoint is unavailable.' }
    $endpoint = [uri]$env:IDENTITY_ENDPOINT
    $flexEndpoint = $endpoint.Scheme -ceq 'http' -and $endpoint.Host -ceq '169.254.255.2' -and $endpoint.Port -eq 8081 -and $endpoint.AbsolutePath -ceq '/msi/token'
    if ($endpoint.Scheme -notin @('http','https') -or $endpoint.UserInfo -or $endpoint.Fragment -or (-not $endpoint.IsLoopback -and -not $flexEndpoint)) {
        throw 'Managed identity endpoint must be loopback or the Azure Flex identity endpoint.'
    }
    $separator = if ($endpoint.Query) { '&' } else { '?' }
    $uri = "$endpoint${separator}resource=$([uri]::EscapeDataString($Resource))&api-version=2019-08-01"
    $result = Invoke-RestMethod -Uri $uri -Headers @{ 'X-IDENTITY-HEADER'=$env:IDENTITY_HEADER; Metadata='true' } -TimeoutSec 30 -MaximumRedirection 0
    if (-not $result.access_token) { throw 'Managed identity did not return a token.' }
    if ($TenantId) {
        try {
            $payload = $result.access_token.Split('.')[1].Replace('-','+').Replace('_','/')
            $payload = $payload.PadRight($payload.Length + ((4 - $payload.Length % 4) % 4), '=')
            $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
            if ($claims.tid -ne $TenantId) { throw 'Wrong tenant.' }
        } catch { throw 'Managed identity token does not match the selected tenant.' }
    }
    return $result.access_token
}

function Invoke-SecurityGraphRead {
    [CmdletBinding()]
    param([Parameter(Mandatory)][uri]$Uri, [ValidateSet('GET','POST')][string]$Method='GET', [object]$Body,
        [ValidateSet('AzureCli','ManagedIdentity')][string]$AuthMode='AzureCli', [string]$TenantId,
        [ValidateRange(1,1000)][int]$MaximumPages=100)
    # POST is reserved for read-oriented hunting. Policy and group writes are deliberately absent.
    if ($Uri.Scheme -ne 'https' -or $Uri.Host -ne 'graph.microsoft.com' -or $Uri.UserInfo -or $Uri.Port -ne 443) { throw 'Only Microsoft Graph HTTPS URLs are accepted.' }
    if ($Uri.AbsolutePath -notmatch '^/(v1\.0|beta)/') { throw 'A versioned Graph endpoint is required.' }
    if ($Method -eq 'POST' -and $Uri.AbsolutePath -notmatch '^/(v1\.0|beta)/security/runHuntingQuery$') { throw 'POST is allowed only for read-only advanced hunting.' }
    $token = Get-SecurityAccessToken -Resource 'https://graph.microsoft.com' -AuthMode $AuthMode -TenantId $TenantId
    $next = $Uri.AbsoluteUri
    $rows = [System.Collections.Generic.List[object]]::new()
    for ($page=0; $next; $page++) {
        if ($page -ge $MaximumPages) { throw 'Graph page limit exceeded; evidence is incomplete.' }
        $pageUri = [uri]$next
        if ($pageUri.Scheme -ne 'https' -or $pageUri.Host -ne $Uri.Host -or $pageUri.UserInfo -or $pageUri.Port -ne 443 -or $pageUri.AbsolutePath -notmatch '^/(v1\.0|beta)/') { throw 'Unsafe Graph pagination URL.' }
        if ($Method -eq 'POST' -and $pageUri.AbsolutePath -notmatch '^/(v1\.0|beta)/security/runHuntingQuery$') { throw 'Unsafe POST pagination endpoint.' }
        $response = $null
        for ($attempt=0; $attempt -lt 4; $attempt++) {
            try {
                $requestParameters = @{ Uri=$pageUri; Method=$Method; Headers=@{Authorization="Bearer $token"}; TimeoutSec=120; MaximumRedirection=0 }
                if ($Method -eq 'POST') { $requestParameters.Body=$Body | ConvertTo-Json -Depth 50 -Compress; $requestParameters.ContentType='application/json' }
                $response = Invoke-RestMethod @requestParameters
                break
            } catch {
                $status = if ($_.Exception.PSObject.Properties.Name -contains 'Response' -and $_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
                if ($status -notin @(429,502,503,504) -or $attempt -eq 3) { throw "Graph read failed (HTTP $status); no evidence was accepted." }
                Start-Sleep -Seconds ([math]::Min(30,[math]::Pow(2,$attempt+1)))
            }
        }
        if ($response.PSObject.Properties.Name -contains 'value') {
            foreach ($row in $response.value) { $rows.Add($row) }
            $next = if ($response.PSObject.Properties.Name -contains '@odata.nextLink') { $response.'@odata.nextLink' } else { $null }
        } else { return $response }
    }
    return $rows.ToArray()
}

function Resolve-SecurityBundlePath {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$RelativePath)
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)' -or $RelativePath -match ':') { throw 'Bundle paths must be relative without traversal.' }
    $base = [IO.Path]::GetFullPath($Root)
    $path = [IO.Path]::GetFullPath((Join-Path $base $RelativePath))
    if (-not $path.StartsWith($base.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Bundle path escapes its root.' }
    $cursor = $base
    foreach ($part in @('') + @($RelativePath -split '[\\/]')) {
        if ($part) { $cursor = Join-Path $cursor $part }
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Bundle path traverses a link.' }
    }
    return $path
}

function Invoke-SecurityBundle {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BundleRoot,[Parameter(Mandatory)][string]$ConfigurationPath,
        [Parameter(Mandatory)][string]$InputDirectory,[Parameter(Mandatory)][string]$OutputDirectory)
    $config = Get-Content -LiteralPath $ConfigurationPath -Raw | ConvertFrom-Json
    if ($config.schemaVersion -ne '1.0' -or @($config.solutions).Count -eq 0) { throw 'Invalid security bundle configuration.' }
    $ids = @{}
    foreach ($solution in $config.solutions) {
        if ($solution.id -notmatch '^azd-[a-z0-9-]+$' -or $ids.ContainsKey($solution.id)) { throw 'Invalid or duplicate solution id.' }
        $ids[$solution.id]=$true
        $runner = Resolve-SecurityBundlePath -Root $BundleRoot -RelativePath $solution.runner
        $evidencePath = Resolve-SecurityBundlePath -Root $InputDirectory -RelativePath $solution.input
        $output = Resolve-SecurityBundlePath -Root $OutputDirectory -RelativePath $solution.id
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) { throw "Missing evidence for $($solution.id)." }
        New-Item -ItemType Directory -Path $output -Force | Out-Null
        & $runner -InputPath $evidencePath -OutputDirectory $output
    }
}

function Invoke-SecurityBlobTransfer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9]{3,24}$')][string]$Account,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$')][string]$Container,
        [Parameter(Mandatory)][string]$Blob,[Parameter(Mandatory)][string]$Path,
        [ValidateSet('Download','Upload')][string]$Direction='Download',
        [ValidateSet('AzureCli','ManagedIdentity')][string]$AuthMode='ManagedIdentity')
    if (-not $Blob -or $Blob -match '(^|/)\.\.(/|$)' -or $Blob -match '[\\\x00-\x1f]') { throw 'Invalid blob name.' }
    $encoded = (@($Blob -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
    $uri = "https://$Account.blob.core.windows.net/$Container/$encoded"
    $token = Get-SecurityAccessToken -Resource 'https://storage.azure.com/' -AuthMode $AuthMode
    $headers = @{ Authorization="Bearer $token"; 'x-ms-version'='2023-11-03'; 'x-ms-date'=[DateTime]::UtcNow.ToString('R') }
    try {
        if ($Direction -eq 'Download') { Invoke-WebRequest -Uri $uri -Headers $headers -OutFile $Path -TimeoutSec 120 -MaximumRedirection 0 | Out-Null }
        else {
            $headers['x-ms-blob-type']='BlockBlob'
            if ($Container -eq 'packages') { $headers['If-None-Match']='*' }
            Invoke-WebRequest -Uri $uri -Headers $headers -Method Put -InFile $Path -TimeoutSec 120 -MaximumRedirection 0 | Out-Null
        }
    } catch {
        $status = if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($Direction -eq 'Upload' -and $Container -eq 'packages' -and $status -in 409,412) {
            $existing = Join-Path ([IO.Path]::GetTempPath()) ('security-existing-'+[guid]::NewGuid().ToString('N')+'.zip')
            try {
                Invoke-SecurityBlobTransfer -Account $Account -Container $Container -Blob $Blob -Path $existing -Direction Download -AuthMode $AuthMode
                if ((Get-FileHash -LiteralPath $existing).Hash -ne (Get-FileHash -LiteralPath $Path).Hash) { throw 'Existing immutable package differs.' }
                return
            } catch { throw 'Immutable package verification failed; publication stopped.' }
            finally { if (Test-Path -LiteralPath $existing) { Remove-Item -LiteralPath $existing } }
        }
        throw "Evidence blob $Direction failed; output is incomplete."
    }
}

function Get-SecurityBundleProvenance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BundleRoot,[Parameter(Mandatory)][string]$ConfigurationPath)
    $manifestPath = Resolve-SecurityBundlePath -Root $BundleRoot -RelativePath 'bundle-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Hosted package requires bundle-manifest.json.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne '1.0' -or @($manifest.files).Count -eq 0) { throw 'Invalid hosted package manifest.' }
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $manifest.files) {
        $path = Resolve-SecurityBundlePath -Root $BundleRoot -RelativePath $file.path
        if (-not $paths.Add($path) -or $file.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
            -not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) {
            throw 'Hosted package manifest has duplicate, missing, or changed files.'
        }
    }
    $configuration = Resolve-SecurityBundlePath -Root $BundleRoot -RelativePath ([IO.Path]::GetRelativePath([IO.Path]::GetFullPath($BundleRoot),[IO.Path]::GetFullPath($ConfigurationPath)))
    if (-not $paths.Contains($configuration)) { throw 'Hosted configuration is absent from the package manifest.' }
    $config = Get-Content -LiteralPath $configuration -Raw | ConvertFrom-Json
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($solution in $config.solutions) {
        if (-not $ids.Add($solution.id) -or -not $paths.Contains((Resolve-SecurityBundlePath -Root $BundleRoot -RelativePath $solution.runner))) {
            throw 'Hosted runner is missing from the package manifest or engine IDs are duplicated.'
        }
    }
    $sources = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($source in $manifest.sourceCommits) {
        if (-not $ids.Contains($source.solutionId) -or -not $sources.Add($source.solutionId) -or
            $source.sourceRevision -cnotmatch '^[a-f0-9]{40}$' -or $source.runtimeRevision -cnotmatch '^[a-f0-9]{40}$') {
            throw 'Hosted package source provenance is invalid.'
        }
    }
    if ($ids.Count -eq 0 -or -not $ids.SetEquals($sources)) { throw 'Hosted package source provenance is incomplete.' }
    [pscustomobject]@{
        manifestSha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        sourceCommits=@($manifest.sourceCommits)
    }
}

function Invoke-HostedSecurityBundle {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BundleRoot,[Parameter(Mandatory)][string]$ConfigurationPath,
        [Parameter(Mandatory)][string]$Account,[string]$InputContainer='evidence',[string]$OutputContainer='reports')
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('security-run-'+[guid]::NewGuid().ToString('N'))
    $inputs = Join-Path $temporary 'inputs'; $outputs = Join-Path $temporary 'outputs'
    New-Item -ItemType Directory -Path $inputs,$outputs -Force | Out-Null
    try {
        $provenance = Get-SecurityBundleProvenance -BundleRoot $BundleRoot -ConfigurationPath $ConfigurationPath
        $config = Get-Content -LiteralPath $ConfigurationPath -Raw | ConvertFrom-Json
        $downloadedPaths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($solution in $config.solutions) {
            $path = Resolve-SecurityBundlePath -Root $inputs -RelativePath $solution.input
            if (-not $downloadedPaths.Add($path)) { throw 'Evidence input paths must be unique across engines.' }
            New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
            Invoke-SecurityBlobTransfer -Account $Account -Container $InputContainer -Blob $solution.input -Path $path
            if ($solution.PSObject.Properties.Name -contains 'artifactFiles') {
                foreach ($artifact in $solution.artifactFiles) {
                    if ($artifact.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Approved evidence artifact requires a SHA256 hash.' }
                    $artifactPath=Resolve-SecurityBundlePath -Root $inputs -RelativePath $artifact.path
                    if (-not $downloadedPaths.Add($artifactPath)) { throw 'Evidence artifact paths must be unique.' }
                    New-Item -ItemType Directory -Path (Split-Path $artifactPath) -Force | Out-Null
                    Invoke-SecurityBlobTransfer -Account $Account -Container $InputContainer -Blob $artifact.blob -Path $artifactPath
                    if ((Get-FileHash -LiteralPath $artifactPath).Hash.ToLowerInvariant() -ne $artifact.sha256) { throw 'Approved evidence artifact hash mismatch.' }
                }
            }
        }
        $inputBindings=@($downloadedPaths | Sort-Object | ForEach-Object {
            @{path=[IO.Path]::GetRelativePath($inputs,$_).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()}
        })
        $previousEvidenceRoot=$env:SECURITY_EVIDENCE_ROOT
        try {
            $env:SECURITY_EVIDENCE_ROOT=$inputs
            Invoke-SecurityBundle -BundleRoot $BundleRoot -ConfigurationPath $ConfigurationPath -InputDirectory $inputs -OutputDirectory $outputs
        } finally { $env:SECURITY_EVIDENCE_ROOT=$previousEvidenceRoot }
        $remainingInputs=@(Get-ChildItem -LiteralPath $inputs -File -Recurse)
        if ($remainingInputs.Count -ne $inputBindings.Count) { throw 'Engine changed the downloaded evidence file set.' }
        foreach ($binding in $inputBindings) {
            $path=Resolve-SecurityBundlePath -Root $inputs -RelativePath $binding.path
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $binding.sha256) {
                throw 'Engine changed downloaded evidence; reports were not published.'
            }
        }
        $runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')+'-'+[guid]::NewGuid().ToString('N')
        foreach ($file in Get-ChildItem -LiteralPath $outputs -File -Recurse) {
            $relative = [IO.Path]::GetRelativePath($outputs,$file.FullName).Replace('\','/')
            Invoke-SecurityBlobTransfer -Account $Account -Container $OutputContainer -Blob "$runId/$relative" -Path $file.FullName -Direction Upload
        }
        $manifestPath = Join-Path $temporary 'completed.json'
        $manifest = @{
            schemaVersion='1.0';runId=$runId;status='complete';completedAt=[DateTimeOffset]::UtcNow.ToString('o')
            bundleManifestSha256=$provenance.manifestSha256;sourceCommits=$provenance.sourceCommits
            inputs=$inputBindings
            files=@(Get-ChildItem -LiteralPath $outputs -File -Recurse | ForEach-Object {
                @{path=[IO.Path]::GetRelativePath($outputs,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}
            })
        }
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        # A run is consumable only when this final marker exists and all listed hashes match.
        Invoke-SecurityBlobTransfer -Account $Account -Container $OutputContainer -Blob "$runId/completed.json" -Path $manifestPath -Direction Upload
        return [pscustomobject]@{runId=$runId;status='review-produced';solutionCount=@($config.solutions).Count}
    } finally {
    $cleanupRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $cleanupPath = [IO.Path]::GetFullPath($temporary)
    if (-not $cleanupPath.StartsWith($cleanupRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($cleanupPath) -notmatch '^security-(package|bundle|run)-[a-f0-9]{32}$') { throw 'Refusing cleanup outside the task temporary directory.' }
    if (Test-Path -LiteralPath $cleanupPath) {
        if ((Get-Item -LiteralPath $cleanupPath).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing recursive cleanup of a reparse point.' }
        Remove-Item -LiteralPath $cleanupPath -Recurse -Force
    }
}
}

Export-ModuleMember -Function Get-SecurityAccessToken,Invoke-SecurityGraphRead,Resolve-SecurityBundlePath,Invoke-SecurityBundle,Invoke-SecurityBlobTransfer,Invoke-HostedSecurityBundle
