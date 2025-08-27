<#
.SYNOPSIS
    Push "Update-SPMachineKey -Local" to all SharePoint servers via a pure script-block.

.DESCRIPTION
    - Resolves WebApp URLs locally (works with your local farm perms).
    - Resolves target servers simply with Get-SPServer where Role != Invalid and Status = Online.
    - Remotes to each server and applies keys locally for each URL.
    - Supports -WhatIf, optional IIS reset, CSV export, and CredSSP/Kerberos.

.PREREQS
    - Run from SharePoint Management Shell on a farm server.
    - WinRM enabled on all targets.
    - Use CredSSP (or Kerberos) if you hit the double-hop issue to SQL.

.PARAMETERS
    -Servers             Explicit target servers (optional). If omitted -> auto-discover.
    -IncludeCentralAdmin Include Central Admin URL (default: off).
    -RestartIIS          Restart IIS on each target after updates.
    -Authentication      CredSSP | Kerberos | Default (default: CredSSP).
    -Credential          Credential for remoting (prompted if omitted).
    -OutCsv              Optional path to export results.
#>

function Invoke-LocalMachineKeyUpdateFarm {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$Servers,  # optional; if omitted we'll auto-discover

        [switch]$ExcludeCentralAdmin,
        [switch]$RestartIIS,

        [ValidateSet('CredSSP','Kerberos','Default')]
        [string]$Authentication = 'CredSSP',

        [System.Management.Automation.PSCredential]$Credential,

        [string]$OutCsv
    )

    begin {
        Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue

        # ---- Resolve WebApp URLs locally ----
        $allWAs = Get-SPWebApplication -IncludeCentralAdministration
        if ($ExcludeCentralAdministration) {
            # Only remove Central Admin if user explicitly asked
            $allWAs = $allWAs | Where-Object { -not $_.IsAdministrationWebApplication }
        }

        $WebAppUrls = $allWAs | Select-Object -ExpandProperty Url
        if (-not $WebAppUrls -or $WebAppUrls.Count -eq 0) {
            throw "No Web Applications resolved locally. (Check your local SharePoint shell access.)"
        }

        Write-Host "Resolved $(($WebAppUrls | Measure-Object).Count) WebApp URL(s) locally:" -ForegroundColor Cyan
        $WebAppUrls | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkCyan }

        # ---- Resolve servers with simple filter (Role != Invalid, Online) ----
        if (-not $Servers -or $Servers.Count -eq 0) {
            $Servers = Get-SPServer |
                Where-Object { $_.Role -ne 'Invalid' -and $_.Status -eq 'Online' } |
                Select-Object -ExpandProperty Address -Unique
        }
        if (-not $Servers -or $Servers.Count -eq 0) {
            throw "No target servers resolved. Pass -Servers explicitly or ensure Get-SPServer returns Online servers."
        }

        Write-Host "Servers to update (local write on each):" -ForegroundColor Cyan
        $Servers | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkCyan }

        # ---- Pure remote script-block (no farm discovery on remote) ----
        $RemoteScript = {
            param([string[]]$WebAppUrls,[bool]$DoRestartIIS)

            Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue
            $out = @()

            foreach ($u in $WebAppUrls) {
                $ok = $true; $msg = "Updated"
                try {
                    if ($WhatIfPreference) {
                        $msg = "WhatIf: would update locally"
                    } else {
                        Update-SPMachineKey -WebApplication $u -Local -ErrorAction Stop
                    }
                } catch {
                    $ok = $false; $msg = $_.Exception.Message
                }
                $out += [pscustomobject]@{
                    Server = $env:COMPUTERNAME
                    Url    = $u
                    Result = if ($ok) { "Success" } else { "Error" }
                    Message= $msg
                    Time   = Get-Date
                }
            }

            if ($DoRestartIIS -and -not $WhatIfPreference) {
                try { iisreset | Out-Null } catch {
                    $out += [pscustomobject]@{
                        Server  = $env:COMPUTERNAME
                        Url     = "(n/a)"
                        Result  = "Warning"
                        Message = "IIS reset failed: $($_.Exception.Message)"
                        Time    = Get-Date
                    }
                }
            }

            $out
        }

        # ---- Prepare remoting params ----
        $invokeParams = @{
            ComputerName = $Servers
            ScriptBlock  = $RemoteScript
            ArgumentList = @($WebAppUrls, [bool]$RestartIIS)
            ThrottleLimit= 8
            ErrorAction  = 'Continue'
        }

        switch ($Authentication) {
            'CredSSP'  { $invokeParams['Authentication'] = 'CredSSP' }
            'Kerberos' { $invokeParams['Authentication'] = 'Kerberos' }
            'Default'  { } # WinRM default (likely NTLM)
        }

        if (-not $Credential) {
            $Credential = Get-Credential -Message "Enter the account that works locally on SP servers"
        }
        $invokeParams['Credential'] = $Credential

        Write-Host "Authentication: $Authentication" -ForegroundColor Cyan
        if ($Authentication -eq 'CredSSP') {
            Write-Host "Tip: CredSSP avoids SQL double-hop. Enable client + server if needed." -ForegroundColor DarkGray
        }
    }

    process {
        if (-not $PSCmdlet.ShouldProcess(($Servers -join ', '), 'Fan-out: Update-SPMachineKey -Local for each WebApp URL')) { return }

        $results = Invoke-Command @invokeParams
        $sorted  = $results | Sort-Object Server, Url

        # Show and return objects
        $sorted | Tee-Object -Variable __r | Format-Table Server, Url, Result, Message, Time -AutoSize | Out-Host

        if ($OutCsv) {
            try {
                $dir = Split-Path -Path $OutCsv -Parent
                if ($dir -and -not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
                $__r | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
                Write-Host "Results exported to: $OutCsv" -ForegroundColor Green
            } catch {
                Write-Warning "CSV export failed: $($_.Exception.Message)"
            }
        }

        return $__r
    }
}
