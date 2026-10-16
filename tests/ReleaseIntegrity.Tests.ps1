Describe 'Release integrity standard' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:tool = Join-Path $script:repoRoot 'tooling/Test-AzdReleaseIntegrity.ps1'
    }

    It 'passes the reference repository release-integrity starter' {
        $result = @(& $script:tool -RepositoryRoot $script:repoRoot)
        $result.Count | Should -Be 1
        $result[0].state | Should -Be 'current'
        $result[0].enforcement | Should -Be 'migration'
    }

    It 'reports missing required security-policy sections' {
        $testRoot = Join-Path $TestDrive 'missing-security-section'
        New-Item -ItemType Directory -Path (Join-Path $testRoot '.github/workflows') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot '.github/workflows/release-attestation.yml') -Destination (Join-Path $testRoot '.github/workflows/release-attestation.yml')
        $security = Get-Content -LiteralPath (Join-Path $script:repoRoot 'SECURITY.md') -Raw
        $security = $security -replace '(?m)^## Response targets\r?\n', ''
        Set-Content -LiteralPath (Join-Path $testRoot 'SECURITY.md') -Value $security -Encoding utf8NoBOM

        $result = @(& $script:tool -RepositoryRoot $testRoot)
        $result[0].findings | Should -Contain 'securityPolicyHeadingMissing:## Response targets'
    }

    It 'reports unpinned release workflow actions' {
        $testRoot = Join-Path $TestDrive 'unpinned-release-action'
        New-Item -ItemType Directory -Path (Join-Path $testRoot '.github/workflows') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'SECURITY.md') -Destination (Join-Path $testRoot 'SECURITY.md')
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/release-attestation.yml') -Raw
        $workflow = $workflow -replace 'actions/attest@[0-9a-f]{40}', 'actions/attest@v4'
        Set-Content -LiteralPath (Join-Path $testRoot '.github/workflows/release-attestation.yml') -Value $workflow -Encoding utf8NoBOM

        $result = @(& $script:tool -RepositoryRoot $testRoot)
        $result.findings | Should -Contain 'attestationActionUnpinnedOrMissing'
        @($result.findings | Where-Object { $_ -like 'workflowActionUnpinned:actions/attest@v4' }).Count | Should -Be 1
    }
}

Describe 'Explicit component release acceptance' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:tool = Join-Path $script:repoRoot 'tooling/Test-AzdReleaseIntegrity.ps1'

        function Set-FixtureRelease {
            & git -C $reference -c commit.gpgsign=false add --all
            & git -C $reference -c commit.gpgsign=false commit --quiet --allow-empty -m 'Fixture release'
            if ($LASTEXITCODE -ne 0) { throw 'Unable to commit the local release fixture.' }
            $accept.ExpectedCommit = (& git -C $reference rev-parse HEAD).Trim()
            & git -C $reference -c tag.gpgsign=false tag -f -a $accept.ExpectedTag -m 'Fixture annotated tag' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Unable to tag the local release fixture.' }
            $tagSha = (& git -C $reference rev-parse "refs/tags/$($accept.ExpectedTag)^{tag}").Trim()
            $global:ReleaseAcceptanceRef = @{
                ref = "refs/tags/$($accept.ExpectedTag)"
                object = @{ type = 'tag'; sha = $tagSha }
            }
            $global:ReleaseAcceptanceTag = @{
                sha = $tagSha
                tag = $accept.ExpectedTag
                object = @{ type = 'commit'; sha = $accept.ExpectedCommit }
                verification = @{ verified = $true }
            }
        }
    }

    BeforeEach {
        $reference = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $componentRoot = Join-Path $reference 'components/powershell/example-component'
        New-Item -ItemType Directory -Path $componentRoot -Force | Out-Null
        $manifestPath = Join-Path $componentRoot 'component.json'
        '{"id":"example-component","version":"1.2.3"}' | Set-Content -LiteralPath $manifestPath
        & git -C $reference init --quiet --initial-branch main
        & git -C $reference config user.name 'Release acceptance fixture'
        & git -C $reference config user.email 'release-test@example.invalid'
        $bundle = Join-Path $TestDrive ('bundle-' + [guid]::NewGuid().ToString('N') + '.tar.gz')
        'Supplied fixture bytes; gh is always mocked.' | Set-Content -LiteralPath $bundle
        $accept = @{
            RepositoryRoot = $reference
            AcceptComponentRelease = $true
            ExpectedRepository = 'nathanmcnulty/azd-reference'
            ExpectedTag = 'component/example-component/v1.2.3'
            ExpectedCommit = $null
            BundlePath = $bundle
        }
        Set-FixtureRelease
        $global:ReleaseAcceptanceCalls = [System.Collections.Generic.List[object]]::new()
        $global:ReleaseAcceptanceRefRaw = $null
        $global:ReleaseAcceptanceTagRaw = $null
        $global:ReleaseAcceptanceApiExit = 0
        $global:ReleaseAcceptanceVerifyExit = 0
        $global:ReleaseAcceptanceMutateBundle = $false
        $originalHost = $env:GH_HOST
        $env:GH_HOST = 'github.com'
        function global:gh {
            param([Parameter(ValueFromRemainingArguments)][string[]] $ArgumentList)

            $global:ReleaseAcceptanceCalls.Add($ArgumentList)
            if ($ArgumentList[0] -eq 'api') {
                $global:LASTEXITCODE = $global:ReleaseAcceptanceApiExit
                if ($ArgumentList[-1] -like '*/git/ref/tags/*') {
                    if ($null -ne $global:ReleaseAcceptanceRefRaw) { return $global:ReleaseAcceptanceRefRaw }
                    return ($global:ReleaseAcceptanceRef | ConvertTo-Json -Depth 10)
                }
                if ($ArgumentList[-1] -like '*/git/tags/*') {
                    if ($null -ne $global:ReleaseAcceptanceTagRaw) { return $global:ReleaseAcceptanceTagRaw }
                    return ($global:ReleaseAcceptanceTag | ConvertTo-Json -Depth 10)
                }
            }
            if ($ArgumentList[0] -eq 'attestation' -and $ArgumentList[1] -eq 'verify') {
                $global:LASTEXITCODE = $global:ReleaseAcceptanceVerifyExit
                if ($global:ReleaseAcceptanceMutateBundle) {
                    Add-Content -LiteralPath $ArgumentList[2] -Value 'Changed while verifying'
                }
                return 'Mock verification output'
            }
            throw "Unexpected gh call in offline tests: $($ArgumentList -join ' ')"
        }
    }

    AfterEach {
        Remove-Item Function:\gh -ErrorAction SilentlyContinue
        Remove-Variable ReleaseAcceptance* -Scope Global -ErrorAction SilentlyContinue
        $env:GH_HOST = $originalHost
    }

    It 'accepts only the expected identity and records the supplied bundle digest' {
        $result = @(& $script:tool @accept)
        $result.Count | Should -Be 1
        $result[0].state | Should -BeExactly 'accepted'
        $result[0].repository | Should -BeExactly $accept.ExpectedRepository
        $result[0].tag | Should -BeExactly $accept.ExpectedTag
        $result[0].revision | Should -BeExactly $accept.ExpectedCommit
        $result[0].component | Should -BeExactly 'example-component'
        $result[0].version | Should -BeExactly '1.2.3'
        $result[0].manifest | Should -BeExactly 'components/powershell/example-component/component.json'
        $result[0].tagObject | Should -BeExactly $global:ReleaseAcceptanceTag.sha
        $result[0].bundleSha256 | Should -BeExactly (Get-FileHash $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
        $result[0].attestationVerified | Should -BeTrue
        $result[0].evidenceScope | Should -BeExactly 'signed-tag-and-attested-bundle'
        $global:ReleaseAcceptanceCalls.Count | Should -Be 3
        ($global:ReleaseAcceptanceCalls[0] -join '|') | Should -BeExactly "api|--hostname|github.com|repos/nathanmcnulty/azd-reference/git/ref/tags/$($accept.ExpectedTag)"
        ($global:ReleaseAcceptanceCalls[1] -join '|') | Should -BeExactly "api|--hostname|github.com|repos/nathanmcnulty/azd-reference/git/tags/$($global:ReleaseAcceptanceTag.sha)"
        ($global:ReleaseAcceptanceCalls[2] -join '|') | Should -BeExactly (
            "attestation|verify|$bundle|--hostname|github.com|--repo|nathanmcnulty/azd-reference|--signer-workflow|nathanmcnulty/azd-reference/.github/workflows/release-attestation.yml|--signer-digest|$($accept.ExpectedCommit)|--source-ref|refs/tags/$($accept.ExpectedTag)|--source-digest|$($accept.ExpectedCommit)|--predicate-type|https://slsa.dev/provenance/v1|--cert-oidc-issuer|https://token.actions.githubusercontent.com|--deny-self-hosted-runners"
        )
    }

    It 'returns the same successful acceptance as JSON' {
        $result = & $script:tool @accept -AsJson | ConvertFrom-Json
        $result.state | Should -BeExactly 'accepted'
        $result.bundleSha256 | Should -Match '^[0-9a-f]{64}$'
    }

    It 'reads the immutable manifest rather than uncommitted working-tree content' {
        '{"id":"other-component","version":"9.9.9"}' | Set-Content -LiteralPath $manifestPath
        (& $script:tool @accept).state | Should -BeExactly 'accepted'
    }

    It 'accepts a valid prerelease version with the same exact manifest' {
        $accept.ExpectedTag = 'component/example-component/v1.2.3-rc.1'
        '{"id":"example-component","version":"1.2.3-rc.1"}' | Set-Content -LiteralPath $manifestPath
        Set-FixtureRelease
        (& $script:tool @accept).version | Should -BeExactly '1.2.3-rc.1'
    }

    It 'does not let a local replacement object hide a mismatched tagged manifest' {
        '{"id":"example-component","version":"9.9.9"}' | Set-Content -LiteralPath $manifestPath
        Set-FixtureRelease
        '{"id":"example-component","version":"1.2.3"}' | Set-Content -LiteralPath $manifestPath
        & git -C $reference add --all
        & git -C $reference -c commit.gpgsign=false commit --quiet -m 'Replacement manifest'
        $replacement = (& git -C $reference rev-parse HEAD).Trim()
        & git -C $reference replace $accept.ExpectedCommit $replacement
        { & $script:tool @accept } | Should -Throw '*manifest version*'
        $global:ReleaseAcceptanceCalls.Count | Should -Be 0
    }

    It 'rejects invalid expected identity <Field>: <Value> before any GitHub access' -ForEach @(
        @{ Field = 'ExpectedRepository'; Value = 'example/azd-reference' },
        @{ Field = 'ExpectedRepository'; Value = 'nathanmcnulty/other-repository' },
        @{ Field = 'ExpectedRepository'; Value = 'NathanMcNulty/azd-reference' },
        @{ Field = 'ExpectedRepository'; Value = 'https://github.com/nathanmcnulty/azd-reference' },
        @{ Field = 'ExpectedTag'; Value = 'refs/tags/component/example-component/v1.2.3' },
        @{ Field = 'ExpectedTag'; Value = 'component/example-component/v01.2.3' },
        @{ Field = 'ExpectedTag'; Value = 'component/example-component/v1.2.3-01' },
        @{ Field = 'ExpectedTag'; Value = 'component/example-component/v1.2.3-rc..1' },
        @{ Field = 'ExpectedTag'; Value = 'component/example-component/v1.2.3+extra' },
        @{ Field = 'ExpectedTag'; Value = 'component/../v1.2.3' },
        @{ Field = 'ExpectedTag'; Value = "component/example-component/v1.2.3`n" },
        @{ Field = 'ExpectedTag'; Value = '--all' },
        @{ Field = 'ExpectedCommit'; Value = ('a' * 39) },
        @{ Field = 'ExpectedCommit'; Value = ('A' * 40) },
        @{ Field = 'ExpectedCommit'; Value = 'HEAD' },
        @{ Field = 'AcceptComponentRelease'; Value = $false }
    ) {
        $accept[$Field] = $Value
        { & $script:tool @accept } | Should -Throw
        $global:ReleaseAcceptanceCalls.Count | Should -Be 0
    }

    It 'rejects an alternate GitHub host before any GitHub access' {
        $env:GH_HOST = 'github.example.invalid'
        { & $script:tool @accept } | Should -Throw '*GH_HOST*'
        $global:ReleaseAcceptanceCalls.Count | Should -Be 0
    }

    It 'requires an available supplied bundle file' -ForEach @('missing', 'directory') {
        $accept.BundlePath = if ($_ -eq 'missing') { Join-Path $TestDrive 'unavailable-bundle.tar.gz' } else { $reference }
        { & $script:tool @accept } | Should -Throw '*bundle is unavailable*'
        $global:ReleaseAcceptanceCalls.Count | Should -Be 0
    }

    It 'rejects missing and lightweight local tags' -ForEach @('missing', 'lightweight') {
        & git -C $reference tag -d $accept.ExpectedTag | Out-Null
        if ($_ -eq 'lightweight') { & git -C $reference -c tag.gpgsign=false tag $accept.ExpectedTag }
        { & $script:tool @accept } | Should -Throw '*Local release evidence*'
        $global:ReleaseAcceptanceCalls.Count | Should -Be 0
    }

    It 'rejects a local tag pointing to a different reviewed commit' {
        $accept.ExpectedCommit = 'a' * 40
        { & $script:tool @accept } | Should -Throw '*local annotated tag*'
        $global:ReleaseAcceptanceCalls.Count | Should -Be 0
    }

    It 'rejects mismatched, missing, duplicate and malformed tagged manifests' -ForEach @('version', 'id', 'duplicate', 'malformed', 'array', 'version-array') {
        switch ($_) {
            'version' { '{"id":"example-component","version":"2.0.0"}' | Set-Content $manifestPath }
            'id' { '{"id":"other-component","version":"1.2.3"}' | Set-Content $manifestPath }
            'duplicate' {
                New-Item -ItemType Directory (Join-Path $reference 'components/duplicate') | Out-Null
                Copy-Item $manifestPath (Join-Path $reference 'components/duplicate/component.json')
            }
            'malformed' { 'not-json' | Set-Content $manifestPath }
            'array' { '[{"id":"example-component","version":"1.2.3"}]' | Set-Content $manifestPath }
            'version-array' { '{"id":"example-component","version":["1.2.3"]}' | Set-Content $manifestPath }
        }
        Set-FixtureRelease
        { & $script:tool @accept } | Should -Throw
        $global:ReleaseAcceptanceCalls.Count | Should -Be 0
    }

    It 'rejects malformed or unavailable remote evidence at <Endpoint>: <Evidence>' -ForEach @(
        @{ Endpoint = 'ref'; Evidence = 'not-json' },
        @{ Endpoint = 'ref'; Evidence = 'null' },
        @{ Endpoint = 'ref'; Evidence = '[]' },
        @{ Endpoint = 'ref'; Evidence = '[{}]' },
        @{ Endpoint = 'ref'; Evidence = '{}' },
        @{ Endpoint = 'ref'; Evidence = '' },
        @{ Endpoint = 'tag'; Evidence = 'not-json' },
        @{ Endpoint = 'tag'; Evidence = 'null' },
        @{ Endpoint = 'tag'; Evidence = '[]' },
        @{ Endpoint = 'tag'; Evidence = '[{}]' },
        @{ Endpoint = 'tag'; Evidence = '{}' },
        @{ Endpoint = 'tag'; Evidence = '' }
    ) {
        if ($Endpoint -eq 'ref') { $global:ReleaseAcceptanceRefRaw = $Evidence }
        else { $global:ReleaseAcceptanceTagRaw = $Evidence }
        { & $script:tool @accept } | Should -Throw
        @($global:ReleaseAcceptanceCalls | Where-Object { $_[0] -eq 'attestation' }).Count | Should -Be 0
    }

    It 'fails when the GitHub API is unavailable even with plausible output' {
        $global:ReleaseAcceptanceApiExit = 1
        { & $script:tool @accept } | Should -Throw '*GitHub release evidence is unavailable*'
        $global:ReleaseAcceptanceCalls.Count | Should -Be 1
    }

    It 'rejects a remote reference with <_>' -ForEach @('wrong-ref', 'ref-array', 'lightweight', 'different-tag-object', 'object-array') {
        switch ($_) {
            'wrong-ref' { $global:ReleaseAcceptanceRef.ref = 'refs/tags/component/other-component/v1.2.3' }
            'ref-array' { $global:ReleaseAcceptanceRef.ref = @($global:ReleaseAcceptanceRef.ref) }
            'lightweight' { $global:ReleaseAcceptanceRef.object.type = 'commit' }
            'different-tag-object' { $global:ReleaseAcceptanceRef.object.sha = 'b' * 40 }
            'object-array' { $global:ReleaseAcceptanceRef.object = @($global:ReleaseAcceptanceRef.object) }
        }
        { & $script:tool @accept } | Should -Throw '*remote reference*'
        $global:ReleaseAcceptanceCalls.Count | Should -Be 1
    }

    It 'rejects a signed tag object with <_>' -ForEach @(
        'wrong-object', 'wrong-name', 'name-case', 'name-array', 'nested-tag', 'wrong-commit',
        'unverified', 'string-true', 'numeric-true', 'missing-verification', 'object-array'
    ) {
        switch ($_) {
            'wrong-object' { $global:ReleaseAcceptanceTag.sha = 'c' * 40 }
            'wrong-name' { $global:ReleaseAcceptanceTag.tag = 'component/other-component/v1.2.3' }
            'name-case' { $global:ReleaseAcceptanceTag.tag = $accept.ExpectedTag.ToUpperInvariant() }
            'name-array' { $global:ReleaseAcceptanceTag.tag = @($accept.ExpectedTag) }
            'nested-tag' { $global:ReleaseAcceptanceTag.object.type = 'tag' }
            'wrong-commit' { $global:ReleaseAcceptanceTag.object.sha = 'd' * 40 }
            'unverified' { $global:ReleaseAcceptanceTag.verification.verified = $false }
            'string-true' { $global:ReleaseAcceptanceTag.verification.verified = 'true' }
            'numeric-true' { $global:ReleaseAcceptanceTag.verification.verified = 1 }
            'missing-verification' { $global:ReleaseAcceptanceTag.Remove('verification') }
            'object-array' { $global:ReleaseAcceptanceTag.object = @($global:ReleaseAcceptanceTag.object) }
        }
        { & $script:tool @accept } | Should -Throw
        $global:ReleaseAcceptanceCalls.Count | Should -Be 2
    }

    It 'fails when attestation verification fails or the CLI lacks support' -ForEach @(1, 127) {
        $global:ReleaseAcceptanceVerifyExit = $_
        { & $script:tool @accept } | Should -Throw '*attestation verification failed or is unavailable*'
        $global:ReleaseAcceptanceCalls.Count | Should -Be 3
    }

    It 'rejects a bundle changed during verification' {
        $global:ReleaseAcceptanceMutateBundle = $true
        { & $script:tool @accept } | Should -Throw '*bundle changed*'
    }

    It 'keeps the default audit entirely offline' {
        (& $script:tool -RepositoryRoot $script:repoRoot).state | Should -BeExactly 'current'
        $global:ReleaseAcceptanceCalls.Count | Should -Be 0
    }

    It 'preserves legacy local signature checking without GitHub calls' {
        $result = & $script:tool -RepositoryRoot $reference -Tag $accept.ExpectedTag
        $result.findings | Should -Contain "tagSignatureUnverified:$($accept.ExpectedTag)"
        $result.state | Should -BeExactly 'findings'
        $global:ReleaseAcceptanceCalls.Count | Should -Be 0
    }
}
