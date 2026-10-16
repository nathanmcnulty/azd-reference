Describe 'Portfolio update scope guard' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:guard = Join-Path $script:repoRoot 'tooling/Assert-AzdPortfolioUpdateScope.ps1'
    }

    BeforeEach {
        $registryPath = Join-Path $TestDrive "registry-$([guid]::NewGuid().ToString('N')).json"
        $registry = Get-Content (Join-Path $script:repoRoot 'portfolio/consumers.json') -Raw | ConvertFrom-Json
        $registry | ConvertTo-Json -Depth 20 | Set-Content $registryPath
        $consumer = $registry.consumers[0]
        $component = $consumer.components[0]
        $parts = $consumer.repository.Split('/')
        $candidate = [ordered]@{
            consumer = $consumer.id
            component = $component.id
            version = $component.desiredVersion
            repository = $consumer.repository
            repositoryOwner = $parts[-2]
            repositoryName = $parts[-1]
            checkoutDirectory = $consumer.checkoutDirectory
            defaultBranch = $consumer.defaultBranch
            branch = "codex/update-$($consumer.id)-$($component.id)-v$($component.desiredVersion)"
        }
    }

    It 'accepts an exact registry-derived candidate with or without selection' {
        { & $script:guard -RegistryPath $registryPath -CandidateJson ($candidate | ConvertTo-Json) } | Should -Not -Throw
        { & $script:guard -RegistryPath $registryPath -CandidateJson ($candidate | ConvertTo-Json) -ConsumerId $consumer.id -ForPublication -PlanOnly:$false } | Should -Not -Throw
    }

    It 'denies plan-only publication before reading registry or candidate data' {
        { & $script:guard -RegistryPath 'does-not-exist.json' -CandidateJson 'invalid' -ForPublication -PlanOnly } |
            Should -Throw '*Plan-only runs cannot publish*'
    }

    It 'rejects every tampered registry-derived field' -ForEach @('consumer', 'component', 'version', 'repository', 'repositoryOwner', 'repositoryName', 'checkoutDirectory', 'defaultBranch', 'branch') {
        $candidate[$_] = 'tampered'
        { & $script:guard -RegistryPath $registryPath -CandidateJson ($candidate | ConvertTo-Json) } | Should -Throw
    }

    It 'rejects non-string fields' -ForEach @('consumer', 'component', 'version', 'repository', 'repositoryOwner', 'repositoryName', 'checkoutDirectory', 'defaultBranch', 'branch') {
        $candidate[$_] = @($candidate[$_])
        { & $script:guard -RegistryPath $registryPath -CandidateJson ($candidate | ConvertTo-Json) } | Should -Throw '*scalar string*'
    }

    It 'rejects extra candidates and even one-element arrays' {
        foreach ($json in @('[]', 'null', (ConvertTo-Json -InputObject @($candidate)), (ConvertTo-Json -InputObject @($candidate, $candidate)))) {
            { & $script:guard -RegistryPath $registryPath -CandidateJson $json } | Should -Throw '*exactly one candidate object*'
        }
    }

    It 'rejects unrecognized, missing, and duplicate properties' {
        $json = $candidate | ConvertTo-Json -Compress
        { & $script:guard -RegistryPath $registryPath -CandidateJson ($json.Insert(1, '"extra":"value",')) } | Should -Throw '*property*'
        { & $script:guard -RegistryPath $registryPath -CandidateJson ($json.Insert(1, '"consumer":"other",')) } | Should -Throw '*duplicate candidate property*'
        $candidate.Remove('branch')
        { & $script:guard -RegistryPath $registryPath -CandidateJson ($candidate | ConvertTo-Json) } | Should -Throw '*missing required fields*'
    }

    It 'rejects an artifact for a different selected consumer' {
        { & $script:guard -RegistryPath $registryPath -CandidateJson ($candidate | ConvertTo-Json) -ConsumerId $registry.consumers[1].id } |
            Should -Throw '*outside the selected ConsumerId*'
    }

    It 'rejects invalid selectors' -ForEach @('unknown-consumer', 'AZD-PIM', 'azd-*', "azd-pim`n") {
        { & $script:guard -RegistryPath $registryPath -CandidateJson ($candidate | ConvertTo-Json) -ConsumerId $_ } | Should -Throw '*ConsumerId*'
    }

    It 'rejects ambiguous consumers and components' {
        $registry.consumers = @($consumer, $consumer)
        $registry | ConvertTo-Json -Depth 20 | Set-Content $registryPath
        { & $script:guard -RegistryPath $registryPath -CandidateJson ($candidate | ConvertTo-Json) -ConsumerId $consumer.id } | Should -Throw '*duplicate consumer*'
        $registry.consumers = @($consumer)
        $registry.consumers[0].components = @($component, $component)
        $registry | ConvertTo-Json -Depth 20 | Set-Content $registryPath
        { & $script:guard -RegistryPath $registryPath -CandidateJson ($candidate | ConvertTo-Json) } | Should -Throw '*duplicate component*'
    }
}
