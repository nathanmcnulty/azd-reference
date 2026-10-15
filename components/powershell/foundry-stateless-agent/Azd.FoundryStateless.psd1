@{
    RootModule = 'Azd.FoundryStateless.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'c645e3a1-4a4b-4b8c-ae40-4b246257e467'
    Author = 'Nathan McNulty'
    Description = 'Minimal versioned prompt agents with bounded stateless structured responses.'
    PowerShellVersion = '7.6'
    FunctionsToExport = @('New-AzdFoundryAgentDefinition', 'Publish-AzdFoundryAgentVersion', 'Test-AzdFoundryAgentVersion', 'Invoke-AzdFoundryStatelessResponse')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
