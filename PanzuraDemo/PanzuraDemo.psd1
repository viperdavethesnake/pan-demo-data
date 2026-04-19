@{
  RootModule        = 'PanzuraDemo.psm1'
  ModuleVersion     = '4.0.0'
  GUID              = 'b7e5f0f1-8a91-4a8f-9b2c-3e5d1f2a6c8d'
  Author            = 'PanzuraDemo'
  CompanyName       = 'DemoCorp'
  Copyright         = 'Internal use'
  Description       = 'Messy enterprise NAS generator for file-system security scan demos.'
  PowerShellVersion = '7.0'
  FunctionsToExport = @(
    'Invoke-DemoPipeline'
    'Test-DemoPrerequisite'
    'Test-DemoSmokeVerification'
    'New-DemoADPopulation'
    'New-DemoFolderTree'
    'New-DemoFile'
    'Remove-DemoOrphanUser'
    'Get-DemoReport'
    'Reset-DemoEnvironment'
    'Import-DemoConfig'
    'Get-DemoScenario'
  )
  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()
  RequiredModules   = @()
  PrivateData       = @{
    PSData = @{
      Tags = @('panzura','demo','nas','acl','messy')
    }
  }
}
