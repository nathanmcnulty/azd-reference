Describe 'Bounded portfolio consumer validation' {
    BeforeAll {
        $updaterSource = Join-Path (Split-Path $PSScriptRoot -Parent) 'tooling/Update-AzdPortfolio.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($updaterSource, [ref] $tokens, [ref] $parseErrors)
        $parseErrors.Count | Should -Be 0
        $functionAst = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-BoundedValidation'
            }, $true)
        $functionAst | Should -Not -BeNullOrEmpty
        Invoke-Expression $functionAst.Extent.Text
    }

    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null
        $validationPath = Join-Path $caseRoot 'Validate.ps1'
    }

    AfterEach {
        # Real child fixtures have their own finite lifetimes as a backstop.
        foreach ($pidFile in Get-ChildItem -LiteralPath $caseRoot -Filter '*.pid') {
            $child = Get-Process -Id ([int] (Get-Content -LiteralPath $pidFile.FullName -Raw)) -ErrorAction SilentlyContinue
            if ($child) {
                try {
                    $child.Kill($true)
                    [void] $child.WaitForExit(2000)
                }
                finally { $child.Dispose() }
            }
        }
    }

    It 'returns both streams, including large output and unterminated Unicode text' {
        @'
if ((Get-Location).Path -ne $PSScriptRoot) { throw 'Unexpected validation working directory.' }
[Console]::Out.WriteLine('')
[Console]::Out.WriteLine(('o' * 131072))
[Console]::Error.WriteLine(('e' * 131072))
[Console]::Out.Write('stdout-final-é')
[Console]::Error.Write('stderr-final-λ')
'@ | Set-Content -LiteralPath $validationPath -Encoding utf8NoBOM

        $output = @(Invoke-BoundedValidation -ValidationPath $validationPath -WorkingDirectory $caseRoot -TimeoutMinutes 1)

        $output.Count | Should -Be 4
        $output[0] | Should -Be ('o' * 131072)
        $output[1] | Should -Be 'stdout-final-é'
        $output[2] | Should -Be ('e' * 131072)
        $output[3] | Should -Be 'stderr-final-λ'
    }

    It 'keeps the nonzero exit code and both captured streams' {
        @'
[Console]::Out.Write('nonzero-stdout')
[Console]::Error.Write('nonzero-stderr')
exit 17
'@ | Set-Content -LiteralPath $validationPath -Encoding utf8NoBOM

        $failure = $null
        try { Invoke-BoundedValidation -ValidationPath $validationPath -WorkingDirectory $caseRoot -TimeoutMinutes 1 }
        catch { $failure = $_.Exception.Message }

        $failure | Should -Match '^Consumer validation failed with exit code 17\.'
        $failure | Should -Match 'nonzero-stdout'
        $failure | Should -Match 'nonzero-stderr'
    }

    It 'preserves both streams when terminating a real timed-out child' {
        @'
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'validation.pid'), [string] $PID)
[Console]::Out.Write('timeout-stdout')
[Console]::Error.Write('timeout-stderr')
Start-Sleep -Seconds 90
'@ | Set-Content -LiteralPath $validationPath -Encoding utf8NoBOM

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $failure = $null
        try { Invoke-BoundedValidation -ValidationPath $validationPath -WorkingDirectory $caseRoot -TimeoutMinutes 1 }
        catch { $failure = $_.Exception.Message }

        $failure | Should -Match '^Consumer validation exceeded its 1 minute timeout\.'
        $failure | Should -Match 'timeout-stdout'
        $failure | Should -Match 'timeout-stderr'
        $timer.Elapsed.TotalSeconds | Should -BeLessThan 75
        $childId = [int] (Get-Content -LiteralPath (Join-Path $caseRoot 'validation.pid') -Raw)
        Get-Process -Id $childId -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'preserves the timeout when cancellation cleanup throws and warnings are terminating' {
        # Fault injection stays in the test. The real cancellation source invokes
        # this callback in finally, exercising the cleanup catch without a test API.
        $probeDefinition = $functionAst.Extent.Text.Replace(
            'function Invoke-BoundedValidation {', 'function Invoke-BoundedValidationCleanupProbe {'
        ).Replace(
            '$readCancellation = [System.Threading.CancellationTokenSource]::new()',
            '$readCancellation = [System.Threading.CancellationTokenSource]::new(); [void] $readCancellation.Token.Register([System.Action] { throw "cleanup-callback-sentinel" })'
        )
        Invoke-Expression $probeDefinition
        'Start-Sleep -Seconds 10' | Set-Content -LiteralPath $validationPath -Encoding utf8NoBOM
        $WarningPreference = 'Stop'
        $warnings = @()
        $failure = $null
        try {
            Invoke-BoundedValidationCleanupProbe -ValidationPath $validationPath -WorkingDirectory $caseRoot -TimeoutMinutes 0 -WarningAction Stop -WarningVariable warnings 3>$null
        }
        catch { $failure = $_.Exception.Message }

        $failure | Should -Match '^Consumer validation exceeded its 0 minute timeout\.'
        ($warnings | Out-String) | Should -Match 'read cancellation failed:.*cleanup-callback-sentinel'
    }

    It 'bounds inherited-pipe draining after root exit <ExitCode> and keeps captured output' -ForEach @(
        @{ ExitCode = 0 }
        @{ ExitCode = 23 }
    ) {
        @'
[Console]::Out.Write('descendant-stdout')
[Console]::Error.Write('descendant-stderr')
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'descendant.ready'), 'ready')
Start-Sleep -Seconds 30
'@ | Set-Content -LiteralPath (Join-Path $caseRoot 'Descendant.ps1') -Encoding utf8NoBOM
        @'
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = 'pwsh'
$startInfo.UseShellExecute = $false
foreach ($argument in '-NoProfile', '-NonInteractive', '-File', (Join-Path $PSScriptRoot 'Descendant.ps1')) {
    [void] $startInfo.ArgumentList.Add($argument)
}
$child = [System.Diagnostics.Process]::Start($startInfo)
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'descendant.pid'), [string] $child.Id)
$timer = [System.Diagnostics.Stopwatch]::StartNew()
while (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'descendant.ready'))) {
    if ($timer.Elapsed.TotalSeconds -gt 10) { throw 'Descendant did not start.' }
    Start-Sleep -Milliseconds 20
}
[Console]::Out.Write('parent-stdout')
[Console]::Error.Write('parent-stderr')
exit EXIT_CODE
'@.Replace('EXIT_CODE', [string] $ExitCode) | Set-Content -LiteralPath $validationPath -Encoding utf8NoBOM

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $failure = $null
        try { Invoke-BoundedValidation -ValidationPath $validationPath -WorkingDirectory $caseRoot -TimeoutMinutes 1 }
        catch { $failure = $_.Exception.Message }

        if ($ExitCode -ne 0) { $failure | Should -Match "^Consumer validation failed with exit code $ExitCode\." }
        $failure | Should -Match 'output capture did not finish within the 5 second cleanup window'
        foreach ($marker in 'parent-stdout', 'parent-stderr', 'descendant-stdout', 'descendant-stderr') {
            $failure | Should -Match $marker
        }
        $timer.Elapsed.TotalSeconds | Should -BeLessThan 20
        $childId = [int] (Get-Content -LiteralPath (Join-Path $caseRoot 'descendant.pid') -Raw)
        Get-Process -Id $childId -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }
}
