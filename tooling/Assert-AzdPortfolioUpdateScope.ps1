[CmdletBinding()]
param(
    [string] $RegistryPath,

    [Parameter(Mandatory)]
    [string] $CandidateJson,

    [string] $ConsumerId,

    [switch] $PlanOnly,

    [switch] $ForPublication
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Publication denial must precede reading either registry or artifact data.
if ($ForPublication -and $PlanOnly) { throw 'Plan-only runs cannot publish portfolio updates.' }

$referenceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $RegistryPath) { $RegistryPath = Join-Path $referenceRoot 'portfolio/consumers.json' }
$registryRaw = Get-Content -LiteralPath $RegistryPath -Raw
if (-not ($registryRaw | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/portfolio-consumers.schema.json') -ErrorAction Stop)) {
    throw 'The portfolio consumer registry does not satisfy its schema.'
}
$registry = $registryRaw | ConvertFrom-Json
if ($ConsumerId.Length -gt 0) {
    if ($ConsumerId -cnotmatch '\A[a-z][a-z0-9-]{1,62}[a-z0-9]\z') {
        throw "ConsumerId must be one exact registry ID: '$ConsumerId'."
    }
    $selected = @($registry.consumers | Where-Object { $_.id -ceq $ConsumerId })
    if ($selected.Count -ne 1) { throw "ConsumerId references an unknown or duplicate consumer: '$ConsumerId'." }
}

# A job receives one matrix object, never an array or a caller-supplied matrix.
# Inspect JSON properties before conversion so duplicate keys cannot be hidden.
$document = [System.Text.Json.JsonDocument]::Parse($CandidateJson)
try {
    if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
        throw 'CandidateJson must contain exactly one candidate object.'
    }
    $fields = @('consumer', 'component', 'version', 'repository', 'repositoryOwner', 'repositoryName', 'checkoutDirectory', 'defaultBranch', 'branch')
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($property in $document.RootElement.EnumerateObject()) {
        if ($property.Name -cnotin $fields -or -not $seen.Add($property.Name)) {
            throw "Unexpected or duplicate candidate property: '$($property.Name)'."
        }
        if ($property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
            throw "Candidate field '$($property.Name)' must be a scalar string."
        }
    }
    if ($seen.Count -ne $fields.Count) { throw 'Candidate is missing required fields.' }
}
finally { $document.Dispose() }
$candidate = $CandidateJson | ConvertFrom-Json
if ($ConsumerId.Length -gt 0 -and $candidate.consumer -cne $ConsumerId) {
    throw 'Candidate consumer is outside the selected ConsumerId.'
}
$consumer = @($registry.consumers | Where-Object { $_.id -ceq $candidate.consumer })
if ($consumer.Count -ne 1) { throw 'Candidate references an unknown or duplicate consumer.' }
$consumer = $consumer[0]
$component = @($consumer.components | Where-Object { $_.id -ceq $candidate.component })
if ($component.Count -ne 1) { throw 'Candidate references an unknown or duplicate component.' }
$component = $component[0]
if ($consumer.repository -cnotmatch '\Ahttps://github\.com/(?<owner>[A-Za-z0-9_.-]+)/(?<name>[A-Za-z0-9_.-]+)\z') {
    throw 'Registry repository must be an exact GitHub repository URL.'
}
$expected = [ordered]@{
    consumer = $consumer.id
    component = $component.id
    version = $component.desiredVersion
    repository = $consumer.repository
    repositoryOwner = $Matches.owner
    repositoryName = $Matches.name
    checkoutDirectory = $consumer.checkoutDirectory
    defaultBranch = $consumer.defaultBranch
    branch = "codex/update-$($consumer.id)-$($component.id)-v$($component.desiredVersion)"
}
foreach ($field in $expected.Keys) {
    if ($candidate.$field -cne $expected[$field]) {
        throw "Candidate field '$field' does not match the registry-derived value."
    }
}
