BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $skeletonPath = Join-Path $repositoryRoot 'skeleton'
    $reportSchema = Join-Path $repositoryRoot 'schemas/deployment-validation.schema.json'
}

Describe 'Starter skeleton' {
    It 'runs Plan without authentication, cloud calls, or delivery actions' {
        $consumer = Join-Path $TestDrive 'consumer'
        Copy-Item -LiteralPath $skeletonPath -Destination $consumer -Recurse

        $script:azInvoked = $false
        function global:az {
            $script:azInvoked = $true
            throw 'The Azure CLI must not be invoked during Plan.'
        }

        try {
            $report = & (Join-Path $consumer 'scripts/Test-Deployment.ps1') `
                -Plan `
                -OutputPath 'reports/plan.json' `
                -PassThru

            $script:azInvoked | Should -BeFalse
            $report.mode | Should -Be 'plan'
            $report.outcome | Should -Be 'planned'
            @($report.checks | Where-Object status -notin 'planned', 'skipped').Count | Should -Be 0

            $reportPath = Join-Path $consumer 'reports/plan.json'
            Test-Path -LiteralPath $reportPath -PathType Leaf | Should -BeTrue
            (Get-Content -LiteralPath $reportPath -Raw |
                Test-Json -SchemaFile $reportSchema -ErrorAction Stop) | Should -BeTrue
        }
        finally {
            Remove-Item Function:\az -ErrorAction SilentlyContinue
        }
    }
}
