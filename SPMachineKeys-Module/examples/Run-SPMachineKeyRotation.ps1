<#
.SYNOPSIS
    Orchestrates a full machine key rotation across a SharePoint farm
    using the SPMachineKeys module functions in the recommended order.
    This script will auto-load the module if possible.
#>

[CmdletBinding()]
param(
    [string]$ExportPath = 'E:\temp\SharePoint_Config_MachineKeys',
    [switch]$IncludeCentralAdmin,
    [switch]$RestartIIS,
    [string]$ModulePath
)

$ErrorActionPreference = 'Stop'
$ModuleName = 'SPMachineKeys'

function Import-SPMachineKeysModule {
    param([string]$HintPath)

    Write-Host ">> Loading $ModuleName module..." -ForegroundColor Cyan

    if ($HintPath) {
        if (Test-Path $HintPath) {
            if ((Get-Item $HintPath).PSIsContainer) {
                $psd1 = Join-Path $HintPath "$ModuleName.psd1"
                $psm1 = Join-Path $HintPath "$ModuleName.psm1"
                if (Test-Path $psd1) { Import-Module $psd1 -Force -ErrorAction Stop; return }
                if (Test-Path $psm1) { Import-Module $psm1 -Force -ErrorAction Stop; return }
            } else {
                Import-Module $HintPath -Force -ErrorAction Stop; return
            }
        } else {
            Write-Warning "ModulePath not found: $HintPath"
        }
    }

    try { Import-Module $ModuleName -ErrorAction Stop -Force; return } catch {}

    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $moduleRoot = Split-Path -Parent $scriptRoot
    $psd1Local = Join-Path $moduleRoot "$ModuleName.psd1"
    $psm1Local = Join-Path $moduleRoot "$ModuleName.psm1"
    if (Test-Path $psd1Local) { Import-Module $psd1Local -Force -ErrorAction Stop; return }
    if (Test-Path $psm1Local) { Import-Module $psm1Local -Force -ErrorAction Stop; return }

    throw "Unable to load $ModuleName. Provide -ModulePath or install the module."
}

Import-SPMachineKeysModule -HintPath $ModulePath

Write-Host "=== SPMachineKeys Rotation Orchestrator ===" -ForegroundColor Cyan
Write-Host "[1/5] Pre-change backup/export..." -ForegroundColor Yellow
BackupAndExport-SPMachineKeys -Path $ExportPath

Write-Host "[2/5] Setting new keys in config DB per Web App..." -ForegroundColor Yellow
if ($IncludeCentralAdmin) {
    Set-SPMachineKeyEachWebApp -IncludeCentralAdmin
} else {
    Set-SPMachineKeyEachWebApp
}

Write-Host "[3/5] Applying keys across farm (Update-SPMachineKey -Local on each server)..." -ForegroundColor Yellow
if ($RestartIIS) {
    Invoke-LocalMachineKeyUpdateFarm -RestartIIS
} else {
    Invoke-LocalMachineKeyUpdateFarm
}

Write-Host "[4/5] Post-change backup/export..." -ForegroundColor Yellow
BackupAndExport-SPMachineKeys -Path $ExportPath

Write-Host "[5/5] Comparing exports across server subfolders..." -ForegroundColor Yellow
Compare-SPMachineKeysInRoot -Root $ExportPath

Write-Host "=== Completed ===" -ForegroundColor Green
