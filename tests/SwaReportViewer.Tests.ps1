Describe 'Offline SWA Standard authorization and publisher prototype' {
    It 'passes the registered dependency-free Node contract suite' {
        $node = Get-Command node -CommandType Application -ErrorAction Stop
        $testPath = Join-Path $PSScriptRoot 'swa-report-viewer/prototype.test.cjs'
        $output = & $node.Source --test --test-reporter=tap $testPath 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $output | Should -Match '# fail 0'
        $output | Should -Not -Match '# tests 0'
    }
}
