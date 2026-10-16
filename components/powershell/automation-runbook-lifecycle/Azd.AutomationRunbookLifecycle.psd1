@{
    RootModule = 'Azd.AutomationRunbookLifecycle.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'f3b8b07d-f9a6-4c9e-8ec7-0d7ba0661629'
    Author = 'Nathan McNulty'
    CompanyName = 'Community'
    Copyright = 'Released into the public domain under the Unlicense.'
    Description = 'Bounded existing Automation runbook runtime binding with preservation readback.'
    PowerShellVersion = '7.6'
    FunctionsToExport = @('Update-AzdAutomationRunbookRuntime')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('azd', 'AzureAutomation', 'lifecycle')
            ProjectUri = 'https://github.com/nathanmcnulty/azd-reference'
            LicenseUri = 'https://unlicense.org/'
        }
    }
}
