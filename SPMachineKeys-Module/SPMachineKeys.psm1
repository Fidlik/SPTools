# Auto-generated PowerShell module loader for SPMachineKeys

try { Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue | Out-Null } catch {}

Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter *.ps1 -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

Export-ModuleMember -Function * -Alias *
