Describe 'Portfolio offline check queue' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:queueTool = Join-Path $script:repoRoot 'tooling/Invoke-AzdPortfolioCheckQueue.ps1'
        $tokens = $null
        $parseErrors = $null
        $toolAst = [System.Management.Automation.Language.Parser]::ParseFile($script:queueTool, [ref] $tokens, [ref] $parseErrors)
        $parseErrors.Count | Should -Be 0
        $failureMessageAst = $toolAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Get-QueueJobFailureMessage'
            }, $true)
        $failureMessageAst | Should -Not -BeNullOrEmpty
        $failureMessageScript = [scriptblock]::Create($failureMessageAst.Extent.Text)
        . $failureMessageScript
        $failureResultAst = $toolAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Get-QueueFailureResult'
            }, $true)
        $failureResultAst | Should -Not -BeNullOrEmpty
        $failureResultScript = [scriptblock]::Create($failureResultAst.Extent.Text)
        . $failureResultScript
        $utcTimestampAst = $toolAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'ConvertTo-UtcTimestamp'
            }, $true)
        $utcTimestampAst | Should -Not -BeNullOrEmpty
        $utcTimestampScript = [scriptblock]::Create($utcTimestampAst.Extent.Text)
        . $utcTimestampScript
    }

    BeforeEach {
        $script:caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:caseRoot -Force | Out-Null

        $script:recordWorker = Join-Path $script:caseRoot 'record-check.ps1'
        @'
param(
    [Parameter(Mandatory)][string] $RecordPath,
    [Parameter(Mandatory)][int] $DelayMilliseconds
)

$startedAt = [DateTimeOffset]::UtcNow
Start-Sleep -Milliseconds $DelayMilliseconds
$finishedAt = [DateTimeOffset]::UtcNow
[ordered]@{
    startedAt = $startedAt.ToUniversalTime().ToString('o')
    finishedAt = $finishedAt.ToUniversalTime().ToString('o')
} | ConvertTo-Json -Compress | Set-Content -LiteralPath $RecordPath -Encoding utf8NoBOM
'recorded'
'@ | Set-Content -LiteralPath $script:recordWorker -Encoding utf8NoBOM

        $script:failureWorker = Join-Path $script:caseRoot 'fail-check.ps1'
        @'
Write-Output 'output-before-failure'
throw 'intentional offline fixture failure'
'@ | Set-Content -LiteralPath $script:failureWorker -Encoding utf8NoBOM
    }

    It 'runs independent checks in parallel and never exceeds five slots while recording timing' {
        $checks = @(
            foreach ($index in 1..8) {
                $recordPath = Join-Path $script:caseRoot "interval-$index.json"
                [ordered]@{
                    id = "independent-$index"
                    executionClass = 'offline'
                    script = 'record-check.ps1'
                    arguments = @($recordPath, '650')
                    serializationKey = "isolated-$index"
                }
            }
        )
        $manifestPath = Join-Path $script:caseRoot 'manifest.json'
        [ordered]@{ schemaVersion = '1.0'; checks = $checks } |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

        $result = & $script:queueTool -ManifestPath $manifestPath -MaxConcurrency 5

        $result.checkCount | Should -Be 8
        $result.passedCount | Should -Be 8
        $result.failedCount | Should -Be 0
        $result.maxConcurrency | Should -Be 5
        $result.observedMaxConcurrency | Should -BeLessOrEqual 5
        $result.elapsedMilliseconds | Should -BeGreaterThan 0
        $result.checks.Count | Should -Be 8

        foreach ($check in $result.checks) {
            $check.status | Should -Be 'passed'
            $check.exitCode | Should -Be 0
            $check.queuedAt | Should -Match 'Z$'
            $check.startedAt | Should -Match 'Z$'
            $check.finishedAt | Should -Match 'Z$'
            $check.queueWaitMilliseconds | Should -BeGreaterOrEqual 0
            $check.runMilliseconds | Should -BeGreaterThan 0
        }

        foreach ($index in 1..8) {
            Test-Path -LiteralPath (Join-Path $script:caseRoot "interval-$index.json") | Should -BeTrue
        }
        $intervals = @(
            foreach ($check in $result.checks) {
                [pscustomobject]@{
                    start = [DateTimeOffset]::Parse($check.startedAt).ToUnixTimeMilliseconds()
                    finish = [DateTimeOffset]::Parse($check.finishedAt).ToUnixTimeMilliseconds()
                }
            }
        )
        $peak = 0
        foreach ($candidate in $intervals) {
            $active = @(
                $intervals | Where-Object {
                    $_.start -le $candidate.start -and $_.finish -gt $candidate.start
                }
            ).Count
            if ($active -gt $peak) { $peak = $active }
        }
        $peak | Should -BeGreaterThan 1
        $peak | Should -BeLessOrEqual 5
        $result.observedMaxConcurrency | Should -BeGreaterOrEqual $peak
        $result.observedMaxConcurrency | Should -BeLessOrEqual 5
    }

    It 'serializes checks with the same key but lets an independent check pass a blocked item' {
        $checks = @(
            [ordered]@{
                id = 'shared-first'
                executionClass = 'offline'
                script = 'record-check.ps1'
                arguments = @((Join-Path $script:caseRoot 'shared-first.json'), '1200')
                serializationKey = 'checkout-a'
            },
            [ordered]@{
                id = 'shared-second'
                executionClass = 'offline'
                script = 'record-check.ps1'
                arguments = @((Join-Path $script:caseRoot 'shared-second.json'), '200')
                serializationKey = 'checkout-a'
            },
            [ordered]@{
                id = 'independent'
                executionClass = 'offline'
                script = 'record-check.ps1'
                arguments = @((Join-Path $script:caseRoot 'independent.json'), '50')
                serializationKey = 'checkout-b'
            },
            [ordered]@{
                id = 'shared-third'
                executionClass = 'offline'
                script = 'record-check.ps1'
                arguments = @((Join-Path $script:caseRoot 'shared-third.json'), '100')
                serializationKey = 'checkout-a'
            }
        )
        $manifestPath = Join-Path $script:caseRoot 'manifest.json'
        [ordered]@{ schemaVersion = '1.0'; checks = $checks } |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

        $result = & $script:queueTool -ManifestPath $manifestPath -MaxConcurrency 2
        $byId = @{}
        foreach ($check in $result.checks) { $byId[$check.id] = $check }

        $first = Get-Content -LiteralPath (Join-Path $script:caseRoot 'shared-first.json') -Raw | ConvertFrom-Json
        $second = Get-Content -LiteralPath (Join-Path $script:caseRoot 'shared-second.json') -Raw | ConvertFrom-Json
        $third = Get-Content -LiteralPath (Join-Path $script:caseRoot 'shared-third.json') -Raw | ConvertFrom-Json
        $independent = Get-Content -LiteralPath (Join-Path $script:caseRoot 'independent.json') -Raw | ConvertFrom-Json

        [DateTimeOffset]::Parse($second.startedAt) | Should -BeGreaterOrEqual ([DateTimeOffset]::Parse($first.finishedAt))
        [DateTimeOffset]::Parse($third.startedAt) | Should -BeGreaterOrEqual ([DateTimeOffset]::Parse($second.finishedAt))
        [DateTimeOffset]::Parse($independent.startedAt) | Should -BeLessThan ([DateTimeOffset]::Parse($first.finishedAt))
        $byId['shared-second'].queueWaitMilliseconds | Should -BeGreaterThan 0
        $result.observedMaxConcurrency | Should -BeLessOrEqual 2
        $result.passedCount | Should -Be 4
        $result.failedCount | Should -Be 0
    }

    It 'records failed outcomes and continues independent work' {
        $checks = @(
            [ordered]@{
                id = 'expected-failure'
                executionClass = 'offline'
                script = 'fail-check.ps1'
                arguments = @()
                serializationKey = 'fail-fixture'
            },
            [ordered]@{
                id = 'after-failure'
                executionClass = 'offline'
                script = 'record-check.ps1'
                arguments = @((Join-Path $script:caseRoot 'after-failure.json'), '10')
                serializationKey = 'success-fixture'
            }
        )
        $manifestPath = Join-Path $script:caseRoot 'manifest.json'
        [ordered]@{ schemaVersion = '1.0'; checks = $checks } |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

        $result = & $script:queueTool -ManifestPath $manifestPath -MaxConcurrency 2

        $result.checkCount | Should -Be 2
        $result.failedCount | Should -Be 1
        $result.passedCount | Should -Be 1
        $result.checks[0].id | Should -Be 'expected-failure'
        $result.checks[0].status | Should -Be 'failed'
        $result.checks[0].exitCode | Should -Be 1
        $result.checks[0].error | Should -Match 'intentional offline fixture failure'
        $result.checks[0].output | Should -Contain 'output-before-failure'
        $result.checks[1].id | Should -Be 'after-failure'
        $result.checks[1].status | Should -Be 'passed'
        Test-Path -LiteralPath (Join-Path $script:caseRoot 'after-failure.json') | Should -BeTrue
    }

    It 'builds a no-result failure for a ThreadJob with zero child jobs' {
        Import-Module Microsoft.PowerShell.ThreadJob -ErrorAction Stop
        $job = Start-ThreadJob -Name 'portfolio-no-result-test' -ScriptBlock { exit 17 }
        try {
            $null = Wait-Job -Job $job -Timeout 5
            $job.State | Should -Be 'Completed'
            @($job.ChildJobs).Count | Should -Be 0
            @(Receive-Job -Job $job -ErrorAction SilentlyContinue).Count | Should -Be 0

            $message = Get-QueueJobFailureMessage -Job $job
            $message | Should -BeExactly "Worker ended in state 'Completed' without returning a result."
        }
        finally {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    It 'normalizes a no-result job to a failed queue item while preserving the last native code separately' {
        $task = [pscustomobject]@{
            sequence = 3
            id = 'empty-worker'
            scriptPath = 'empty-worker.ps1'
            serializationKey = 'empty-worker'
            queuedAt = [DateTimeOffset]::UtcNow
            enqueueTimestamp = [System.Diagnostics.Stopwatch]::GetTimestamp()
        }

        $result = Get-QueueFailureResult -Task $task -Message "Worker ended in state 'Completed' without returning a result."

        $result.status | Should -Be 'failed'
        $result.exitCode | Should -Be 1
        $result.lastNativeExitCode | Should -BeNullOrEmpty
        $result.error | Should -Match "without returning a result"
    }

    It 'prefers the parent failure reason and falls back to a child reason' {
        $parentReason = [System.InvalidOperationException]::new('parent worker failure')
        $childReason = [System.InvalidOperationException]::new('child worker failure')
        $job = [pscustomobject]@{
            State = 'Failed'
            JobStateInfo = [pscustomobject]@{ Reason = $parentReason }
            ChildJobs = @([pscustomobject]@{ JobStateInfo = [pscustomobject]@{ Reason = $childReason } })
        }

        Get-QueueJobFailureMessage -Job $job -ReceiveFailureMessage 'receive diagnostic' |
            Should -BeExactly 'parent worker failure Receive-Job detail: receive diagnostic'

        $job.JobStateInfo.Reason = $null
        Get-QueueJobFailureMessage -Job $job |
            Should -BeExactly 'child worker failure'
    }

    It 'normalizes PowerShell errors and separately reports a nonzero native exit' {
        $errorWorker = Join-Path $script:caseRoot 'nonterminating-error.ps1'
        @'
Write-Output 'output-before-error-record'
Write-Error -Message 'intentional offline error record' -ErrorAction Continue
'@ | Set-Content -LiteralPath $errorWorker -Encoding utf8NoBOM

        $nativeWorker = Join-Path $script:caseRoot 'native-exit.ps1'
        $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source.Replace("'", "''")
        "& '$pwshPath' -NoLogo -NoProfile -Command 'exit 17'" |
            Set-Content -LiteralPath $nativeWorker -Encoding utf8NoBOM

        $manifestPath = Join-Path $script:caseRoot 'manifest.json'
        [ordered]@{
            schemaVersion = '1.0'
            checks = @(
                [ordered]@{
                    id = 'powershell-error-record'
                    executionClass = 'offline'
                    script = 'nonterminating-error.ps1'
                    serializationKey = 'powershell-error'
                },
                [ordered]@{
                    id = 'native-nonzero-exit'
                    executionClass = 'offline'
                    script = 'native-exit.ps1'
                    serializationKey = 'native-exit'
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

        $result = & $script:queueTool -ManifestPath $manifestPath -MaxConcurrency 1

        $result.checks[0].status | Should -Be 'failed'
        $result.checks[0].exitCode | Should -Be 1
        $result.checks[0].lastNativeExitCode | Should -Be 0
        $result.checks[0].output | Should -Contain 'output-before-error-record'
        $result.checks[0].error | Should -Match 'intentional offline error record'
        $result.checks[1].status | Should -Be 'failed'
        $result.checks[1].exitCode | Should -Be 17
        $result.checks[1].lastNativeExitCode | Should -Be 17
    }

    It 'rejects non-offline work before running any script' {
        $markerPath = Join-Path $script:caseRoot 'must-not-exist.txt'
        $manifestPath = Join-Path $script:caseRoot 'manifest.json'
        [ordered]@{
            schemaVersion = '1.0'
            checks = @(
                [ordered]@{
                    id = 'azure-check'
                    executionClass = 'azure'
                    script = 'record-check.ps1'
                    arguments = @($markerPath, '1')
                    serializationKey = 'tenant-subscription-target'
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

        { & $script:queueTool -ManifestPath $manifestPath } | Should -Throw '*executionClass*offline*'
        Test-Path -LiteralPath $markerPath | Should -BeFalse
    }

    It 'emits parseable JSON with queue and per-check timings' {
        $manifestPath = Join-Path $script:caseRoot 'manifest.json'
        [ordered]@{
            schemaVersion = '1.0'
            checks = @(
                [ordered]@{
                    id = 'json-check'
                    executionClass = 'offline'
                    script = 'record-check.ps1'
                    arguments = @((Join-Path $script:caseRoot 'json-check.json'), '10')
                    serializationKey = 'json-fixture'
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

        $json = (& $script:queueTool -ManifestPath $manifestPath -AsJson) -join [Environment]::NewLine
        $result = $json | ConvertFrom-Json -ErrorAction Stop

        $result.checkCount | Should -Be 1
        $result.passedCount | Should -Be 1
        $result.observedMaxConcurrency | Should -Be 1
        $result.checks[0].queueWaitMilliseconds | Should -BeGreaterOrEqual 0
        $result.checks[0].runMilliseconds | Should -BeGreaterThan 0
        $json | Should -Match '"queuedAt"\s*:\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z"'
        $json | Should -Match '"startedAt"\s*:\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z"'
        $json | Should -Match '"finishedAt"\s*:\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z"'
    }

    It 'rejects a concurrency value above the hard five-slot ceiling' {
        $manifestPath = Join-Path $script:caseRoot 'manifest.json'
        [ordered]@{
            schemaVersion = '1.0'
            checks = @(
                [ordered]@{
                    id = 'one'
                    executionClass = 'offline'
                    script = 'record-check.ps1'
                    arguments = @((Join-Path $script:caseRoot 'one.json'), '1')
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

        { & $script:queueTool -ManifestPath $manifestPath -MaxConcurrency 6 } | Should -Throw
    }
}
