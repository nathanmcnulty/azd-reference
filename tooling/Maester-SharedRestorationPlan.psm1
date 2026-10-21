#Requires -Version 7.6
# Pure offline comparison only. Nothing produced here authorizes a provider write.
Set-StrictMode -Version Latest
$script:SharedJournalModule = Import-Module (Join-Path $PSScriptRoot '../components/powershell/maester-azd-hooks/Maester-OwnershipJournal.psm1') -PassThru

function ConvertTo-SharedCanonicalJson {
  param($Value)
  & $script:SharedJournalModule { param($v) ConvertTo-MaesterJournalCanonicalJson $v } $Value
}
function Get-SharedHash {
  param($Value)
  [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes((ConvertTo-SharedCanonicalJson $Value)))).ToLowerInvariant()
}
function Assert-SharedFields {
  param($Value, [string[]]$Fields)
  & $script:SharedJournalModule { param($v,$f) Assert-MaesterJournalFields $v $f $f 'shared restoration evidence' } $Value $Fields
}
function Assert-SharedTime {
  param($Value)
  $parsed = [DateTimeOffset]::MinValue
  if ($Value -isnot [string] -or -not [DateTimeOffset]::TryParseExact($Value, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed) -or $parsed.Offset -ne [TimeSpan]::Zero) {
    throw 'Shared restoration evidence requires an exact UTC timestamp.'
  }
  return $parsed
}
function Assert-SharedValues {
  param($Values, $Binding, [string]$Kind)
  $fields = if ($Kind -ceq 'ApplicationConfiguration') { @('redirectUris', 'identifierUris', 'groupMembershipClaims', 'enableIdTokenIssuance', 'enableAccessTokenIssuance') } else { @('scopes') }
  Assert-SharedFields $Values $fields
  & $script:SharedJournalModule { param($v,$f,$b,$k) Assert-MaesterJournalMetadata $v $f $f $b 'before' $k } $Values $fields $Binding $Kind
  # Legacy journal validation allows absent values. Never equate absent, empty,
  # false or missing fields here; exact comparison is deliberately conservative.
  foreach ($field in $fields) {
    $value = $Values[$field]
    if ($field -cin @('redirectUris','identifierUris','scopes')) {
      if ($null -ne $value -and $value -isnot [Collections.IList]) { throw 'Shared restoration arrays must be explicit arrays or null.' }
      if ($null -ne $value) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($item in $value) { if ($item -isnot [string] -or -not $seen.Add($item)) { throw 'Shared restoration arrays must contain unique strings.' } }
      }
    } elseif ($field -cin @('enableIdTokenIssuance','enableAccessTokenIssuance')) {
      if ($null -ne $value -and $value -isnot [bool]) { throw 'Shared restoration flags must be Boolean or null.' }
    }
  }
}

function Get-MaesterSharedRestorationPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][Collections.IDictionary]$Journal,
    [Parameter(Mandatory)][Collections.IDictionary]$Binding,
    [Parameter(Mandatory)][Collections.IDictionary]$Evidence,
    [Parameter(Mandatory)][Collections.IDictionary]$Protection,
    [ValidateRange(1,3600)][int]$MaximumAgeSeconds = 900,
    [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
  )
  $ErrorActionPreference = 'Stop'
  # Validate without opening a journal session or creating lock/checkpoint files.
  & $script:SharedJournalModule { param($j,$b) Assert-MaesterJournalDocument $j $b } $Journal $Binding
  Assert-SharedFields $Protection @('applicationObjectIds','appIds','servicePrincipalIds')
  foreach ($field in $Protection.Keys) {
    if ($Protection[$field] -isnot [Collections.IList] -or $Protection[$field].Count -gt 128) { throw 'Protected identities must be bounded explicit arrays.' }
    foreach ($id in $Protection[$field]) { & $script:SharedJournalModule { param($v) Assert-MaesterJournalGuid $v } $id }
  }
  Assert-SharedFields $Evidence @('schemaVersion','binding','journalHash','observations')
  if ($Evidence.schemaVersion -cne '1.0' -or (ConvertTo-SharedCanonicalJson $Evidence.binding) -cne (ConvertTo-SharedCanonicalJson $Binding)) { throw 'Shared restoration evidence has a different schema or binding.' }
  if ($Evidence.journalHash -cne (Get-SharedHash $Journal)) { throw 'Shared restoration evidence does not bind the exact journal.' }
  if ($Evidence.observations -isnot [Collections.IList] -or $Evidence.observations.Count -gt 512) { throw 'Shared restoration observations must be a bounded array.' }
  if ([Text.Encoding]::UTF8.GetByteCount((ConvertTo-SharedCanonicalJson $Evidence)) -gt 1048576) { throw 'Shared restoration evidence exceeds its size limit.' }
  $observations = @{}
  foreach ($observation in $Evidence.observations) {
    & $script:SharedJournalModule { param($v) Assert-MaesterJournalFields $v @('operationId','observedUtc','state','expected','exactIds','values','principalId') @('operationId','observedUtc','state','expected','exactIds','values') 'shared restoration observation' } $observation
    & $script:SharedJournalModule { param($v) Assert-MaesterJournalGuid $v } $observation.operationId
    if ($observations.ContainsKey($observation.operationId)) { throw 'Duplicate shared restoration observations are ambiguous.' }
    $record = @($Journal.records | Where-Object operationId -CEQ $observation.operationId)
    if ($record.Count -ne 1 -or $record[0].kind -cnotin @('ApplicationConfiguration','OAuth2PermissionGrant') -or $record[0].ownership -cne 'Mutation') { throw 'Observation does not name one supported shared mutation.' }
    $record = $record[0]
    if ($record.kind -ceq 'OAuth2PermissionGrant') {
      if (-not $observation.Contains('principalId')) { throw 'OAuth observations require the explicit provider principalId, including null.' }
      if ($record.expected.consentType -ceq 'AllPrincipals' -and $null -ne $observation.principalId) { throw 'AllPrincipals observation has a conflicting principal identity.' }
    } elseif ($observation.Contains('principalId')) { throw 'Application observations cannot include a grant principal.' }
    if ((ConvertTo-SharedCanonicalJson $observation.expected) -cne (ConvertTo-SharedCanonicalJson $record.expected) -or (ConvertTo-SharedCanonicalJson $observation.exactIds) -cne (ConvertTo-SharedCanonicalJson $record.exactIds)) { throw 'Observed provider identity differs from the exact receipt.' }
    if ($observation.state -cnotin @('present','absent','unknown')) { throw 'Unsupported shared restoration observation state.' }
    $observed = Assert-SharedTime $observation.observedUtc
    if ($observed -gt $Now) { throw 'Future shared restoration observations are invalid.' }
    if ($observation.state -ceq 'present') { Assert-SharedValues $observation.values $Binding $record.kind }
    elseif ($observation.values -isnot [Collections.IDictionary] -or $observation.values.Count -ne 0) { throw 'Unavailable observations cannot carry provider values.' }
    $observations[$observation.operationId] = $observation
  }
  $results = [Collections.Generic.List[object]]::new()
  foreach ($record in $Journal.records) {
    if ($record.ownership -cne 'Mutation' -or $null -ne $record.coveredByOperationId) { continue }
    $reason = ''; $status = 'blocked'
    if ($record.kind -cnotin @('ApplicationConfiguration','OAuth2PermissionGrant')) { $reason = 'unsupportedKind' }
    elseif ($record.state -cne 'applied') { $reason = 'receiptNotApplied' }
    elseif ($record.kind -ceq 'OAuth2PermissionGrant' -and ($record.expected.consentType -cne 'AllPrincipals' -or $record.expected.Contains('principalId'))) { $reason = 'principalConsentUnsupported' }
    else {
      # Any repeated target is a generation boundary, even if earlier records are
      # terminal or have different keys. Never infer an undo chain by timestamps.
      $sameTarget = @($Journal.records | Where-Object {
        $other = $_
        if ($other.kind -cne $record.kind) { return $false }
        if ($record.kind -ceq 'ApplicationConfiguration') {
          # Either immutable application identity overlapping is enough to block:
          # contradictory object/app pairs are not independent generations.
          return $other.expected.applicationObjectId -ceq $record.expected.applicationObjectId -or $other.expected.appId -ceq $record.expected.appId
        }
        # A grant ID cannot safely be assigned two different tuples. Conversely,
        # repeated tuples with different grant IDs still require reconciliation.
        return ($other.exactIds.Contains('grantId') -and $other.exactIds['grantId'] -ceq $record.exactIds['grantId']) -or (
          $other.expected.clientId -ceq $record.expected.clientId -and
          $other.expected.resourceId -ceq $record.expected.resourceId -and
          $other.expected.consentType -ceq $record.expected.consentType)
      })
      $protected = $false
      foreach ($values in @($record.expected,$record.exactIds)) {
        foreach ($field in @('appId','applicationObjectId','servicePrincipalId','clientId')) {
          if (-not $values.Contains($field)) { continue }
          $id = $values[$field]
          if ($id -ceq $Binding.setupClientId -or $id -cin $Protection.appIds -or $id -cin $Protection.applicationObjectIds -or $id -cin $Protection.servicePrincipalIds) { $protected = $true }
        }
      }
      if ($protected) { $reason = 'protectedIdentity' }
      elseif ($sameTarget.Count -ne 1) { $reason = 'repeatedTargetNeedsGenerationContract' }
      elseif (-not $observations.ContainsKey($record.operationId)) { $reason = 'observationMissing' }
      else {
        Assert-SharedValues $record.before $Binding $record.kind
        Assert-SharedValues $record.after $Binding $record.kind
        $observation = $observations[$record.operationId]
        $updated = Assert-SharedTime $record.updatedUtc
        $created = Assert-SharedTime $record.createdUtc
        $observed = Assert-SharedTime $observation.observedUtc
        if ($created -gt $updated -or $updated -gt $observed) { $reason = 'observationPredatesReceipt' }
        elseif (($Now - $observed).TotalSeconds -gt $MaximumAgeSeconds) { $reason = 'observationStale' }
        elseif ($observation.state -ceq 'absent') { $reason = 'targetAbsentNotRestored' }
        elseif ($observation.state -ceq 'unknown') { $reason = 'currentStateUnknown' }
        else {
          $before = ConvertTo-SharedCanonicalJson $record.before
          $after = ConvertTo-SharedCanonicalJson $record.after
          $current = ConvertTo-SharedCanonicalJson $observation.values
          if ($current -ceq $before) { $status = 'alreadyAtBefore'; $reason = 'noWriteNeededNotRestoreProof' }
          elseif ($current -ceq $after) { $status = 'reviewCandidate'; $reason = 'capturedAfterStateMatches' }
          else { $reason = 'concurrentChangeConflict' }
        }
      }
    }
    $results.Add([ordered]@{
      operationId = $record.operationId; kind = $record.kind; status = $status; reason = $reason
      mutationAllowed = $false; deletionAllowed = $false; adoptionAllowed = $false
    })
  }
  $projection = [ordered]@{
    schemaVersion = '1.0'; journalHash = $Evidence.journalHash
    evidenceHash = Get-SharedHash $Evidence; protectionHash = Get-SharedHash $Protection
    observationMaximumAgeSeconds = $MaximumAgeSeconds; evaluatedUtc = $Now.ToUniversalTime().ToString('o')
    authoritativeProviderRead = $false; executable = $false; operations = @($results.ToArray())
  }
  $projection.planHash = Get-SharedHash $projection
  return [pscustomobject]$projection
}
Export-ModuleMember -Function Get-MaesterSharedRestorationPlan
