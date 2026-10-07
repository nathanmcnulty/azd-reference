param($Timer)
$null = $Timer
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../scripts/vendor/Azd.SecurityAutomation/Azd.SecurityAutomation.psm1') -Force
Invoke-HostedSecurityBundle -BundleRoot (Join-Path $PSScriptRoot '..') -ConfigurationPath (Join-Path $PSScriptRoot '../security-bundle.json') -Account $env:SECURITY_STORAGE_ACCOUNT
