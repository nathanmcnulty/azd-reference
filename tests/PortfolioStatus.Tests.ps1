Describe 'Portfolio component status' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
    }

    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $reference = Join-Path $caseRoot 'reference'
        $portfolioRoot = Join-Path $caseRoot 'portfolio'
        New-Item -ItemType Directory -Path $reference, $portfolioRoot | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'components') -Destination $reference -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'schemas') -Destination $reference -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'tooling') -Destination $reference -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'portfolio') -Destination $reference -Recurse
        & git -C $reference init --initial-branch main | Out-Null
        & git -C $reference config core.autocrlf false
        & git -C $reference config user.name 'reference tests'
        & git -C $reference config user.email 'reference-tests@example.invalid'
        & git -C $reference add --all
        & git -C $reference commit -m 'Reference fixture' | Out-Null
        & git -C $reference tag 'component/deployment-validation/v0.3.3'
        $releaseRevision = (& git -C $reference rev-parse HEAD).Trim()
        $statusTool = Join-Path $reference 'tooling/Get-AzdPortfolioStatus.ps1'

        $checkout = Join-Path $portfolioRoot 'consumer-one'
        $managedRelative = 'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psd1'
        $managed = Join-Path $checkout $managedRelative
        New-Item -ItemType Directory -Path (Split-Path -Parent $managed) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'components/powershell/deployment-validation/Azd.DeploymentValidation.psd1') -Destination $managed
        Set-Content -LiteralPath (Join-Path $checkout '.gitattributes') -Encoding utf8NoBOM -Value 'scripts/vendor/** text eol=lf'
        $workflowRoot = Join-Path $checkout '.github/workflows'
        New-Item -ItemType Directory -Path $workflowRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $workflowRoot 'validate-consumer.yml') -Encoding utf8NoBOM -Value "name: Validate`non: push`npermissions:`n  contents: read`njobs: {}"
        $hash = (Get-FileHash -LiteralPath $managed -Algorithm SHA256).Hash.ToLowerInvariant()

        [ordered]@{
            manifestVersion = '1.0'
            components = @(
                [ordered]@{
                    id = 'deployment-validation'
                    version = '0.3.3'
                    sourceRepository = 'https://github.com/nathanmcnulty/azd-reference'
                    sourceRevision = $releaseRevision
                    files = @(
                        [ordered]@{
                            source = 'components/powershell/deployment-validation/Azd.DeploymentValidation.psd1'
                            target = $managedRelative
                            sha256 = $hash
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $checkout 'azd-components.lock.json') -Encoding utf8NoBOM

        & git -C $checkout init --initial-branch main | Out-Null
        & git -C $checkout config core.autocrlf false
        & git -C $checkout config user.name 'portfolio tests'
        & git -C $checkout config user.email 'portfolio-tests@example.invalid'
        & git -C $checkout remote add origin 'https://github.com/example/consumer-one.git'
        & git -C $checkout add --all
        & git -C $checkout commit -m 'Consumer fixture' | Out-Null

        $registryPath = Join-Path $portfolioRoot 'consumers.json'
        $registry = [ordered]@{
            schemaVersion = '1.0'
            referenceRepository = 'https://github.com/nathanmcnulty/azd-reference'
            consumers = @(
                [ordered]@{
                    id = 'consumer-one'
                    repository = 'https://github.com/example/consumer-one'
                    checkoutDirectory = 'consumer-one'
                    solutionRoot = '.'
                    defaultBranch = 'main'
                    repositoryValidationWorkflow = '.github/workflows/validate-consumer.yml'
                    rolloutRing = 'pilot'
                    adoption = 'adopted'
                    components = @(
                        [ordered]@{
                            id = 'deployment-validation'
                            desiredVersion = '0.3.3'
                        }
                    )
                }
            )
        }
        $registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM
    }

    It 'reports a current consumer without changing its checkout' {
        $before = @(& git -C $checkout status --porcelain)
        $result = @(& $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath)
        $result.Count | Should -Be 1
        $result[0].state | Should -Be 'current'
        $result[0].installedVersion | Should -Be '0.3.3'
        @(& git -C $checkout status --porcelain) | Should -Be $before
    }

    It 'reports an outdated component' {
        $data = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $data.consumers[0].components[0].desiredVersion = '0.4.0'
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM
        (@(& $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath))[0].state | Should -Be 'outdated'
    }

    It 'reports a missing consumer-declared repository validation workflow' {
        $data = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $data.consumers[0].repositoryValidationWorkflow = '.github/workflows/validate-other.yml'
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        $result = (@(& $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath))[0]
        $result.findings | Should -Contain 'repositoryValidationWorkflowMissing:.github/workflows/validate-other.yml'
    }

    It 'honors explicit LF policy for a CRLF working representation' {
        $text = [System.IO.File]::ReadAllText($managed).Replace("`r`n", "`n").Replace("`n", "`r`n")
        [System.IO.File]::WriteAllText($managed, $text, [System.Text.UTF8Encoding]::new($false))
        (@(& $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath))[0].state | Should -Be 'current'
    }

    It 'reports a missing managed file and fails when requested' {
        Remove-Item -LiteralPath $managed
        (@(& $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath))[0].state | Should -Be 'missing'
        { & $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -FailOnFindings } | Should -Throw '*portfolio contains*'
    }

    It 'rejects duplicate component declarations' {
        $data = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $data.consumers[0].components = @($data.consumers[0].components[0], $data.consumers[0].components[0])
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM
        { & $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath } | Should -Throw '*duplicate component*'
    }

    It 'reports a lock that does not originate from the installed release tag' {
        $lockPath = Join-Path $checkout 'azd-components.lock.json'
        $data = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        $data.components[0].sourceRevision = '0123456789abcdef0123456789abcdef01234567'
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $lockPath -Encoding utf8NoBOM
        (@(& $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath))[0].state | Should -Be 'sourceRevisionMismatch'
    }

    It 'still reports an outdated version when its installed release tag is unavailable' {
        $lockPath = Join-Path $checkout 'azd-components.lock.json'
        $data = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        $data.components[0].version = '0.3.2'
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $lockPath -Encoding utf8NoBOM
        $result = (@(& $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath))[0]
        $result.state | Should -Be 'outdated'
        $result.findings | Should -Contain 'installedReleaseTagMissing:deployment-validation@0.3.2'
    }

    It 'rejects a release tag whose committed manifest has another version' {
        & git -C $reference tag 'component/deployment-validation/v0.4.0'
        $lockPath = Join-Path $checkout 'azd-components.lock.json'
        $data = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        $data.components[0].version = '0.4.0'
        $data.components[0].sourceRevision = $releaseRevision
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $lockPath -Encoding utf8NoBOM
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $registry.consumers[0].components[0].desiredVersion = '0.4.0'
        $registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        $result = (@(& $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath))[0]
        $result.state | Should -Be 'installedReleaseTagInvalid'
        $result.findings | Should -Contain 'desiredReleaseTagInvalid:deployment-validation@0.4.0'
    }

    It 'audits action pinning, workflow permissions, and bounded dependency updates' {
        $workflowRoot = Join-Path $checkout '.github/workflows'
        New-Item -ItemType Directory -Path $workflowRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $workflowRoot 'validate.yml') -Encoding utf8NoBOM -Value "name: Validate`non: push`njobs:`n  test:`n    runs-on: ubuntu-latest`n    steps:`n      - uses: actions/checkout@v4"
        New-Item -ItemType Directory -Path (Join-Path $checkout '.github') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $checkout '.github/dependabot.yml') -Encoding utf8NoBOM -Value "version: 2`nupdates: []"

        $result = (@(& $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath))[0]
        @($result.findings | Where-Object { $_ -like 'workflowActionUnpinned:*' }).Count | Should -Be 1
        @($result.findings | Where-Object { $_ -like 'workflowPermissionsNotRestricted:*' }).Count | Should -Be 1
        $result.findings | Should -Contain 'dependencyUpdatesNotGroupedAndBounded'
    }

    It 'requires every Dependabot update stream to be grouped and bounded' {
        New-Item -ItemType Directory -Path (Join-Path $checkout '.github') -Force | Out-Null
        $dependabot = @'
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    open-pull-requests-limit: 5
    groups:
      actions:
        patterns: ['*']
  - package-ecosystem: npm
    directory: /
    schedule:
      interval: weekly
'@
        Set-Content -LiteralPath (Join-Path $checkout '.github/dependabot.yml') -Encoding utf8NoBOM -Value $dependabot
        $result = (@(& $statusTool -PortfolioRoot $portfolioRoot -RegistryPath $registryPath))[0]
        $result.findings | Should -Contain 'dependencyUpdatesNotGroupedAndBounded'
    }
}
