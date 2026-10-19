Describe 'Maester Azure DevOps cleanup' {
  BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $cleanupPath = Join-Path $repoRoot 'components/powershell/maester-azd-hooks/Maester-PreDownCleanup.psm1'
    $cleanup = Get-Content -LiteralPath $cleanupPath -Raw
  }

  It 'uses explicit ownership-aware postdown instead of name-discovered predown deletion' {
    $cleanup | Should -Match 'function Test-MaesterOwnedCleanupPreDown'
    $cleanup | Should -Match 'function Invoke-MaesterOwnedCleanupPostDown'
    $cleanup | Should -Match 'ApprovedPlanHash'
    $cleanup | Should -Not -Match 'function Remove-ResourceGroupLocks'
    $cleanup | Should -Not -Match 'Remove-WebAppEasyAuthEntraApplications'
    $cleanup | Should -Not -Match 'get-access-token.*https://graph.microsoft.com'
  }

  It 'supports subscription-scoped Azure CLI access tokens' {
    $helpersPath = Join-Path $repoRoot 'components/powershell/maester-azd-hooks/Maester-SetupHelpers.psm1'
    $helpers = Get-Content -LiteralPath $helpersPath -Raw

    $helpers | Should -Match '\[string\]\$SubscriptionId'
    $helpers | Should -Match 'tokenArgs\s*\+=\s*@\(.+--subscription.+\$SubscriptionId'
    $helpers | Should -Match '(?s)if \([^\r\n]*SubscriptionId[^\r\n]*\).*?--subscription.*?elseif \([^\r\n]*TenantId[^\r\n]*\).*?--tenant'
  }
}

Describe 'Maester Web App security group wizard validation' {
  BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $wizardPath = Join-Path $repoRoot 'components/powershell/maester-azd-hooks/Maester-UpWizard.psm1'
    Import-Module $wizardPath -Force
  }

  AfterAll {
    Remove-Module Maester-UpWizard -Force -ErrorAction SilentlyContinue
  }

  It 'rejects a <case> cached group ID before any environment value is persisted' -TestCases @(
    @{ case = 'blank'; key = 'SECURITY_GROUP_OBJECT_ID'; value = '' }
    @{ case = 'malformed'; key = 'SECURITY_GROUP_OBJECT_ID'; value = 'not-a-guid' }
    @{ case = 'nil'; key = 'SECURITY_GROUP_OBJECT_ID'; value = '00000000-0000-0000-0000-000000000000' }
    @{ case = 'malformed legacy fallback'; key = 'EASY_AUTH_SECURITY_GROUP_OBJECT_ID'; value = 'not-a-guid' }
  ) {
    param($key, $value)

    InModuleScope Maester-UpWizard -Parameters @{ cachedKey = $key; cachedGroupId = $value } {
      Mock Test-InteractiveWizard { $false }
      Mock Get-AzdEnvironmentValues {
        $values = @{
          MAESTER_SETUP_CLIENT_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
          MAESTER_SETUP_ACCOUNT = 'admin@example.com'
          INCLUDE_WEB_APP = 'true'
          INCLUDE_EXCHANGE = 'false'
          INCLUDE_TEAMS = 'false'
          INCLUDE_AZURE = 'false'
        }
        $values[$cachedKey] = $cachedGroupId
        $values
      }
      Mock Set-AzdEnvValueStrict {}

      {
        Invoke-MaesterUpWizard `
          -SolutionName automation-account `
          -SubscriptionId '11111111-1111-4111-8111-111111111111'
      } | Should -Throw '*SECURITY_GROUP_OBJECT_ID must be a non-empty GUID when INCLUDE_WEB_APP=true*INCLUDE_WEB_APP=false*'

      Should -Invoke Set-AzdEnvValueStrict -Times 0 -Exactly
    }
  }

  It 'normalizes a valid cached group ID and persists it only after validation' {
    InModuleScope Maester-UpWizard {
      Mock Test-InteractiveWizard { $false }
      Mock Get-AzdEnvironmentValues {
        @{
          MAESTER_SETUP_CLIENT_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
          MAESTER_SETUP_ACCOUNT = 'admin@example.com'
          INCLUDE_WEB_APP = 'true'
          INCLUDE_EXCHANGE = 'false'
          INCLUDE_TEAMS = 'false'
          INCLUDE_AZURE = 'false'
          SECURITY_GROUP_OBJECT_ID = '{AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE}'
        }
      }
      Mock Set-AzdEnvValueStrict {}

      Invoke-MaesterUpWizard `
        -SolutionName automation-account `
        -SubscriptionId '11111111-1111-4111-8111-111111111111'

      Should -Invoke Set-AzdEnvValueStrict -Times 1 -Exactly -ParameterFilter {
        $Name -eq 'SECURITY_GROUP_OBJECT_ID' -and $Value -ceq 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
      }
    }
  }

  It 'reprompts after an invalid interactive value and returns the normalized group ID' {
    InModuleScope Maester-UpWizard {
      $responses = [Collections.Generic.Queue[string]]::new()
      $responses.Enqueue('still-not-a-guid')
      $responses.Enqueue('{AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE}')
      Mock Read-Host { $responses.Dequeue() }
      Mock Write-Host {}

      $result = Read-SecurityGroupObjectId -CurrentValue 'invalid-cached-value' -InteractiveWizard $true

      $result | Should -BeExactly 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
      Should -Invoke Read-Host -Times 2 -Exactly
      Should -Invoke Write-Host -ParameterFilter {
        [string]$Object -match 'Microsoft Entra ID > Groups > All groups' -and
        [string]$Object -match 'choose No for Include Web App'
      }
    }
  }

  It 'keeps the disabled Web App baseline without validating, persisting, or looking up a group' {
    InModuleScope Maester-UpWizard {
      Mock Test-InteractiveWizard { $false }
      Mock Get-AzdEnvironmentValues {
        @{
          MAESTER_SETUP_CLIENT_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
          MAESTER_SETUP_ACCOUNT = 'admin@example.com'
          INCLUDE_WEB_APP = 'false'
          INCLUDE_EXCHANGE = 'false'
          INCLUDE_TEAMS = 'false'
          INCLUDE_AZURE = 'false'
          SECURITY_GROUP_OBJECT_ID = 'invalid-but-disabled'
        }
      }
      Mock Set-AzdEnvValueStrict {}
      Mock Invoke-RestMethod { throw 'A disabled Web App must not invoke Graph.' }

      {
        Invoke-MaesterUpWizard `
          -SolutionName automation-account `
          -SubscriptionId '11111111-1111-4111-8111-111111111111'
      } | Should -Not -Throw

      Should -Invoke Set-AzdEnvValueStrict -Times 0 -Exactly -ParameterFilter {
        $Name -eq 'SECURITY_GROUP_OBJECT_ID'
      }
      Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }
  }
}

Describe 'Maester assessment profile selection' {
  BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../components/powershell/maester-azd-hooks/Maester-UpWizard.psm1') -Force
  }
  AfterAll { Remove-Module Maester-UpWizard -Force -ErrorAction SilentlyContinue }

  It 'maps an interactive Full choice <answer> to <profile> without including report writes' -ForEach @(
    @{ answer = ''; profile = 'Full' }, @{ answer = 'n'; profile = 'Minimal' }
  ) {
    InModuleScope Maester-UpWizard -Parameters @{ answer = $answer; profile = $profile } {
      Mock Test-InteractiveWizard { $true }
      Mock Get-AzdEnvironmentValues { @{
        INCLUDE_WEB_APP = 'false'; INCLUDE_EXCHANGE = 'false'; INCLUDE_TEAMS = 'false'; INCLUDE_AZURE = 'false'
        MAESTER_SETUP_CLIENT_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; MAESTER_SETUP_ACCOUNT = 'admin@example.com'
      } }
      Mock Read-Host { if ($Prompt -like 'Grant the permissions needed for the full assessment?*') { return $answer }; return 'n' }
      Mock Set-AzdEnvValueStrict {}
      Invoke-MaesterUpWizard -SolutionName automation-account -SubscriptionId '11111111-1111-4111-8111-111111111111'
      Should -Invoke Read-Host -Times 1 -ParameterFilter { $Prompt -ceq 'Grant the permissions needed for the full assessment? [Y/n]' }
      Should -Invoke Set-AzdEnvValueStrict -Times 1 -ParameterFilter { $Name -ceq 'PERMISSION_PROFILE' -and $Value -ceq $profile }
      Should -Invoke Set-AzdEnvValueStrict -Times 1 -ParameterFilter { $Name -ceq 'INCLUDE_REPORT_SETTINGS_WRITE' -and $Value -ceq 'false' }
    }
  }

  It 'keeps noninteractive <stored> as <expected> without permission expansion' -ForEach @(
    @{ stored = ''; expected = 'Minimal' }, @{ stored = 'Minimal'; expected = 'Minimal' },
    @{ stored = 'Extended'; expected = 'Extended' }, @{ stored = 'Full'; expected = 'Full' }
  ) {
    InModuleScope Maester-UpWizard -Parameters @{ stored = $stored; expected = $expected } {
      Mock Test-InteractiveWizard { $false }
      Mock Get-AzdEnvironmentValues { @{
        PERMISSION_PROFILE = $stored
        MAESTER_SETUP_CLIENT_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; MAESTER_SETUP_ACCOUNT = 'admin@example.com'
      } }
      Mock Read-Host { throw 'No unattended prompts.' }
      Mock Set-AzdEnvValueStrict {}
      Invoke-MaesterUpWizard -SolutionName automation-account -SubscriptionId '11111111-1111-4111-8111-111111111111'
      Should -Invoke Set-AzdEnvValueStrict -Times 1 -ParameterFilter { $Name -ceq 'PERMISSION_PROFILE' -and $Value -ceq $expected }
      Should -Invoke Read-Host -Times 0
    }
  }

  It 'does not call the legacy Extended profile Full' {
    InModuleScope Maester-UpWizard {
      Mock Test-InteractiveWizard { $true }
      Mock Get-AzdEnvironmentValues { @{
        PERMISSION_PROFILE = 'Extended'; INCLUDE_WEB_APP = 'false'; INCLUDE_EXCHANGE = 'false'; INCLUDE_TEAMS = 'false'; INCLUDE_AZURE = 'false'
        MAESTER_SETUP_CLIENT_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; MAESTER_SETUP_ACCOUNT = 'admin@example.com'
      } }
      Mock Read-Host { 'n' }
      Mock Set-AzdEnvValueStrict {}
      Mock Write-Host {}
      Invoke-MaesterUpWizard -SolutionName automation-account -SubscriptionId '11111111-1111-4111-8111-111111111111'
      Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like 'Extended is the legacy permission set.*' }
      Should -Invoke Set-AzdEnvValueStrict -Times 1 -ParameterFilter { $Name -ceq 'PERMISSION_PROFILE' -and $Value -ceq 'Minimal' }
    }
  }

  It 'rejects missing or default setup-client identity before persistence' -ForEach @(
    @{ client = ''; account = 'admin@example.com' },
    @{ client = '14d82eec-204b-4c2f-b7e8-296a70dab67e'; account = 'admin@example.com' },
    @{ client = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; account = '' }
  ) {
    InModuleScope Maester-UpWizard -Parameters @{ client = $client; account = $account } {
      Mock Test-InteractiveWizard { $false }
      Mock Get-AzdEnvironmentValues { @{ MAESTER_SETUP_CLIENT_ID = $client; MAESTER_SETUP_ACCOUNT = $account } }
      Mock Set-AzdEnvValueStrict {}
      { Invoke-MaesterUpWizard -SolutionName automation-account -SubscriptionId '11111111-1111-4111-8111-111111111111' } | Should -Throw
      Should -Invoke Set-AzdEnvValueStrict -Times 0
    }
  }
  It 'keeps the requested interactive Full default Yes even when upgrading a stored Minimal profile' {
    InModuleScope Maester-UpWizard {
      Mock Test-InteractiveWizard { $true }
      Mock Get-AzdEnvironmentValues { @{
        PERMISSION_PROFILE = 'Minimal'; INCLUDE_WEB_APP = 'false'; INCLUDE_EXCHANGE = 'false'; INCLUDE_TEAMS = 'false'; INCLUDE_AZURE = 'false'
        MAESTER_SETUP_CLIENT_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; MAESTER_SETUP_ACCOUNT = 'admin@example.com'
      } }
      Mock Read-Host { if ($Prompt -like 'Grant the permissions needed for the full assessment?*') { return '' }; return 'n' }
      Mock Set-AzdEnvValueStrict {}
      Invoke-MaesterUpWizard -SolutionName automation-account -SubscriptionId '11111111-1111-4111-8111-111111111111'
      Should -Invoke Read-Host -Times 1 -ParameterFilter { $Prompt -ceq 'Grant the permissions needed for the full assessment? [Y/n]' }
      Should -Invoke Set-AzdEnvValueStrict -Times 1 -ParameterFilter { $Name -ceq 'PERMISSION_PROFILE' -and $Value -ceq 'Full' }
    }
  }

}
