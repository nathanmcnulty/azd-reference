#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]] $ProfilePath,
    [Parameter(Mandatory)][string] $PricePath,
    [Parameter(Mandatory)][string] $RequestPath,
    [string] $MeasurementPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$schemaRoot = Join-Path (Split-Path $PSScriptRoot) 'schemas'
$culture = [Globalization.CultureInfo]::InvariantCulture
$scenarios = 'low', 'base', 'high'
$categories = 'fixed', 'usage', 'oneTime', 'optional'

function Read-CostInput {
    param([string] $Path, [string] $Kind)
    $file = Get-Item -LiteralPath $Path
    if ($file -isnot [IO.FileInfo] -or $file.Length -gt 128KB) {
        throw "Invalid or oversized cost $Kind file."
    }
    $raw = Get-Content -LiteralPath $file.FullName -Raw
    $schema = Join-Path $schemaRoot "cost-$Kind.schema.json"
    if (-not (Test-Json -Json $raw -SchemaFile $schema -ErrorAction SilentlyContinue)) {
        throw "Invalid cost $Kind contract."
    }
    return (ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 24 -DateKind String -NoEnumerate)
}

function ConvertTo-CostDate {
    param([string] $Value)
    return [DateOnly]::ParseExact($Value, 'yyyy-MM-dd', $culture)
}

function New-CostSummary {
    $totals = [ordered]@{}
    foreach ($category in ($categories + 'knownTotal')) {
        $totals[$category] = [ordered]@{low = 0d; base = 0d; high = 0d}
    }
    return $totals
}

function Format-CostAmount {
    param([decimal] $Amount)
    return $Amount.ToString('0.00', $culture)
}

function ConvertTo-CostSummaryText {
    param($Totals)
    foreach ($bucket in $Totals.Values) {
        foreach ($scenario in $scenarios) {
            $bucket[$scenario] = Format-CostAmount $bucket[$scenario]
        }
    }
    return $Totals
}

function Get-CostMeterKey {
    param($Meter)
    return (@($Meter.service, $Meter.sku, $Meter.meter, $Meter.unit) -join '|')
}

function Get-CostRunCount {
    param([string] $Schedule, [DateOnly] $Start, [int] $Days)
    switch ($Schedule) {
        'none' { return 0 }
        'everyFiveMinutes' { return 288 * $Days }
        'sundayUtc' {
            $firstSunday = (7 - [int]$Start.DayOfWeek) % 7
            return [int][Math]::Floor(($Days + 6 - $firstSunday) / 7)
        }
    }
}

if ($ProfilePath.Count -gt 12) { throw 'At most twelve cost profiles can be loaded.' }
$profiles = @{}
foreach ($path in $ProfilePath) {
    $costProfile = Read-CostInput $path profile
    if ($profiles.ContainsKey($costProfile.id)) { throw "Duplicate profile '$($costProfile.id)'." }
    $profiles.Add($costProfile.id, $costProfile)
}
$prices = Read-CostInput $PricePath prices
$request = Read-CostInput $RequestPath request
$asOf = ConvertTo-CostDate $request.asOf
$start = ConvertTo-CostDate $request.periodStart
if ($start.Day -ne 1 -or $start.Year -ge 9999) { throw 'A billing period starts on the first UTC day of a calendar month.' }
$days = $start.AddMonths(1).DayNumber - $start.DayNumber
$measurements = @{}
if ($MeasurementPath) {
    $inputMeasurements = Read-CostInput $MeasurementPath measurements
    foreach ($measurement in $inputMeasurements.observations) {
        $key = "$($measurement.profile)|$($measurement.line)"
        if ($measurements.ContainsKey($key) -or $measurement.periodStart -cne $request.periodStart -or
            (ConvertTo-CostDate $measurement.observedOn) -gt $asOf) {
            throw 'Measurements must be unique, match the selected period and be observed by the evaluation date.'
        }
        $measurements.Add($key, $measurement)
    }
}

$catalog = @{}
$observationKeys = @{}
foreach ($price in $prices.observations) {
    $effective = ConvertTo-CostDate $price.effectiveOn
    $observed = ConvertTo-CostDate $price.observedOn
    $meterKey = Get-CostMeterKey $price
    $observationKey = "$meterKey|$($price.region)|$($price.currency)|$($price.effectiveOn)|$($price.observedOn)"
    if ($observationKeys.ContainsKey($observationKey)) { throw 'Duplicate observations for the same meter and dates.' }
    $observationKeys.Add($observationKey, $true)
    if ($price.region -cne $request.region -or $price.currency -cne $request.currency -or
        $effective -gt $asOf -or $observed -gt $asOf -or $effective -gt $start) { continue }
    $previous = $catalog[$meterKey]
    if ($null -eq $previous -or $price.effectiveOn -cgt $previous.effectiveOn -or
        ($price.effectiveOn -ceq $previous.effectiveOn -and $price.observedOn -cgt $previous.observedOn)) {
        $catalog[$meterKey] = $price
    }
}

$selected = @{}
foreach ($selection in $request.selections) {
    if ($selected.ContainsKey($selection.profile)) { throw "Duplicate selection '$($selection.profile)'." }
    if (-not $profiles.ContainsKey($selection.profile)) { throw "Unknown profile '$($selection.profile)'." }
    $selected.Add($selection.profile, $selection.configuration)
}

$portfolioTotals = New-CostSummary
$allocated = @{}
$sharedAssets = @{}
$profileIds = [string[]]@($selected.Keys)
[Array]::Sort($profileIds, [StringComparer]::Ordinal)
$estimates = foreach ($id in $profileIds) {
    $costProfile = $profiles[$id]
    $configurations = @($costProfile.configurations | Where-Object { $_.id -ceq $selected[$id] })
    if ($configurations.Count -ne 1) { throw "Unknown or ambiguous configuration for '$id'." }
    $configuration = $configurations[0]
    $runs = Get-CostRunCount $configuration.schedule $start $days
    $quantities = @{
        fixed = 1; periodDays = $days; runs = $runs; users = $request.users; devices = $request.devices
        deviceMonths = [decimal]$request.devices * $days / 30
        retainedDeviceDays = $request.devices * [Math]::Min($configuration.retentionDays, $days + $request.priorRetentionDays)
    }
    $standaloneTotals = New-CostSummary
    $incrementalTotals = New-CostSummary
    $standaloneAllocated = @{}
    $standaloneAssets = @{}
    $linesById = @{}
    foreach ($line in $configuration.lines) {
        if ($linesById.ContainsKey($line.id)) { throw "Duplicate line '$($line.id)' in '$id'." }
        if ($line.factors.low -gt $line.factors.base -or $line.factors.base -gt $line.factors.high) {
            throw "Unordered scenario factors for '$($line.id)'."
        }
        $linesById.Add($line.id, $line)
    }
    $lineIds = [string[]]@($linesById.Keys)
    [Array]::Sort($lineIds, [StringComparer]::Ordinal)
    $complete = $true
    $lines = @(foreach ($lineId in $lineIds) {
        $line = $linesById[$lineId]
        $meterKey = Get-CostMeterKey $line.price
        $price = $catalog[$meterKey]
        $quantity = [ordered]@{}
        foreach ($scenario in $scenarios) {
            $quantity[$scenario] = [decimal]$quantities[$line.basis] * [decimal]$line.factors[$scenario]
        }
        $allocatedElsewhere = $false
        if ($line.Contains('sharedResource')) {
            if ($line.category -cne 'fixed' -or -not $line.Contains('allowedScope')) {
                throw 'Shared resources require an explicit allocation scope and a fixed baseline line.'
            }
            if ($line.allowedScope -ceq $request.allocationScope) {
                $asset = $line.sharedResource
                $assetSignature = "$meterKey|$($quantity.low)|$($quantity.base)|$($quantity.high)"
                if ($standaloneAssets.ContainsKey($asset)) { throw "Duplicate shared resource '$asset' in '$id'." }
                $standaloneAssets.Add($asset, $true)
                if ($sharedAssets.ContainsKey($asset) -and $sharedAssets[$asset] -cne $assetSignature) {
                    throw "Conflicting usage or price meter for shared resource '$asset'."
                }
                $allocatedElsewhere = $sharedAssets.ContainsKey($asset)
                $sharedAssets[$asset] = $assetSignature
            }
        }
        $record = [ordered]@{
            id = $lineId; label = $line.label; category = $line.category; price = $line.price; reason = $line.reason
            status = 'priced'; quantity = $quantity; grantApplied = [ordered]@{low = 0; base = 0; high = 0}
            allocatedElsewhere = $allocatedElsewhere
            standalone = $null; incremental = $null; observation = $price; measurement = $null
        }
        $measurementKey = "$id|$lineId"
        if ($measurements.ContainsKey($measurementKey)) {
            $measurement = $measurements[$measurementKey]
            if ($measurement.revision -cne $costProfile.revision -or $measurement.configuration -cne $configuration.id -or
                $measurement.unit -cne $line.price.unit) { throw 'Measured usage does not match the selected profile, configuration or unit.' }
            $record.measurement = $measurement
            $measurements.Remove($measurementKey)
        }
        if ($line.category -ceq 'oneTime' -and -not $request.includeOneTime) {
            $record.status = 'excluded'
        } elseif ($null -eq $price) {
            $record.status = 'missing'
            $complete = $false
        } elseif (($asOf.DayNumber - (ConvertTo-CostDate $price.observedOn).DayNumber) -gt $price.maxAgeDays) {
            $record.status = 'stale'
            $complete = $false
        } else {
            $record.standalone = [ordered]@{}
            $record.incremental = [ordered]@{}
            $allowance = if ($line.Contains('allowedScope') -and $line.allowedScope -ceq $request.allocationScope) {
                [decimal]$price.freeUnits
            } else { 0d }
            foreach ($scenario in $scenarios) {
                $allocationKey = "$meterKey|$scenario"
                $standaloneGrant = [Math]::Min($quantity[$scenario], [decimal]($allowance - [decimal]$standaloneAllocated[$allocationKey]))
                $portfolioQuantity = if ($allocatedElsewhere) { 0d } else { $quantity[$scenario] }
                $portfolioGrant = [Math]::Min($portfolioQuantity, [decimal]($allowance - [decimal]$allocated[$allocationKey]))
                # An ineligible line must not consume or restore another line's grant.
                $standaloneGrant = [Math]::Max(0d, $standaloneGrant)
                $portfolioGrant = [Math]::Max(0d, $portfolioGrant)
                $standaloneAllocated[$allocationKey] += $standaloneGrant
                $allocated[$allocationKey] += $portfolioGrant
                $record.grantApplied[$scenario] = $portfolioGrant
                $standalone = [Math]::Round(($quantity[$scenario] - $standaloneGrant) * [decimal]$price.rate, 2, [MidpointRounding]::AwayFromZero)
                $incremental = [Math]::Round(($portfolioQuantity - $portfolioGrant) * [decimal]$price.rate, 2, [MidpointRounding]::AwayFromZero)
                $record.standalone[$scenario] = Format-CostAmount $standalone
                $record.incremental[$scenario] = Format-CostAmount $incremental
                $standaloneTotals[$line.category][$scenario] += $standalone
                $standaloneTotals.knownTotal[$scenario] += $standalone
                $incrementalTotals[$line.category][$scenario] += $incremental
                $incrementalTotals.knownTotal[$scenario] += $incremental
                $portfolioTotals[$line.category][$scenario] += $incremental
                $portfolioTotals.knownTotal[$scenario] += $incremental
            }
        }
        $record
    })
    [ordered]@{
        id = $id; repository = $costProfile.repository; revision = $costProfile.revision; configuration = $configuration.id
        options = $configuration.options; schedule = $configuration.schedule; retentionDays = $configuration.retentionDays
        runs = $runs; lines = $lines; exclusions = $configuration.exclusions
        unallocated = @($configuration['unallocated'] | Where-Object { $_ })
        complete = $complete
        standalone = ConvertTo-CostSummaryText $standaloneTotals
        incremental = ConvertTo-CostSummaryText $incrementalTotals
    }
}

if ($measurements.Count) { throw 'Measured usage refers to a line outside the selected configurations.' }

[ordered]@{
    schemaVersion = '1.0'; request = $request; periodDays = $days; profiles = @($estimates)
    portfolio = ConvertTo-CostSummaryText $portfolioTotals
    unallocated = @(foreach ($estimate in $estimates) {
        foreach ($label in $estimate.unallocated) { [ordered]@{profile = $estimate.id; label = $label} }
    })
    complete = @($estimates | Where-Object { -not $_.complete }).Count -eq 0
} | ConvertTo-Json -Depth 24
