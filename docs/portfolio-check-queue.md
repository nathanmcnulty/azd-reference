# Bounded offline portfolio check queue

`tooling/Invoke-AzdPortfolioCheckQueue.ps1` requires 64-bit PowerShell 7.6 or
later, matching the repository tooling baseline. It runs a reviewed list of
offline PowerShell checks with a hard maximum of five concurrent workers. It
returns a result for every item, including failures, in manifest order. Each result
records UTC enqueue/start/finish times, queue wait in milliseconds, execution
time in milliseconds, exit status, captured output, and any error. The summary
records total elapsed time, the configured limit, and observed peak
concurrency.

The bounds apply to manifest size (100 checks) and concurrent workers. The
queue does not enforce a per-check timeout or maximum runtime. Use only trusted
checks that terminate within an independently established time bound. Because
workers are thread jobs in one PowerShell process, checks must not mutate
process-wide environment variables or other shared process state. A
`serializationKey` serializes declared shared writable targets within one queue
invocation; do not overlap separate queue processes on the same target.

Create a private JSON manifest with this shape:

~~~json
{
  "schemaVersion": "1.0",
  "checks": [
    {
      "id": "reference-schema",
      "executionClass": "offline",
      "script": "C:\\private-evidence\\portfolio-checks\\Run-ReferenceSchema.ps1",
      "arguments": [],
      "serializationKey": "C:\\azd\\azd-reference"
    },
    {
      "id": "device-cleanup-source",
      "executionClass": "offline",
      "script": "C:\\private-evidence\\portfolio-checks\\Run-DeviceCleanupSource.ps1",
      "arguments": [],
      "serializationKey": "C:\\azd\\azd-device-cleanup"
    }
  ]
}
~~~

The manifest path may be absolute or relative to the manifest file. Every
'script' must identify an existing '.ps1' file. Checks without a
'serializationKey' are eligible to run together. Give checks the same key when
they share a writable checkout, fixture root, or state target; a blocked key
does not prevent unrelated checks from using a free slot. Use a canonical key
for each exact shared target.

Run the queue and save its output under the private evidence directory:

~~~powershell
$result = & .\tooling\Invoke-AzdPortfolioCheckQueue.ps1 -ManifestPath C:\azd\evidence\portfolio-checks\manifest.json
$result | ConvertTo-Json -Depth 10 |
    Set-Content C:\azd\evidence\portfolio-checks\result.json -Encoding utf8NoBOM
~~~

Set 'executionClass' to 'offline' only for checks already reviewed as offline;
this manifest value documents the check contract and is not an execution
sandbox. For Pester suites, use a small '.ps1' adapter that invokes
'Invoke-Pester -CI -PassThru' and throws when 'FailedCount' is nonzero. Review
captured output before sharing a receipt because check output may contain
private paths or operational details. `exitCode` preserves a nonzero final
native `$LASTEXITCODE`; otherwise, failed PowerShell errors and workers that
return no result are normalized to `1`. `lastNativeExitCode` reports the final
worker value separately. A check that deliberately handles or resets a native
failure must explicitly fail if the queue should treat that check as failed;
the queue cannot reconstruct a code that the check has already reset.
