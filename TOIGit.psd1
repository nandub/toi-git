@{
    RootModule = 'TOIGit.psm1'
    ModuleVersion = '1.0.3'
    GUID = '6bff46bc-0cc5-44bb-b711-9713a1d2099d'
    Author = 'Fernando Ortiz'
    CompanyName = 'TOI'
    Copyright = '(c) TOI'
    Description = 'PowerShell workflow assistant for modern Git with typed branches, quality gates, and GitHub-aware flows.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-Toi', 'Get-ToiVersion')
    AliasesToExport = @('toi')
    CmdletsToExport = @()
    VariablesToExport = @()
}
