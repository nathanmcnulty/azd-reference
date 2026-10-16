Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AzdRunbookMetadataSnapshot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ExpectedAccountId,
    [Parameter(Mandatory)][string]$RunbookName,
    [Parameter(Mandatory)][System.Collections.IDictionary]$Runbook
  )

  $expectedId = "$ExpectedAccountId/runbooks/$RunbookName"
  $properties = $Runbook['properties']
  if ($Runbook['id'] -isnot [string] -or $Runbook['name'] -isnot [string] -or
      $Runbook['type'] -isnot [string] -or [string]$Runbook['id'] -ine $expectedId -or [string]$Runbook['name'] -ine $RunbookName -or
      [string]$Runbook['type'] -ine 'Microsoft.Automation/automationAccounts/runbooks' -or
      $properties -isnot [System.Collections.IDictionary] -or
      $properties['state'] -isnot [string] -or $properties['runbookType'] -isnot [string] -or
      [string]$properties['state'] -ine 'Published' -or [string]$properties['runbookType'] -ine 'PowerShell') {
    throw 'The fresh runbook metadata read does not match the exact published PowerShell target.'
  }
  if ($Runbook['location'] -isnot [string] -or [string]::IsNullOrWhiteSpace($Runbook['location'])) {
    throw 'The fresh runbook metadata has no valid location.'
  }

  # Snapshot mutable metadata for comparison; content/state/runtime are checked
  # separately. Draft, parameters, timestamps and read-only fields are never replayed.
  $metadata = [ordered]@{ location = $Runbook['location']; properties = [ordered]@{} }
  foreach ($name in @('description', 'logProgress', 'logVerbose', 'logActivityTrace')) {
    if (-not $properties.Contains($name)) { continue }
    $value = $properties[$name]
    $valid = switch ($name) {
      'description' { $value -is [string] }
      'logProgress' { $value -is [bool] }
      'logVerbose' { $value -is [bool] }
      'logActivityTrace' { ($value -is [int] -or $value -is [long]) -and $value -ge [int]::MinValue -and $value -le [int]::MaxValue }
    }
    if (-not $valid) { throw "The fresh runbook metadata property '$name' has an unsupported null or value type." }
    $metadata.properties[$name] = $value
  }
  if ($Runbook.Contains('tags')) {
    if ($null -eq $Runbook['tags']) {
      # ARM treats null resource properties as absent: retain the untagged state.
      $metadata['tags'] = $null
      return $metadata
    }
    if ($Runbook['tags'] -isnot [System.Collections.IDictionary]) {
      throw 'The fresh runbook metadata tags must be a string-valued object.'
    }
    $metadata.tags = [ordered]@{}
    foreach ($key in $Runbook['tags'].Keys) {
      if ($key -isnot [string] -or $Runbook['tags'][$key] -isnot [string]) {
        throw 'The fresh runbook metadata tags must be a string-valued object.'
      }
      $metadata.tags[$key] = $Runbook['tags'][$key]
    }
  }
  return $metadata
}

function ConvertTo-AzdRunbookCanonicalJson {
  param([AllowNull()]$Value)
  function ConvertTo-CanonicalValue {
    param([AllowNull()]$Item)
    if ($null -eq $Item) { return $null }
    if ($Item -is [System.Collections.IDictionary]) {
      $ordered = [ordered]@{}
      foreach ($key in @($Item.Keys | Sort-Object)) { $ordered[$key] = ConvertTo-CanonicalValue $Item[$key] }
      return $ordered
    }
    if ($Item -is [pscustomobject]) {
      $ordered = [ordered]@{}
      foreach ($property in @($Item.PSObject.Properties | Sort-Object Name)) { $ordered[$property.Name] = ConvertTo-CanonicalValue $property.Value }
      return $ordered
    }
    if ($Item -is [System.Collections.IList]) {
      $items = @(foreach ($element in $Item) { ConvertTo-CanonicalValue $element })
      return ,$items
    }
    return $Item
  }
  return ConvertTo-Json -InputObject (ConvertTo-CanonicalValue $Value) -Depth 100 -Compress
}

function Update-AzdAutomationRunbookRuntime {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ExpectedAccountId,
    [Parameter(Mandatory)][string]$RunbookName,
    [Parameter(Mandatory)][scriptblock]$AssertOwnership,
    [Parameter(Mandatory)]$ExpectedRuntimeName,
    [Parameter(Mandatory)]$ExpectedRuntimeVersion,
    [Parameter(Mandatory)][string]$ExpectedContent,
    [Parameter(Mandatory)][scriptblock]$GetResource,
    [Parameter(Mandatory)][scriptblock]$GetContent,
    [Parameter(Mandatory)][scriptblock]$PatchResource
  )

  # The caller owns provenance, target selection and transport authentication.
  # Reject path injection before invoking even the ownership callback.
  if ($ExpectedAccountId -notmatch '\A/subscriptions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/resourceGroups/(?!\.{1,2}/)[a-zA-Z0-9_.()-]+/providers/Microsoft\.Automation/automationAccounts/[a-zA-Z0-9][a-zA-Z0-9_-]{0,49}\z' -or
      $RunbookName -cnotmatch '\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z' -or
      $ExpectedRuntimeName -isnot [string] -or $ExpectedRuntimeName -cnotmatch '\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z' -or
      $ExpectedRuntimeVersion -isnot [string] -or $ExpectedRuntimeVersion -cnotmatch '\A[0-9]+\.[0-9]+\z' -or
      [string]::IsNullOrWhiteSpace($ExpectedContent)) {
    throw 'Explicit Automation account, runbook, runtime name/version and nonblank expected content are required.'
  }
  $owned = & $AssertOwnership $ExpectedAccountId $RunbookName
  if ($owned -isnot [bool] -or -not $owned) {
    throw 'The caller did not assert verified ownership of the exact Automation runbook.'
  }
  $runtimeId = "$ExpectedAccountId/runtimeEnvironments/$ExpectedRuntimeName"
  $runtime = & $GetResource "$runtimeId`?api-version=2024-10-23"
  $runtimeRecord = $runtime | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
  $runtimeProperties = if ($runtimeRecord -is [System.Collections.IDictionary]) { $runtimeRecord['properties'] } else { $null }
  $definition = if ($runtimeProperties -is [System.Collections.IDictionary]) { $runtimeProperties['runtime'] } else { $null }
  if ($definition -isnot [System.Collections.IDictionary] -or
      $runtimeRecord['id'] -isnot [string] -or $runtimeRecord['name'] -isnot [string] -or
      $runtimeRecord['type'] -isnot [string] -or
      [string]$runtimeRecord['id'] -ine $runtimeId -or [string]$runtimeRecord['name'] -ine $ExpectedRuntimeName -or
      [string]$runtimeRecord['type'] -ine 'Microsoft.Automation/automationAccounts/runtimeEnvironments' -or
      $definition['language'] -isnot [string] -or $definition['language'] -cne 'PowerShell' -or
      $definition['version'] -isnot [string] -or $definition['version'] -cne $ExpectedRuntimeVersion) {
    throw 'The exact deployment runtime does not match its account, name, type, language, and version.'
  }

  $runbookPath = "$ExpectedAccountId/runbooks/${RunbookName}?api-version=2024-10-23"
  $contentPath = "$ExpectedAccountId/runbooks/${RunbookName}/content?api-version=2024-10-23"
  $before = & $GetResource $runbookPath
  $beforeRecord = $before | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
  $beforeMetadata = Get-AzdRunbookMetadataSnapshot -ExpectedAccountId $ExpectedAccountId -RunbookName $RunbookName -Runbook $beforeRecord
  $currentRuntime = $beforeRecord['properties']['runtimeEnvironment']
  if ($currentRuntime -isnot [string] -or [string]::IsNullOrWhiteSpace($currentRuntime)) {
    throw 'The existing runbook has no verified scalar runtime binding before PATCH.'
  }
  $expected = $ExpectedContent.TrimStart([char]0xFEFF).Replace("`r`n", "`n")
  $published = & $GetContent $contentPath
  if ($published -isnot [string] -or [string]::IsNullOrWhiteSpace($published) -or
      $published.TrimStart([char]0xFEFF).Replace("`r`n", "`n") -cne $expected) {
    throw 'Published/local runbook content differs before the runtime PATCH.'
  }
  if ($currentRuntime -ieq $ExpectedRuntimeName) {
    Write-Host "Existing runbook is already bound to '$ExpectedRuntimeName'; runtime PATCH was skipped."
    return $false
  }

  # Use the documented direct update route instead of create-or-update PUT.
  # Readback must prove preservation; never upload or publish a draft here.
  Write-Host "Updating existing runbook runtime '$currentRuntime' to '$ExpectedRuntimeName'."
  $body = @{ properties = @{ runtimeEnvironment = $ExpectedRuntimeName } } | ConvertTo-Json -Depth 3 -Compress
  & $PatchResource $runbookPath $body | Out-Null
  $after = & $GetResource $runbookPath
  $afterRecord = $after | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
  $afterMetadata = Get-AzdRunbookMetadataSnapshot -ExpectedAccountId $ExpectedAccountId -RunbookName $RunbookName -Runbook $afterRecord
  $afterContent = & $GetContent $contentPath
  if ($afterRecord['properties']['runtimeEnvironment'] -isnot [string] -or
      $afterRecord['properties']['runtimeEnvironment'] -ine $ExpectedRuntimeName -or
      (ConvertTo-AzdRunbookCanonicalJson $afterMetadata) -cne (ConvertTo-AzdRunbookCanonicalJson $beforeMetadata) -or
      $afterContent -isnot [string] -or
      $afterContent.TrimStart([char]0xFEFF).Replace("`r`n", "`n") -cne $expected) {
    throw 'The runtime PATCH did not preserve the published runbook content, metadata, and expected binding.'
  }
  Write-Host "Verified existing runbook runtime binding '$ExpectedRuntimeName' with published content and metadata unchanged."
  return $true
}

Export-ModuleMember -Function Update-AzdAutomationRunbookRuntime
