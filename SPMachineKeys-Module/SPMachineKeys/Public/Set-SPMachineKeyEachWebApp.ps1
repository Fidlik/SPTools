<#
.SYNOPSIS
    Updates SharePoint machine keys for all web applications.

.DESCRIPTION
    This script retrieves all SharePoint web applications, including the Central Administration site, 
    and runs the Set-SPMachineKey command for each. 
    This is typically used after patching or to re-sync keys across servers.

.NOTES
    Author: [Your Name]
    Date:   [YYYY-MM-DD]
    Tested on: SharePoint 2016/2019/Subscription Edition
    Requires: Microsoft.SharePoint.PowerShell snap-in
#>

# --- Classic PowerShell Header ---
# Load SharePoint PowerShell snap-in if not already loaded
if (-not (Get-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell
}

function Set-SPMachineKeyEachWebApp {
    # Get all web applications including Central Administration
    $webApps = Get-SPWebApplication -IncludeCentralAdministration

    foreach ($wa in $webApps) {
        Write-Host "Updating keys on $($wa.Url)..." -ForegroundColor Cyan
        Set-SPMachineKey -WebApplication $wa
    }
}

# --- Classic PowerShell Execution ---
# Run the function
#Set-SPMachineKeyEachWebApp