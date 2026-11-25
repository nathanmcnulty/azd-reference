# Offline cost estimator pilot

Use the PowerShell 7.6 CLI to evaluate the three reviewed profiles with fixed synthetic prices. Run from the Reference repository root.

```powershell
$pilot = './examples/cost-pilot'
$profiles = (Get-ChildItem "$pilot/profiles" -Filter '*.json').FullName
./tooling/Get-AzdCostEstimate.ps1 -ProfilePath $profiles -PricePath "$pilot/prices.json" -RequestPath "$pilot/request.json" |
    Set-Content ./cost-estimate.json -Encoding utf8
```

Open `examples/cost-pilot/gui/index.html` and select that JSON file. The fixture displays the CLI's output directly. Its automated test feeds the same result to the browser renderer and checks the displayed portfolio and profile amounts. The pilot uses no credentials, deployment, installer, external dependencies, or price lookups.

## Reviewed configuration

| Profile | Selected configuration | Source |
| --- | --- | --- |
| Auth Notifications | FC1 with a five-minute timer. The rare-email case varies synthetic event-related state operations with independent user count. Collection off still accounts for the timer, standing storage, and application logs. | [Auth Notifications source](https://github.com/nathanmcnulty/azd-auth-notifications/tree/a8578f8b1f99ca5760f8e470fc6b1169cf763187) |
| Maester Function App | FC1 at two GiB and UTC Sunday assessments. The selected optional B1 portal contributes dedicated hours. The portal-off configuration retains assessment and storage meters. | [Maester Function App source](https://github.com/nathanmcnulty/azd-maester-functionapp/tree/76976139f2026917484a91223ba278e9aa1fc058) |
| Sysmon | Compare local-only with the DCR delivering endpoint events to an existing Log Analytics workspace backing Sentinel. The selected case varies intake and retention with device count. Existing workspace overhead stays unallocated. Direct Data Lake export needs its own source and capability review. | [Sysmon source](https://github.com/nathanmcnulty/azd-sysmon/tree/30fe2bc87be0d417151990a8714f81eb3ec5b84d) |

For the checked-in 5,000-user and 5,000-device scenario, the CLI and GUI report
base incremental estimates of 18.92 for Auth Notifications, 38.23 for Maester,
and 3,859.50 for Sysmon in synthetic USD. The total is 3,916.65. The Auth
Notifications timer runs even with collection disabled. Turning off the
Maester portal removes its dedicated compute hours. Local-only Sysmon keeps
event collection on the device and removes the workspace ingestion and
analytics meters. A future Data Lake archival mode would need to account for
storage and retrieval and specify how operators would investigate events
without the priced Sentinel analytics path. If both destinations are enabled,
estimate both copies of ingestion.

## Contract and conventions

- The versioned schemas separate profile assumptions, observed prices, the request, the result, and optional measured usage. The input selects a closed configuration per solution. Each profile records the commit and the files behind that configuration. Factors are ordered low, base, and high, with a rationale per meter. The profile grammar accepts only predefined quantity bases.
- The request binds the UTC evaluation date and the first UTC day of a calendar month. The calculation uses the actual days in that month and counts occurrences of the configured UTC schedules. A per-30-day quantity scales with calendar days. The retention estimate uses end-of-period retained volume, capped at the configured retention days, as the month’s capacity proxy. `priorRetentionDays` models growth from an earlier period without inferring billable historical usage.
- `gb` and `gb-month` are decimal storage units. `gib-second` uses binary GiB and seconds. Currency is USD in the pilot. Arithmetic uses decimal values. Each line is rounded to two decimals, midpoint away from zero, then summed. Amounts are emitted as invariant two-decimal strings so consumers display the same value.
- A priced line requires an exact region, currency, service, SKU, meter, and unit match. Effective and observed dates must satisfy the request. The latest qualifying observation is selected. Prices beyond their stated age are stale. Missing and stale line amounts are null, and known totals are labeled partial. The fixed prices are synthetic.
- Standalone estimates apply eligible allowances within each profile. Incremental estimates share one pool per meter and scenario for the explicit allocation scope. Ordering is ordinal by profile and line ID. Identical eligible shared fixed resources are allocated once to the first profile and conflicting definitions are rejected. A separate unallocated bucket lists shared charges with no verified allocation basis. `complete` describes the price coverage of the modeled lines.
- Optional measured usage can be supplied with `-MeasurementPath`. It must match the exact selected profile revision, configuration, line unit, and month. It is displayed separately with coverage and provenance and is never used to recompute estimated costs. Actual billing export, private import, negotiated prices, credits, tax, and workload measurement belong to the separately authorized #143 lane.

## Adoption checklist

1. Pick a reviewed deployment revision and inventory its option combinations, default host, resource SKUs, meter units, and recurring or one-time actions. Record exclusions and uncertainty in the configuration. Keep users and devices independent.
2. Add a versioned, data-only profile and synthetic price fixtures. Record service, region, currency, effective and observation dates, maximum age, and provenance for any separately reviewed real price records. Keep private source data out of the repository.
3. Prove scheduled and zero-volume behavior, distinct populations, option toggles, unknown prices, and any relevant retention or shared-resource rules. Give any shared resource a reviewed allocation scope. Compare the CLI result with a consumer fixture.
4. Pin the reviewed Reference revision when adopting the evaluator and schemas. Vendor those exact bytes and review compatibility before updating the pin. Use the same result contract in the GUI and solution documentation. The deployed solution has no runtime dependency on Reference.
5. Use #143 to request measurement separately. Revisit the assumptions using observed units and workload shape before extrapolating from a small canary to the 5,000-device reference scenario.
