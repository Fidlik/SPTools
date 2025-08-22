@{
    RootModule        = 'SPMachineKeys.psm1'
    ModuleVersion     = '1.0.1'
    GUID              = '4964cf3f-13e1-4ff1-b980-8795d9e05766'
    Author            = 'Zdenek Machura'
    CompanyName       = 'N/A'
    Copyright         = '(c) 2025-08-22 Zdenek Machura. All rights reserved.'
    Description       = 'Utilities to export, rotate, apply, and compare SharePoint <machineKey> values across a farm.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'BackupAndExport-SPMachineKeys',
        'Set-SPMachineKeyEachWebApp',
        'Invoke-LocalMachineKeyUpdateFarm',
        'Compare-SPMachineKeys',
        'Compare-SPMachineKeysInRoot'
    )
    AliasesToExport   = @()
    CmdletsToExport   = @()
    VariablesToExport = '*'
    PrivateData       = @{ PSData = @{ Tags = @('SharePoint','MachineKey','Farm','IIS','Config'); } }
}
