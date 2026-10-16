BeforeAll {
    $workflowRoot = Split-Path $PSScriptRoot -Parent
    $workflow = Get-Content (Join-Path $workflowRoot '.github/workflows/portfolio-updates.yml') -Raw

    function Get-PortfolioWorkflowJob {
        param([string] $Name)
        $match = [regex]::Match($workflow, "(?ms)^  ${Name}:\r?\n.*?(?=^  [a-z-]+:|\z)")
        if (-not $match.Success) { throw "Missing workflow job: $Name" }
        $match.Value
    }

    function Get-PortfolioWorkflowStep {
        param([string] $Job, [string] $Name)
        $pattern = '(?ms)^      - name: ' + [regex]::Escape($Name) + '\r?\n.*?(?=^      - name:|\z)'
        $match = [regex]::Match((Get-PortfolioWorkflowJob $Job), $pattern)
        if (-not $match.Success) { throw "Missing workflow step: $Job / $Name" }
        $match.Value
    }

    $steps = @{
        acquire = Get-PortfolioWorkflowStep prepare 'Acquire and verify the exact component release bundle'
        prepare = Get-PortfolioWorkflowStep prepare 'Prepare and validate locally without a write credential'
        package = Get-PortfolioWorkflowStep prepare 'Package only the validated Git branch'
        restore = Get-PortfolioWorkflowStep publish 'Restore the exact validated branch'
        recheck = Get-PortfolioWorkflowStep publish 'Recheck publication scope and release before App authentication'
        publish = Get-PortfolioWorkflowStep publish 'Publish the exact prevalidated branch as a draft pull request'
    }

    function Invoke-PortfolioReleaseWorkflowFixture {
        param(
            [ValidateSet('Environment', 'Prepare', 'Publish', 'RoundTrip')] [string] $Phase = 'Publish',
            [string] $Case = 'valid',
            [string] $Field = '',
            [string] $SolutionRoot = '.'
        )

        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        foreach ($step in $steps.GetEnumerator()) {
            $match = [regex]::Match($step.Value, '(?s)        run: \|\r?\n(?<code>.*)')
            if (-not $match.Success) { throw "Missing PowerShell block: $($step.Key)" }
            $code = $match.Groups['code'].Value -replace '(?m)^          ', ''
            Set-Content (Join-Path $root "$($step.Key).ps1") $code -Encoding utf8NoBOM
        }
        Copy-Item (Join-Path $workflowRoot 'schemas/azd-components-lock.schema.json') (Join-Path $root 'lock.schema.json')
        @{ Phase = $Phase; Case = $Case; Field = $Field; SolutionRoot = $SolutionRoot } |
            ConvertTo-Json | Set-Content (Join-Path $root 'case.json') -Encoding utf8NoBOM

        # Only the workflow blocks execute production code. Dependency stubs record
        # bindings and fail closed; Git uses disposable local repositories only.
        $fixture = @'
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$case = Get-Content ./case.json -Raw | ConvertFrom-Json
if ($case.Phase -eq 'Environment') {
    $gitCommand = Get-Command git -CommandType Application -ErrorAction Stop
    $gitVersion = & git --version
    if ($LASTEXITCODE -ne 0) { throw 'Git could not execute in the isolated fixture environment.' }
    @{ GitPath = $gitCommand.Source; GitVersion = [string]$gitVersion; PathExt = $env:PATHEXT } |
        ConvertTo-Json | Set-Content ./environment.json -Encoding utf8NoBOM
    exit 0
}
$env:FIXTURE_ROOT = $PSScriptRoot
$env:FIXTURE_CASE = $case.Case
$env:RUNNER_TEMP = Join-Path $PSScriptRoot 'runner'
$reference = Join-Path $PSScriptRoot 'portfolio/azd-reference'
$consumer = Join-Path $PSScriptRoot 'portfolio/consumer-one'
$tooling = Join-Path $reference 'tooling'
$download = Join-Path $env:RUNNER_TEMP 'prepared-branch'
New-Item -ItemType Directory -Path $tooling, "$reference/portfolio", "$reference/schemas", $consumer, $download, ./empty-hooks -Force | Out-Null
Copy-Item ./lock.schema.json "$reference/schemas/azd-components-lock.schema.json"
$env:TARGET_COMPONENT = 'fixture-component'
$env:TARGET_VERSION = '1.2.3'
$env:TARGET_DIRECTORY = 'consumer-one'
$env:TARGET_CONSUMER = 'consumer-one'
$env:TARGET_BRANCH = 'component-updates/fixture-component-v1.2.3'
$env:SELECTED_CONSUMER = 'consumer-one'
$env:PLAN_ONLY = 'false'
$env:CANDIDATE_JSON = '{"consumer":"consumer-one"}'
$env:GH_TOKEN = 'fixture-read-token'
$env:GITHUB_TOKEN = 'fixture-read-token'

function Invoke-FixtureGit {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git command failed: $args" }
}
foreach ($repository in $reference, $consumer) {
    Invoke-FixtureGit -C $repository init --quiet --initial-branch=main
    Invoke-FixtureGit -C $repository config user.name 'offline workflow fixture'
    Invoke-FixtureGit -C $repository config user.email 'fixture@example.invalid'
    Invoke-FixtureGit -C $repository config commit.gpgsign false
    Invoke-FixtureGit -C $repository config tag.gpgsign false
    Invoke-FixtureGit -C $repository config core.hooksPath "$PSScriptRoot/empty-hooks"
    'base fixture' | Set-Content "$repository/README.md"
    Invoke-FixtureGit -C $repository add README.md
    Invoke-FixtureGit -C $repository commit --quiet -m 'Fixture base'
}
Invoke-FixtureGit -C $reference tag -a 'component/fixture-component/v1.2.3' -m 'Fixture release'
$trustedRevision = [string](Invoke-FixtureGit -C $reference rev-parse HEAD)
$trustedRevision | Set-Content ./trusted-revision.txt
'Later default branch content' | Set-Content "$reference/README.md"
Invoke-FixtureGit -C $reference commit --quiet -am 'Fixture later main'
$laterRevision = [string](Invoke-FixtureGit -C $reference rev-parse HEAD)
$laterRevision | Set-Content ./later-revision.txt
$env:FIXTURE_REVISION = $trustedRevision
$env:FIXTURE_LATER_REVISION = $laterRevision
@{ consumers = @(@{ id = 'consumer-one'; solutionRoot = $case.SolutionRoot }) } |
    ConvertTo-Json -Depth 10 | Set-Content "$reference/portfolio/consumers.json"

$entry = [ordered]@{
    id = 'fixture-component'; version = '1.2.3'
    sourceRepository = 'https://github.com/nathanmcnulty/azd-reference'
    sourceRevision = $trustedRevision
    files = @(@{ source = 'source.ps1'; target = 'target.ps1'; sha256 = ('a' * 64) })
}
if ($case.Case -eq 'scalar-mismatch') {
    $entry[$case.Field] = switch ($case.Field) {
        sourceRevision { $laterRevision }
        version { '9.9.9' }
        sourceRepository { 'https://github.com/example/untrusted-reference' }
    }
}
if ($case.Case -eq 'array-value') { $entry[$case.Field] = @($entry[$case.Field]) }
if ($case.Case -eq 'mixed-array-value') { $entry[$case.Field] = @($entry[$case.Field], 'untrusted') }
$entries = @($entry)
if ($case.Case -eq 'duplicate-component') { $entries += $entry }
if ($case.Case -eq 'missing-component') { $entry.id = 'other-component' }
$lock = @{ manifestVersion = '1.0'; components = $entries }
$lockDirectory = if ($case.SolutionRoot -eq '.') { $consumer } else { Join-Path $consumer $case.SolutionRoot }
New-Item -ItemType Directory -Path $lockDirectory -Force | Out-Null
Invoke-FixtureGit -C $consumer checkout --quiet -b $env:TARGET_BRANCH
$lock | ConvertTo-Json -Depth 20 | Set-Content "$lockDirectory/azd-components.lock.json"
Invoke-FixtureGit -C $consumer add --all
Invoke-FixtureGit -C $consumer commit --quiet -m 'Fixture prepared component lock'
Invoke-FixtureGit -C $consumer checkout --quiet main
if ($case.Case -eq 'missing-tag') { Invoke-FixtureGit -C $reference tag --delete 'component/fixture-component/v1.2.3' | Out-Null }

@STUB@
[CmdletBinding()]
param([string] $ExpectedRepository, [string] $ExpectedTag, [string] $ExpectedCommit, [string] $DestinationPath)
@{ action = 'acquire'; repository = $ExpectedRepository; tag = $ExpectedTag; revision = $ExpectedCommit; bundle = $DestinationPath; token = $env:GH_TOKEN } |
    ConvertTo-Json -Compress | Add-Content "$env:FIXTURE_ROOT/calls.jsonl"
if ($env:FIXTURE_CASE -eq 'acquisition-failure') { throw 'Fixture acquisition failed.' }
if ($ExpectedCommit -cne $env:FIXTURE_REVISION) { throw 'Acquisition received an untrusted revision.' }
'original fixture release bundle' | Set-Content -LiteralPath $DestinationPath -Encoding utf8NoBOM
# Returned metadata must not become the trusted workflow revision.
[pscustomobject]@{ revision = $env:FIXTURE_LATER_REVISION; sourceRevision = $env:FIXTURE_LATER_REVISION }
@ENDSTUB@ | Set-Content "$tooling/Get-AzdComponentReleaseBundle.ps1"

@STUB@
[CmdletBinding()]
param([switch] $AcceptComponentRelease, [string] $RepositoryRoot, [string] $ExpectedRepository, [string] $ExpectedTag, [string] $ExpectedCommit, [string] $BundlePath)
@{ action = 'accept'; repository = $ExpectedRepository; tag = $ExpectedTag; revision = $ExpectedCommit; bundle = $BundlePath; token = $env:GH_TOKEN; acceptComponentRelease = [bool]$AcceptComponentRelease } |
    ConvertTo-Json -Compress | Add-Content "$env:FIXTURE_ROOT/calls.jsonl"
if ($env:FIXTURE_CASE -in @('acceptance-failure', 'bad-attestation')) { throw 'Fixture attestation rejected.' }
if (-not (Test-Path -LiteralPath $BundlePath -PathType Leaf)) { throw 'Fixture release bundle is missing.' }
if ($ExpectedCommit -cne $env:FIXTURE_REVISION) { throw 'Acceptance received an untrusted revision.' }
if ((Get-Content -LiteralPath $BundlePath -Raw).Trim() -cne 'original fixture release bundle') { throw 'The transferred release bundle changed.' }
'accepted' | Set-Content "$env:FIXTURE_ROOT/accepted.txt"
[pscustomobject]@{ revision = $env:FIXTURE_LATER_REVISION; sourceRevision = $env:FIXTURE_LATER_REVISION }
@ENDSTUB@ | Set-Content "$tooling/Test-AzdReleaseIntegrity.ps1"

@STUB@
[CmdletBinding(SupportsShouldProcess)]
param([string] $Component, [string] $Version, [string] $ConsumerId, [string] $PortfolioRoot, [string] $WorktreeRoot, [string] $Operation, [string] $ExpectedRevision)
if (-not (Test-Path "$env:FIXTURE_ROOT/accepted.txt")) { throw 'Preparation ran before release acceptance.' }
@{ action = 'prepare'; revision = $ExpectedRevision; operation = $Operation; token = $env:GH_TOKEN } |
    ConvertTo-Json -Compress | Add-Content "$env:FIXTURE_ROOT/calls.jsonl"
@{ action = 'consumer-validation'; revision = $ExpectedRevision } |
    ConvertTo-Json -Compress | Add-Content "$env:FIXTURE_ROOT/calls.jsonl"
@ENDSTUB@ | Set-Content "$tooling/Update-AzdPortfolio.ps1"

@STUB@
[CmdletBinding()]
param([string] $CandidateJson, [string] $ConsumerId, [switch] $PlanOnly, [switch] $ForPublication)
@{ action = 'scope' } | ConvertTo-Json -Compress | Add-Content "$env:FIXTURE_ROOT/calls.jsonl"
@ENDSTUB@ | Set-Content "$tooling/Assert-AzdPortfolioUpdateScope.ps1"

@STUB@
[CmdletBinding(SupportsShouldProcess)]
param([string] $Component, [string] $Version, [string] $ConsumerId, [string] $PortfolioRoot, [string] $WorktreeRoot, [switch] $PreparedBranchesOnly, [string] $ExpectedRevision, [string] $ReleaseBundlePath)
@{ action = 'publish'; revision = $ExpectedRevision; bundle = $ReleaseBundlePath; readToken = $env:AZD_RELEASE_READ_TOKEN; token = $env:GH_TOKEN; preparedBranchesOnly = [bool]$PreparedBranchesOnly } |
    ConvertTo-Json -Compress | Add-Content "$env:FIXTURE_ROOT/calls.jsonl"
@ENDSTUB@ | Set-Content "$tooling/Publish-AzdPortfolioUpdates.ps1"

if ($case.Phase -in @('Prepare', 'RoundTrip')) {
    $env:GITHUB_OUTPUT = "$PSScriptRoot/prepare.outputs"
    & ./acquire.ps1
    $env:EXPECTED_REVISION = (Get-Content $env:GITHUB_OUTPUT) -replace '^revision=', ''
    $env:GH_TOKEN = ''
    & ./prepare.ps1
    & ./package.ps1
    if ($case.Phase -eq 'Prepare') { exit 0 }
    Copy-Item "$env:RUNNER_TEMP/prepared-branch.bundle" "$download/prepared-branch.bundle"
    Copy-Item "$env:RUNNER_TEMP/component-release.tar.gz" "$download/component-release.tar.gz"
}
else {
    Invoke-FixtureGit -C $consumer bundle create "$download/prepared-branch.bundle" "refs/heads/$env:TARGET_BRANCH"
    if ($case.Case -ne 'missing-bundle') { 'original fixture release bundle' | Set-Content "$download/component-release.tar.gz" -Encoding utf8NoBOM }
}
Invoke-FixtureGit -C $consumer branch --delete --force $env:TARGET_BRANCH | Out-Null
& ./restore.ps1
$env:GITHUB_OUTPUT = "$PSScriptRoot/publish.outputs"
$env:GH_TOKEN = 'fixture-read-token'
& ./recheck.ps1
# Model the next step only after the actual pre-App block succeeds.
'app-token-step-reached' | Set-Content ./app-token-reached.txt
$env:EXPECTED_REVISION = (Get-Content $env:GITHUB_OUTPUT) -replace '^revision=', ''
$env:GH_TOKEN = 'fixture-app-token'
$env:AZD_RELEASE_READ_TOKEN = 'fixture-read-token'
function gh {
    if (($args -join ' ') -cne 'auth setup-git') { throw "Unexpected fixture gh request: $args" }
    @{ action = 'setup-git'; token = $env:GH_TOKEN } | ConvertTo-Json -Compress | Add-Content "$env:FIXTURE_ROOT/calls.jsonl"
}
& ./publish.ps1
'@
        Set-Content (Join-Path $root 'fixture.ps1') ($fixture.Replace('@STUB@', "@'").Replace('@ENDSTUB@', "'@")) -Encoding utf8NoBOM
        $start = [System.Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })))
        foreach ($argument in '-NoLogo', '-NoProfile', '-NonInteractive', '-File', (Join-Path $root 'fixture.ps1')) { $start.ArgumentList.Add($argument) }
        $start.WorkingDirectory = $root
        # Do not inherit authentication, Git overrides, profiles, or global config.
        # PowerShell on Windows needs PATHEXT to resolve extensionless Git commands.
        $start.Environment.Clear()
        foreach ($name in 'PATH', 'PATHEXT', 'SystemRoot', 'PSModulePath') {
            $value = [Environment]::GetEnvironmentVariable($name)
            if ($value) { $start.Environment[$name] = $value }
        }
        $start.Environment['HOME'] = $root
        $start.Environment['USERPROFILE'] = $root
        $start.Environment['TEMP'] = $root
        $start.Environment['TMP'] = $root
        $start.Environment['GIT_CONFIG_NOSYSTEM'] = '1'
        $start.Environment['GIT_CONFIG_GLOBAL'] = Join-Path $root 'empty-git-config'
        $start.Environment['GIT_ALLOW_PROTOCOL'] = 'file'
        $start.Environment['GIT_TERMINAL_PROMPT'] = '0'
        $start.Environment['POWERSHELL_TELEMETRY_OPTOUT'] = '1'
        $start.Environment['DOTNET_CLI_TELEMETRY_OPTOUT'] = '1'
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($start)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $callsPath = Join-Path $root 'calls.jsonl'
            [pscustomobject]@{
                ExitCode = $process.ExitCode
                Output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
                Root = $root
                Calls = @(if (Test-Path $callsPath) { Get-Content $callsPath | ConvertFrom-Json })
            }
        }
        finally { $process.Dispose() }
    }
}

Describe 'Portfolio release workflow trust boundaries' {
    It 'grants artifact lookup actions read only to Prepare' {
        $workflow | Should -Match '(?m)^permissions:\r?\n  contents: read\r?$'
        @([regex]::Matches($workflow, '(?m)^\s+actions: read\s*$')).Count | Should -Be 1
        (Get-PortfolioWorkflowJob prepare) | Should -Match '(?m)^    permissions:\r?\n      contents: read\r?\n      actions: read\r?$'
        foreach ($job in 'discover', 'publish', 'configuration-required') {
            (Get-PortfolioWorkflowJob $job) | Should -Not -Match '(?m)^\s+actions:'
        }
        $workflow | Should -Not -Match '(?m)^\s+(contents|actions): write\s*$'
    }

    It 'accepts the acquired release before preparing or validating consumer code' {
        $prepare = Get-PortfolioWorkflowJob prepare
        $prepare.IndexOf('Acquire and verify the exact component release bundle') | Should -BeLessThan $prepare.IndexOf('Prepare and validate locally without a write credential')
        $prepare.IndexOf('Prepare and validate locally without a write credential') | Should -BeLessThan $prepare.IndexOf('Package only the validated Git branch')
        $steps.acquire.IndexOf('Get-AzdComponentReleaseBundle.ps1') | Should -BeLessThan $steps.acquire.IndexOf('Test-AzdReleaseIntegrity.ps1')
        $steps.acquire.IndexOf('Test-AzdReleaseIntegrity.ps1') | Should -BeLessThan $steps.acquire.IndexOf('"revision=')
        $steps.prepare | Should -Match 'EXPECTED_REVISION: \$\{\{ steps\.release\.outputs\.revision \}\}'
        $steps.prepare | Should -Match '-ExpectedRevision \$env:EXPECTED_REVISION'
        $steps.acquire | Should -Match 'GH_TOKEN: \$\{\{ github\.token \}\}'
        $prepare | Should -Not -Match 'create-github-app-token|secrets\.'
    }

    It 'downloads only the matching artifact from the current workflow run' {
        $download = Get-PortfolioWorkflowStep publish 'Download the branch validated on the credential-free runner'
        $download | Should -Match 'uses: actions/download-artifact@[0-9a-f]{40}'
        $download | Should -Match 'name: prepared-\$\{\{ matrix.consumer \}\}-\$\{\{ matrix.component \}\}-\$\{\{ matrix.version \}\}'
        $download | Should -Match 'path: \$\{\{ runner.temp \}\}/prepared-branch'
        $download | Should -Not -Match '(?m)^\s+(repository|run-id|github-token|pattern|merge-multiple):'
    }

    It 'rechecks trusted provenance after restore and before minting an App credential' {
        $publish = Get-PortfolioWorkflowJob publish
        $publish.IndexOf('Restore the exact validated branch') | Should -BeLessThan $publish.IndexOf('Recheck publication scope and release before App authentication')
        $publish.IndexOf('Recheck publication scope and release before App authentication') | Should -BeLessThan $publish.IndexOf('actions/create-github-app-token@')
        $publish.IndexOf('actions/create-github-app-token@') | Should -BeLessThan $publish.IndexOf('Publish the exact prevalidated branch as a draft pull request')
        $steps.recheck | Should -Match 'GH_TOKEN: \$\{\{ github\.token \}\}'
        $steps.recheck | Should -Match 'git --no-replace-objects .*rev-parse .*"refs/tags/\$\{tag\}\^\{commit\}"'
        $steps.recheck | Should -Match 'Test-Json -SchemaFile'
        $steps.recheck.IndexOf('Test-AzdReleaseIntegrity.ps1') | Should -BeLessThan $steps.recheck.IndexOf('"revision=')
        $publish | Should -Not -Match 'continue-on-error:|if: always\(\)'
    }

    It 'transfers the original release bundle with the validated branch and reuses it for publication' {
        $upload = Get-PortfolioWorkflowStep prepare 'Transfer the validated branch without credentials'
        $upload | Should -Match '(?m)^            \$\{\{ runner.temp \}\}/prepared-branch.bundle\r?$'
        $upload | Should -Match '(?m)^            \$\{\{ runner.temp \}\}/component-release.tar.gz\r?$'
        $upload | Should -Match 'if-no-files-found: error'
        $steps.publish | Should -Match 'AZD_RELEASE_READ_TOKEN: \$\{\{ github.token \}\}'
        $steps.publish | Should -Match 'GH_TOKEN: \$\{\{ steps.app-token.outputs.token \}\}'
        $steps.publish | Should -Match 'EXPECTED_REVISION: \$\{\{ steps.release.outputs.revision \}\}'
        $steps.publish | Should -Match '-ExpectedRevision \$env:EXPECTED_REVISION'
        $steps.publish | Should -Match '-ReleaseBundlePath \(Join-Path \$env:RUNNER_TEMP ''prepared-branch/component-release\.tar\.gz''\)'
        $steps.publish | Should -Match '-PreparedBranchesOnly'
    }
}

Describe 'Portfolio release workflow offline execution' {
    It 'resolves and executes Git in the isolated child with native executable extensions preserved' {
        $originalPathExt = [Environment]::GetEnvironmentVariable('PATHEXT')
        $expectedPathExt = if ($originalPathExt) { $originalPathExt } else { '.COM;.EXE;.BAT;.CMD' }
        try {
            # Supply the Windows lookup variable on every host so Linux also detects
            # an accidental removal from the child-process environment allowlist.
            [Environment]::SetEnvironmentVariable('PATHEXT', $expectedPathExt)
            $result = Invoke-PortfolioReleaseWorkflowFixture -Phase Environment
            $result.ExitCode | Should -Be 0 -Because $result.Output
            $environment = Get-Content (Join-Path $result.Root 'environment.json') -Raw | ConvertFrom-Json
            $environment.PathExt | Should -BeExactly $expectedPathExt
            $environment.GitVersion | Should -Match '^git version '
            Test-Path -LiteralPath $environment.GitPath -PathType Leaf | Should -BeTrue
            if ($IsWindows) { $environment.GitPath | Should -Match '\.exe$' }
        }
        finally { [Environment]::SetEnvironmentVariable('PATHEXT', $originalPathExt) }
    }

    It 'acquires and accepts the exact trusted tag before preparation and consumer validation' {
        $result = Invoke-PortfolioReleaseWorkflowFixture -Phase Prepare
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $revision = Get-Content (Join-Path $result.Root 'trusted-revision.txt')
        Get-Content (Join-Path $result.Root 'prepare.outputs') | Should -Be "revision=$revision"
        ($result.Calls.action -join ',') | Should -Be 'acquire,accept,prepare,consumer-validation'
        foreach ($call in $result.Calls) { $call.revision | Should -Be $revision }
        foreach ($call in $result.Calls | Where-Object action -In acquire, accept) {
            $call.repository | Should -Be 'nathanmcnulty/azd-reference'
            $call.tag | Should -Be 'component/fixture-component/v1.2.3'
            $call.token | Should -Be 'fixture-read-token'
            $call.bundle | Should -Be (Join-Path $result.Root 'runner/component-release.tar.gz')
        }
        ($result.Calls | Where-Object action -EQ prepare).token | Should -BeNullOrEmpty
        ($result.Calls | Where-Object action -EQ accept).acceptComponentRelease | Should -BeTrue
    }

    It 'stops Prepare without emitting a revision or running consumer code on <Case>' -ForEach @(
        @{ Case = 'acquisition-failure'; Actions = 'acquire' }
        @{ Case = 'acceptance-failure'; Actions = 'acquire,accept' }
        @{ Case = 'missing-tag'; Actions = '' }
    ) {
        $result = Invoke-PortfolioReleaseWorkflowFixture -Phase Prepare -Case $Case
        $result.ExitCode | Should -Not -Be 0
        Test-Path (Join-Path $result.Root 'prepare.outputs') | Should -BeFalse
        ($result.Calls.action -join ',') | Should -Be $Actions
        Test-Path (Join-Path $result.Root 'runner/prepared-branch.bundle') | Should -BeFalse
    }

    It 'rejects <Case> before emitting a Publish revision or reaching App authentication' -ForEach @(
        @{ Case = 'missing-bundle' }
        @{ Case = 'bad-attestation' }
        @{ Case = 'missing-tag' }
        @{ Case = 'duplicate-component' }
        @{ Case = 'missing-component' }
    ) {
        $result = Invoke-PortfolioReleaseWorkflowFixture -Case $Case
        $result.ExitCode | Should -Not -Be 0
        Test-Path (Join-Path $result.Root 'publish.outputs') | Should -BeFalse
        Test-Path (Join-Path $result.Root 'app-token-reached.txt') | Should -BeFalse
        @($result.Calls | Where-Object action -In 'publish', 'setup-git').Count | Should -Be 0
    }

    It 'rejects prepared lock <Field> as <Case> before acceptance and App authentication' -ForEach @(
        foreach ($field in 'sourceRevision', 'version', 'sourceRepository') {
            foreach ($case in 'scalar-mismatch', 'array-value', 'mixed-array-value') {
                @{ Field = $field; Case = $case }
            }
        }
    ) {
        $result = Invoke-PortfolioReleaseWorkflowFixture -Case $Case -Field $Field
        $result.ExitCode | Should -Not -Be 0
        Test-Path (Join-Path $result.Root 'publish.outputs') | Should -BeFalse
        Test-Path (Join-Path $result.Root 'app-token-reached.txt') | Should -BeFalse
        ($result.Calls.action -join ',') | Should -Be 'scope'
        if ($Case -eq 'scalar-mismatch') { $result.Output | Should -Match 'Prepared lock provenance does not match' }
        else { $result.Output | Should -Match 'schema' }
    }

    It 'emits the trusted local tag SHA rather than HEAD or returned metadata for solution root <SolutionRoot>' -ForEach @(
        @{ SolutionRoot = '.' }
        @{ SolutionRoot = 'infra/nested' }
    ) {
        $result = Invoke-PortfolioReleaseWorkflowFixture -SolutionRoot $SolutionRoot
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $revision = Get-Content (Join-Path $result.Root 'trusted-revision.txt')
        $revision | Should -Not -Be (Get-Content (Join-Path $result.Root 'later-revision.txt'))
        Get-Content (Join-Path $result.Root 'publish.outputs') | Should -Be "revision=$revision"
        Test-Path (Join-Path $result.Root 'app-token-reached.txt') | Should -BeTrue
        $accept = $result.Calls | Where-Object action -EQ accept
        $accept.revision | Should -Be $revision
        $accept.repository | Should -Be 'nathanmcnulty/azd-reference'
        $accept.tag | Should -Be 'component/fixture-component/v1.2.3'
        $accept.token | Should -Be 'fixture-read-token'
    }

    It 'keeps the same accepted bundle and revision across preparation, branch transfer, and publication' {
        $result = Invoke-PortfolioReleaseWorkflowFixture -Phase RoundTrip
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $revision = Get-Content (Join-Path $result.Root 'trusted-revision.txt')
        Get-Content (Join-Path $result.Root 'prepare.outputs') | Should -Be "revision=$revision"
        Get-Content (Join-Path $result.Root 'publish.outputs') | Should -Be "revision=$revision"
        ($result.Calls.action -join ',') | Should -Be 'acquire,accept,prepare,consumer-validation,scope,accept,scope,setup-git,publish'
        $original = Join-Path $result.Root 'runner/component-release.tar.gz'
        $transferred = Join-Path $result.Root 'runner/prepared-branch/component-release.tar.gz'
        (Get-FileHash $original).Hash | Should -Be (Get-FileHash $transferred).Hash
        $publisher = $result.Calls | Where-Object action -EQ publish
        $publisher.revision | Should -Be $revision
        $publisher.bundle | Should -Be $transferred
        $publisher.readToken | Should -Be 'fixture-read-token'
        $publisher.token | Should -Be 'fixture-app-token'
        $publisher.preparedBranchesOnly | Should -BeTrue
    }
}
