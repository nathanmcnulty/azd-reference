Describe 'Maester Azure DevOps cleanup' {
  BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $cleanupPath = Join-Path $repoRoot 'components/powershell/maester-azd-hooks/Maester-PreDownCleanup.psm1'
    $cleanup = Get-Content -LiteralPath $cleanupPath -Raw
  }

  It 'reissues service-connection deletion while Azure DevOps state converges' {
    $cleanup | Should -Match '\$maxDeleteAttempts\s*=\s*6'
    $cleanup | Should -Match '\$retryDelaySeconds\s*=\s*5'
    $cleanup | Should -Match '(?s)for \(\$attempt = 1; \$attempt -le \$maxDeleteAttempts; \$attempt\+\+\).*?Invoke-AdoRest.*?-Method DELETE.*?Invoke-AdoRest.*?-Method GET'
    $cleanup | Should -Match 'Reissue DELETE'
  }

  It 'supports subscription-scoped Azure CLI access tokens' {
    $helpersPath = Join-Path $repoRoot 'components/powershell/maester-azd-hooks/Maester-SetupHelpers.psm1'
    $helpers = Get-Content -LiteralPath $helpersPath -Raw

    $helpers | Should -Match '\[string\]\$SubscriptionId'
    $helpers | Should -Match 'tokenArgs\s*\+=\s*@\(.+--subscription.+\$SubscriptionId'
  }
}
