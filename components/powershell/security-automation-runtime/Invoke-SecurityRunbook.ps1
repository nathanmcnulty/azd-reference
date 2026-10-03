param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]{3,24}$')][string]$StorageAccount,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9/._-]+$')][string]$BundleBlob,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$BundleSha256
)
$ErrorActionPreference = 'Stop'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('security-bundle-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    if (-not $env:IDENTITY_ENDPOINT -or -not $env:IDENTITY_HEADER) { throw 'Automation managed identity is unavailable.' }
    $endpoint = [uri]$env:IDENTITY_ENDPOINT
    if (-not $endpoint.IsLoopback) { throw 'Identity endpoint must be local.' }
    $uri = "$endpoint`?resource=https%3A%2F%2Fstorage.azure.com%2F&api-version=2019-08-01"
    $identity = Invoke-RestMethod -Uri $uri -Headers @{ 'X-IDENTITY-HEADER'=$env:IDENTITY_HEADER; Metadata='true' } -TimeoutSec 30 -MaximumRedirection 0
    $zip = Join-Path $temporary 'bundle.zip'
    Invoke-WebRequest -Uri "https://$StorageAccount.blob.core.windows.net/packages/$BundleBlob" -Headers @{Authorization="Bearer $($identity.access_token)";'x-ms-version'='2023-11-03'} -OutFile $zip -MaximumRedirection 0 -TimeoutSec 120
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $BundleSha256) { throw 'Approved bundle hash mismatch.' }
    $root = Join-Path $temporary 'source'
    # Inspect every entry before extraction; the approved package cannot write outside this directory.
    Add-Type -AssemblyName System.IO.Compression
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match '(^|[/\\])\.\.([/\\]|$)|^[\/]|:') { throw 'Unsafe package entry.' }
        }
    } finally { $archive.Dispose() }
    Expand-Archive -LiteralPath $zip -DestinationPath $root
    Import-Module (Join-Path $root 'scripts/vendor/Azd.SecurityAutomation/Azd.SecurityAutomation.psm1') -Force
    Invoke-HostedSecurityBundle -BundleRoot $root -ConfigurationPath (Join-Path $root 'security-bundle.json') -Account $StorageAccount
} finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
