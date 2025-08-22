function BackupAndExport-SPMachineKeys {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    begin {
        # Default export directory
        $defaultRoot = 'E:\temp\SharePoint_Config_MachineKeys'
        if (-not (Test-Path $defaultRoot)) {
            Write-Verbose "Creating base export directory: $defaultRoot"
            New-Item -Path $defaultRoot -ItemType Directory -Force | Out-Null
        }

        # Determine export root
        if (-not $PSBoundParameters.ContainsKey('Path')) {
            $Path = $defaultRoot
        }
        if (-not (Test-Path $Path)) {
            Write-Verbose "Creating root export directory: $Path"
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }

        # Local web apps and farm servers
        $webApps    = Get-SPWebApplication -IncludeCentralAdministration
        $ServerList = Get-SPServer |
                      Where-Object Role -ne 'Invalid' |
                      Select-Object -ExpandProperty Name
        Write-Verbose "Will process servers: $($ServerList -join ', ')"

        # Timestamp for filenames: ddMMyyHHmmss (added seconds)
        $timestamp = Get-Date -Format ddMMyyHHmmss
    }

    process {
        foreach ($server in $ServerList) {
            Write-Verbose "Processing server: $server"

            # Create per-server output folder
            $serverFolder = Join-Path $Path $server
            if (-not (Test-Path $serverFolder)) {
                Write-Verbose "Creating folder for $server : $serverFolder"
                New-Item -Path $serverFolder -ItemType Directory -Force | Out-Null
            }

            $collected = @()

            foreach ($wa in $webApps) {
                # Local path to web.config
                $localCfg = Join-Path $wa.IisSettings['Default'].Path 'web.config'

                # Convert to UNC using C$ admin share
                $drive   = $localCfg.Substring(0,1)
                $uncPath = "\\$server\$($drive)`$" + $localCfg.Substring(2)

                if (Test-Path $uncPath) {
                    Write-Verbose "Found web.config at $uncPath"
                    [xml]$xml = Get-Content $uncPath
                    $mk = $xml.configuration.'system.web'.machineKey
                    if ($mk) {
                        $collected += [PSCustomObject]@{
                            Url           = $wa.Url
                            ValidationKey = $mk.validationKey
                            DecryptionKey = $mk.decryptionKey
                        }
                        Write-Host "  • Backed up machineKey for $($wa.Url)" -ForegroundColor Green
                    } else {
                        Write-Warning "  • No <machineKey> section in $uncPath"
                    }
                } else {
                    Write-Warning "  • Cannot reach web.config at $uncPath"
                }
            }

            # Export JSON per server
            if ($collected.Count) {
                $jsonName = "{0}_{1}_machineKeys.json" -f $timestamp, $server
                $jsonPath = Join-Path $serverFolder $jsonName
                $collected |
                    ConvertTo-Json -Depth 3 |
                    Out-File -FilePath $jsonPath -Encoding UTF8

                Write-Host "`n[$server] Exported $($collected.Count) entries to: $jsonPath`n" -ForegroundColor Green
            } else {
                Write-Warning "[$server] No machineKey entries collected."
            }
        }
    }
}
