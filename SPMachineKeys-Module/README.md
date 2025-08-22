# SPMachineKeys

PowerShell module for managing SharePoint `<machineKey>` values across a farm.

## Quick Start (Recommended Run Order)
1. `BackupAndExport-SPMachineKeys`  – create a point-in-time export/backup
2. `Set-SPMachineKeyEachWebApp`     – generate/set new keys in config DB per web app
3. `Invoke-LocalMachineKeyUpdateFarm` – apply keys to each server (Update-SPMachineKey -Local)
4. `BackupAndExport-SPMachineKeys`  – export again after changes
5. `Compare-SPMachineKeysInRoot`    – verify what changed across server subfolders

### Example
```powershell
# 1) Pre-change backup
$exportRoot = 'E:\temp\SharePoint_Config_MachineKeys'
BackupAndExport-SPMachineKeys -Path $exportRoot

# 2) Set new keys in the config DB per web app
Set-SPMachineKeyEachWebApp -IncludeCentralAdmin

# 3) Apply the keys locally on each farm server
Invoke-LocalMachineKeyUpdateFarm -RestartIIS

# 4) Post-change backup
BackupAndExport-SPMachineKeys -Path $exportRoot

# 5) Compare across server subfolders
Compare-SPMachineKeysInRoot -Path $exportRoot
```

## Installation
See the docs/Guide.pdf or README for detailed steps.
