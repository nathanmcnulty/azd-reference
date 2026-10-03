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
    if (-not $endpoint.IsLoopback) { throw 'Managed identity endpoint must be local.' }
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
    } catch { throw "Evidence blob $Direction failed; output is incomplete." }
}

function Invoke-HostedSecurityBundle {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BundleRoot,[Parameter(Mandatory)][string]$ConfigurationPath,
        [Parameter(Mandatory)][string]$Account,[string]$InputContainer='evidence',[string]$OutputContainer='reports')
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('security-run-'+[guid]::NewGuid().ToString('N'))
    $inputs = Join-Path $temporary 'inputs'; $outputs = Join-Path $temporary 'outputs'
    New-Item -ItemType Directory -Path $inputs,$outputs -Force | Out-Null
    try {
        $config = Get-Content -LiteralPath $ConfigurationPath -Raw | ConvertFrom-Json
        foreach ($solution in $config.solutions) {
            $path = Resolve-SecurityBundlePath -Root $inputs -RelativePath $solution.input
            New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
            Invoke-SecurityBlobTransfer -Account $Account -Container $InputContainer -Blob $solution.input -Path $path
        }
        Invoke-SecurityBundle -BundleRoot $BundleRoot -ConfigurationPath $ConfigurationPath -InputDirectory $inputs -OutputDirectory $outputs
        $runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')+'-'+[guid]::NewGuid().ToString('N')
        foreach ($file in Get-ChildItem -LiteralPath $outputs -File -Recurse) {
            $relative = [IO.Path]::GetRelativePath($outputs,$file.FullName).Replace('\','/')
            Invoke-SecurityBlobTransfer -Account $Account -Container $OutputContainer -Blob "$runId/$relative" -Path $file.FullName -Direction Upload
        }
        $manifestPath = Join-Path $temporary 'completed.json'
        $manifest = @{
            schemaVersion='1.0';runId=$runId;status='complete';completedAt=[DateTimeOffset]::UtcNow.ToString('o')
            files=@(Get-ChildItem -LiteralPath $outputs -File -Recurse | ForEach-Object {
                @{path=[IO.Path]::GetRelativePath($outputs,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}
            })
        }
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        # A run is consumable only when this final marker exists and all listed hashes match.
        Invoke-SecurityBlobTransfer -Account $Account -Container $OutputContainer -Blob "$runId/completed.json" -Path $manifestPath -Direction Upload
        return [pscustomobject]@{runId=$runId;status='review-produced';solutionCount=@($config.solutions).Count}
    } finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
}

Export-ModuleMember -Function Get-SecurityAccessToken,Invoke-SecurityGraphRead,Resolve-SecurityBundlePath,Invoke-SecurityBundle,Invoke-SecurityBlobTransfer,Invoke-HostedSecurityBundle
