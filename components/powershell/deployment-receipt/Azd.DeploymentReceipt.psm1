Set-StrictMode -Version Latest

$script:DefaultOutputPath = 'reports/deployment-receipt.json'
$script:MaxReceiptBytes = 1024KB
$script:MaxCollectionItems = 500
$script:MaxTextLength = 4096
$script:SensitiveKeyPattern = '(?i)(secret|password|token|credential|authorization|connectionstring|callback|(?:client|access|account|host|shared)key|(?:^|[._-])sig(?:$|[._-]))'
$script:SensitiveValuePattern = '(?i)(bearer\s+\S+|(?:accountkey|sharedaccesssignature|clientsecret|password)\s*=|[?&](?:sig|token|secret|password|key)=)'

function Test-AzdReceiptReparsePoint {
    param([Parameter(Mandatory)][string] $Path)

    (Get-Item -LiteralPath $Path -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint
}

function Assert-AzdReceiptText {
    param(
        [Parameter(Mandatory)][string] $Value,
        [Parameter(Mandatory)][string] $Label,
        [int] $MaximumLength = $script:MaxTextLength
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt $MaximumLength -or $Value -match '[\x00-\x1F]') {
        throw "$Label must be nonempty, bounded, and free of control characters."
    }
    if ($Value -match $script:SensitiveValuePattern -or $Value -match '(?i)https?://[^\s]*/callback(?:[/?#]|$)') {
        throw "$Label contains a value that cannot be written to a deployment receipt."
    }
}

function Assert-AzdReceiptSafeValue {
    param(
        [Parameter(Mandatory)][object] $Value,
        [int] $Depth = 0,
        [ref] $ItemCount
    )

    if ($Depth -gt 16) { throw 'Receipt details are nested too deeply.' }
    $ItemCount.Value = [int] $ItemCount.Value + 1
    if ($ItemCount.Value -gt $script:MaxCollectionItems) { throw 'Receipt details contain too many values.' }
    if ($null -eq $Value -or $Value -is [bool] -or $Value -is [byte] -or $Value -is [int16] -or
        $Value -is [int32] -or $Value -is [int64] -or $Value -is [uint16] -or $Value -is [uint32] -or
        $Value -is [uint64] -or $Value -is [decimal] -or $Value -is [double]) { return }
    if ($Value -is [string]) {
        Assert-AzdReceiptText -Value $Value -Label 'Receipt detail value'
        return
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            $key = [string] $key
            Assert-AzdReceiptText -Value $key -Label 'Receipt detail key' -MaximumLength 128
            if ($key -match $script:SensitiveKeyPattern) { throw 'Receipt detail key is sensitive.' }
            Assert-AzdReceiptSafeValue -Value $Value[$key] -Depth ($Depth + 1) -ItemCount $ItemCount
        }
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            Assert-AzdReceiptSafeValue -Value $item -Depth ($Depth + 1) -ItemCount $ItemCount
        }
        return
    }
    if ($Value -is [psobject]) {
        $properties = @($Value.PSObject.Properties | Where-Object { $_.MemberType -match 'Property' })
        foreach ($property in $properties) {
            Assert-AzdReceiptText -Value $property.Name -Label 'Receipt detail key' -MaximumLength 128
            if ($property.Name -match $script:SensitiveKeyPattern) { throw 'Receipt detail key is sensitive.' }
            Assert-AzdReceiptSafeValue -Value $property.Value -Depth ($Depth + 1) -ItemCount $ItemCount
        }
        return
    }
    throw 'Receipt details contain an unsupported value type.'
}

function Assert-AzdReceiptArtifactPath {
    param([Parameter(Mandatory)][string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 512 -or
        [System.IO.Path]::IsPathRooted($Path) -or $Path -match '[\\\x00-\x1F]' -or
        ($Path -split '/' | Where-Object { $_ -in '.', '..' })) {
        throw 'Receipt artifacts must be bounded repository-relative forward-slash paths.'
    }
}

function Assert-AzdReceiptShape {
    param([Parameter(Mandatory)][object] $Receipt)

    $mode = [string] $Receipt.mode
    if ($mode -notin @('plan', 'enforce')) { throw 'Receipt mode must be plan or enforce.' }
    if ($mode -eq 'plan' -and [int64] $Receipt.summary.applied -ne 0) {
        throw 'Plan receipts cannot report applied actions.'
    }
    $itemCount = 0
    Assert-AzdReceiptSafeValue -Value $Receipt.details -ItemCount ([ref] $itemCount)
    foreach ($artifact in @($Receipt.artifacts)) { Assert-AzdReceiptArtifactPath -Path ([string] $artifact) }
    foreach ($action in @($Receipt.operationalActions)) {
        Assert-AzdReceiptText -Value ([string] $action) -Label 'Operational action'
    }
}

function New-AzdDeploymentReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Template,
        [Parameter(Mandatory)][string] $TemplateVersion,
        [Parameter(Mandatory)][ValidateSet('plan', 'enforce')][string] $Mode,
        [datetimeoffset] $GeneratedAt = [datetimeoffset]::UtcNow,
        [ValidateRange(0, [int]::MaxValue)][int] $Applied = 0,
        [ValidateRange(0, [int]::MaxValue)][int] $Unchanged = 0,
        [ValidateRange(0, [int]::MaxValue)][int] $Skipped = 0,
        [ValidateRange(0, [int]::MaxValue)][int] $Warnings = 0,
        [ValidateRange(0, [int]::MaxValue)][int] $Failed = 0,
        [string[]] $Artifacts = @(),
        [string[]] $OperationalActions = @(),
        [hashtable] $Details = @{}
    )

    Assert-AzdReceiptText -Value $Template -Label 'Template' -MaximumLength 128
    Assert-AzdReceiptText -Value $TemplateVersion -Label 'Template version' -MaximumLength 128
    if ($Mode -eq 'plan' -and $Applied -ne 0) { throw 'Plan receipts cannot report applied actions.' }
    if ($Artifacts.Count -gt $script:MaxCollectionItems -or $OperationalActions.Count -gt $script:MaxCollectionItems) {
        throw 'Receipt artifacts and operational actions are limited to 500 items each.'
    }
    $receipt = [pscustomobject] [ordered]@{
        schemaVersion = '1.0'
        generatedAt = $GeneratedAt.UtcDateTime.ToString('o')
        template = $Template
        templateVersion = $TemplateVersion
        mode = $Mode
        summary = [ordered]@{
            applied = $Applied
            unchanged = $Unchanged
            skipped = $Skipped
            warnings = $Warnings
            failed = $Failed
        }
        artifacts = @($Artifacts)
        operationalActions = @($OperationalActions)
        details = $Details
    }
    Assert-AzdReceiptShape -Receipt $receipt
    return $receipt
}

function Write-AzdDeploymentReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Receipt,
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [string] $OutputPath = $script:DefaultOutputPath,
        [string] $SchemaPath = (Join-Path $PSScriptRoot 'deployment-receipt.schema.json')
    )

    if ([System.IO.Path]::IsPathRooted($OutputPath) -or $OutputPath -split '[\\/]' -contains '..') {
        throw 'OutputPath must be repository-relative and cannot contain parent traversal.'
    }
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'RepositoryRoot must be an existing directory.' }
    if (Test-AzdReceiptReparsePoint -Path $root) { throw 'RepositoryRoot cannot be a symbolic link or reparse point.' }
    $target = [System.IO.Path]::GetFullPath((Join-Path $root $OutputPath))
    $rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not $target.StartsWith($rootPrefix, $comparison)) { throw 'OutputPath resolves outside RepositoryRoot.' }

    $cursor = $root
    foreach ($segment in $OutputPath -split '[\\/]') {
        $cursor = Join-Path $cursor $segment
        if ((Test-Path -LiteralPath $cursor) -and (Test-AzdReceiptReparsePoint -Path $cursor)) {
            throw 'OutputPath cannot traverse a symbolic link or reparse point.'
        }
    }
    Assert-AzdReceiptShape -Receipt $Receipt
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) { throw 'The deployment receipt schema is unavailable.' }
    $json = $Receipt | ConvertTo-Json -Depth 30
    if ([System.Text.Encoding]::UTF8.GetByteCount($json) -gt $script:MaxReceiptBytes) { throw 'Deployment receipt exceeds 1 MiB.' }
    try {
        if (-not ($json | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) { throw 'Schema validation returned false.' }
    }
    catch { throw 'The deployment receipt does not satisfy its schema.' }

    $directory = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    if (Test-AzdReceiptReparsePoint -Path $directory) { throw 'Output directory cannot be a symbolic link or reparse point.' }
    $temporaryPath = Join-Path $directory ('.{0}.{1}.tmp' -f [System.IO.Path]::GetFileName($target), [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
        $cursor = $root
        foreach ($segment in $OutputPath -split '[\\/]') {
            $cursor = Join-Path $cursor $segment
            if ((Test-Path -LiteralPath $cursor) -and (Test-AzdReceiptReparsePoint -Path $cursor)) {
                throw 'OutputPath became a symbolic link or reparse point before the receipt could be committed.'
            }
        }
        Move-Item -LiteralPath $temporaryPath -Destination $target -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
    return [System.IO.Path]::GetRelativePath($root, $target).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
}

Export-ModuleMember -Function 'New-AzdDeploymentReceipt', 'Write-AzdDeploymentReceipt'
