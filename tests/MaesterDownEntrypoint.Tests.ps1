BeforeAll {
  $script:repoRoot=Split-Path $PSScriptRoot -Parent
  $script:fixture=Join-Path $PSScriptRoot 'fixtures/maester-down-subprocess.ps1'
  function Invoke-DownChild {
    param([string]$Scenario,[string]$SolutionName='automation-account',[string]$Ci='',[string]$Noninteractive='')
    $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh'))
    $info.UseShellExecute=$false; $info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $info.Environment['CI']=$Ci; $info.Environment['AZD_NON_INTERACTIVE']=$Noninteractive
    foreach($argument in @('-NoProfile','-File',$script:fixture,'-RepositoryRoot',$script:repoRoot,'-ProjectRoot',$root,'-Scenario',$Scenario,'-SolutionName',$SolutionName)){ $info.ArgumentList.Add($argument) }
    $process=[Diagnostics.Process]::Start($info)
    try {
      $process.StandardInput.Close()
      $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
      if(-not $process.WaitForExit(30000)){throw 'The offline down-hook subprocess timed out.'}
      $output=$stdout.GetAwaiter().GetResult(); $errors=$stderr.GetAwaiter().GetResult()
      if($process.ExitCode -ne 0){throw "The subprocess fixture failed: $errors $output"}
      $line=@($output -split '\r?\n' | Where-Object { $_.StartsWith('{') })[-1]
      return $line | ConvertFrom-Json -Depth 16
    } finally {if(-not $process.HasExited){$process.Kill($true)};$process.Dispose()}
  }
}

Describe 'Actual canonical down entrypoint in a fresh PowerShell process' {
  It 'rejects unavailable interactive cleanup before an approved unlock for <SolutionName>' -ForEach @(
    @{SolutionName='automation-account'},@{SolutionName='function-app'},@{SolutionName='container-app-job'},@{SolutionName='azure-devops'}
  ) {
    $result=Invoke-DownChild PreInteractive -SolutionName $SolutionName
    $result.InputRedirected | Should -BeTrue
    $result.CiSelected | Should -BeFalse
    $result.NoninteractiveSelected | Should -BeFalse
    $result.Success | Should -BeFalse
    $result.Message | Should -BeLike '*Down stopped before changing owned locks or Azure resources*parent Process session is not transferred*'
    $result.LockDeletes | Should -Be 0
    $result.GraphDeletes | Should -Be 0
    $result.Connections.Count | Should -Be 0
    $result.JournalUnchanged | Should -BeTrue
  }

  It 'also rejects the interactive contract when no locks remain' {
    $result=Invoke-DownChild PreInteractiveUnlocked
    $result.Success | Should -BeFalse
    $result.Message | Should -BeLike '*remaining ownership records*this process cannot prompt*'
    $result.LockDeletes | Should -Be 0
    $result.JournalUnchanged | Should -BeTrue
  }

  It 'retains the explicit policy input <InputName> without inventing a CLI-exported flag' -ForEach @(
    @{InputName='CI';Ci='true';Noninteractive=''},@{InputName='AZD_NON_INTERACTIVE';Ci='';Noninteractive='true'}
  ) {
    $result=Invoke-DownChild PreInteractive -Ci $Ci -Noninteractive $Noninteractive
    $result.Success | Should -BeFalse
    $result.Message | Should -BeLike '*Down stopped before changing owned locks or Azure resources*'
    $result.LockDeletes | Should -Be 0
  }

  It 'allows <Scenario> without starting Graph authentication or changing journal records' -ForEach @(
    @{Scenario='PrePlan'},@{Scenario='PreNoJournal'},@{Scenario='PreDeleted'},@{Scenario='PreEmpty'}
  ) {
    $result=Invoke-DownChild $Scenario
    $result.Success | Should -BeTrue
    $result.LockDeletes | Should -Be 0
    $result.GraphDeletes | Should -Be 0
    $result.Connections.Count | Should -Be 0
    $result.JournalUnchanged | Should -BeTrue
  }

  It 'preserves explicit noninteractive predown unlock approval' {
    $result=Invoke-DownChild PreExplicitHash -Ci true -Noninteractive true
    $result.Success | Should -BeTrue
    $result.LockDeletes | Should -Be 1
    $result.GraphDeletes | Should -Be 0
    $result.Connections.Count | Should -Be 0
    $result.JournalUnchanged | Should -BeTrue
  }

  It 'selects one fresh Process login inside the child for <SolutionName> using the existing exact scope union' -ForEach @(
    @{SolutionName='automation-account'},@{SolutionName='function-app'},@{SolutionName='container-app-job'},@{SolutionName='azure-devops'}
  ) {
    $result=Invoke-DownChild PostFreshLogin -SolutionName $SolutionName
    $result.Success | Should -BeTrue
    $result.InitialContextAbsent | Should -BeTrue
    $result.Connections.Count | Should -Be 1
    $connection=$result.Connections[0]
    $connection.ContextScope | Should -BeExactly 'Process'
    $connection.TenantId | Should -BeExactly '11111111-1111-4111-8111-111111111111'
    $connection.ClientId | Should -BeExactly '33333333-3333-4333-8333-333333333333'
    @($connection.Scopes | Sort-Object) | Should -Be @('Application.Read.All','AppRoleAssignment.ReadWrite.All','Directory.Read.All')
    $connection.Parameters | Should -Not -Contain 'UseDeviceAuthentication'
    $connection.Parameters | Should -Not -Contain 'AccessToken'
    $result.Entries[0].action | Should -BeExactly 'AlreadyAbsent'
    $result.GraphDeletes | Should -Be 0
    $result.JournalUnchanged | Should -BeTrue
  }

  It 'fails closed without child authentication and points recovery through the canonical entrypoint' {
    $result=Invoke-DownChild PostMissingContext
    $result.Success | Should -BeFalse
    $result.InitialContextAbsent | Should -BeTrue
    $result.Message | Should -BeLike '*external cleanup is incomplete*fresh normal-browser sign-in*Invoke-MaesterDown.ps1* -Phase PostDown *-EnvironmentName ''down-child''*-SolutionName ''automation-account''*-InteractiveConsent*'
    $result.Message | Should -Not -BeLike '*retrying: Invoke-MaesterOwnedCleanupPostDown*'
    $result.Connections.Count | Should -Be 0
    $result.GraphDeletes | Should -Be 0
    $result.JournalUnchanged | Should -BeTrue
  }

  It 'provides the same usable recovery when the actual interactive postdown hook cannot prompt' {
    $result=Invoke-DownChild PostInteractiveUnavailable
    $result.Success | Should -BeFalse
    $result.Message | Should -BeLike '*Azure has been removed*external cleanup is incomplete*ownership journal is retained*Interactive teardown login is unavailable*Invoke-MaesterDown.ps1* -Phase PostDown *-EnvironmentName ''down-child''*-SolutionName ''automation-account''*-InteractiveConsent*'
    $result.Connections.Count | Should -Be 0
    $result.GraphDeletes | Should -Be 0
    $result.JournalUnchanged | Should -BeTrue
  }

  It 'preserves an existing verified Process context for an explicit noninteractive preview' {
    $result=Invoke-DownChild PostExistingContext -Ci true -Noninteractive true
    $result.Success | Should -BeTrue
    $result.InitialContextAbsent | Should -BeFalse
    $result.Connections.Count | Should -Be 0
    $result.Entries[0].action | Should -BeExactly 'AlreadyAbsent'
    $result.JournalUnchanged | Should -BeTrue
  }

  It 'preserves direct preauthorized noninteractive cleanup and exact absence checkpointing' {
    $result=Invoke-DownChild PostModuleExisting -Ci true -Noninteractive true
    $result.Success | Should -BeTrue
    $result.Completed | Should -BeTrue
    $result.Connections.Count | Should -Be 0
    $result.GraphDeletes | Should -Be 0
    $result.States | Should -Be @('deleted')
  }

  It 'completes a terminal journal without unnecessary login or approval prompts' {
    $result=Invoke-DownChild PostTerminal -Ci true -Noninteractive true
    $result.Success | Should -BeTrue
    $result.Completed | Should -BeTrue
    $result.Connections.Count | Should -Be 0
    $result.GraphDeletes | Should -Be 0
    $result.JournalUnchanged | Should -BeTrue
  }
}
