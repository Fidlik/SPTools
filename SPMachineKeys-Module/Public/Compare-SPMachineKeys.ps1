<# 
Compare SharePoint machine key exports with colorized output and multi-server support.

Two entry points:
  1) Compare-SPMachineKeys           -> compare two files or auto-pick two newest in a folder
  2) Compare-SPMachineKeysInRoot     -> iterate all immediate subfolders (servers) under a root

Colors:
  Unchanged  = DarkGray
  Added      = Green
  Removed    = Magenta
  Changed*   = Yellow (Validation/Decryption) or Red (both changed)

#>

function Compare-SPMachineKeys {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$Path,

        [string]$OldFile,
        [string]$NewFile,

        [switch]$ShowKeys,

        [string]$OutCsv,
        [string]$OutJson,

        [switch]$NoConsoleTable  # if set, won't print the color table (still returns objects)
    )

    #--- helpers ---------------------------------------------------------------
    function Get-Sha1 {
        param([Parameter(Mandatory)][string]$Text)
        $sha1 = [System.Security.Cryptography.SHA1]::Create()
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
            $hash  = $sha1.ComputeHash($bytes)
            -join ($hash | ForEach-Object { $_.ToString("x2") })
        }
        finally { $sha1.Dispose() }
    }

    function Mask-Key {
        param([string]$Key)
        if ([string]::IsNullOrEmpty($Key)) { return $Key }
        if ($Key.Length -le 12) { return $Key }
        return "{0}…{1}" -f $Key.Substring(0,6), $Key.Substring($Key.Length-6,6)
    }

    function Read-KeyFile {
        param([Parameter(Mandatory)][string]$File)
        if (-not (Test-Path -LiteralPath $File)) {
            throw "File not found: $File"
        }
        $raw = Get-Content -LiteralPath $File -Raw
        $items = $null
        try { $items = $raw | ConvertFrom-Json }
        catch { throw "Failed to parse JSON in '$File': $($_.Exception.Message)" }

        $map = @{}
        foreach ($it in $items) {
            if (-not $it.Url) { continue }
            $map[$it.Url] = [PSCustomObject]@{
                Url            = [string]$it.Url
                ValidationKey  = [string]$it.ValidationKey
                DecryptionKey  = [string]$it.DecryptionKey
            }
        }
        return $map
    }

    function Pick-LatestTwo {
        param([Parameter(Mandatory)][string]$Folder)
        if (-not (Test-Path -LiteralPath $Folder)) {
            throw "Folder not found: $Folder"
        }
        $files = Get-ChildItem -LiteralPath $Folder -File -Filter *_machineKeys.json |
                 Sort-Object LastWriteTimeUtc -Descending
        if ($files.Count -lt 2) {
            throw "Found only $($files.Count) '*_machineKeys.json' in '$Folder'. Need at least two."
        }
        return @($files[1].FullName, $files[0].FullName) # [old,new]
    }

    function Get-ColorForChange {
        param([string]$Change)
        switch -Regex ($Change) {
            '^Unchanged$'                           { 'DarkGray'; break }
            '^Added$'                               { 'Green'; break }
            '^Removed$'                             { 'Magenta'; break }
            'Changed \(Validation & Decryption\)'   { 'Red'; break }
            'Changed \(Validation only\)'           { 'Yellow'; break }
            'Changed \(Decryption only\)'           { 'Yellow'; break }
            default                                 { 'White' }
        }
    }
    #-------------------------------------------------------------------------

    # Resolve file pair
    if ([string]::IsNullOrWhiteSpace($OldFile) -or [string]::IsNullOrWhiteSpace($NewFile)) {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw "Provide -Path to auto-pick files, or specify both -OldFile and -NewFile."
        }
        $pair = Pick-LatestTwo -Folder $Path
        $OldFile = $pair[0]
        $NewFile = $pair[1]
    }

    # Read files
    $oldMap = Read-KeyFile -File $OldFile
    $newMap = Read-KeyFile -File $NewFile

    # Union of URLs
    $allUrls = New-Object System.Collections.Generic.HashSet[string]
    $oldMap.Keys | ForEach-Object { $allUrls.Add($_) | Out-Null }
    $newMap.Keys | ForEach-Object { $allUrls.Add($_) | Out-Null }

    # Build results
    $results = foreach ($url in $allUrls) {
        $old = $oldMap[$url]
        $new = $newMap[$url]

        if ($null -eq $old) {
            $change = 'Added'
            $ovk = $odk = $null
            $nvk = $new.ValidationKey
            $ndk = $new.DecryptionKey
        }
        elseif ($null -eq $new) {
            $change = 'Removed'
            $ovk = $old.ValidationKey
            $odk = $old.DecryptionKey
            $nvk = $ndk = $null
        }
        else {
            $vkSame = ($old.ValidationKey -eq $new.ValidationKey)
            $dkSame = ($old.DecryptionKey -eq $new.DecryptionKey)
            if     ($vkSame -and $dkSame) { $change = 'Unchanged' }
            elseif (-not $vkSame -and -not $dkSame) { $change = 'Changed (Validation & Decryption)' }
            elseif (-not $vkSame) { $change = 'Changed (Validation only)' }
            else { $change = 'Changed (Decryption only)' }

            $ovk = $old.ValidationKey; $odk = $old.DecryptionKey
            $nvk = $new.ValidationKey; $ndk = $new.DecryptionKey
        }

        if ($ShowKeys) {
            $dispOldVK = $ovk; $dispOldDK = $odk
            $dispNewVK = $nvk; $dispNewDK = $ndk
        } else {
            $dispOldVK = if ($ovk) { "{0} ({1})" -f (Mask-Key $ovk), (Get-Sha1 $ovk).Substring(0,12) } else { $null }
            $dispOldDK = if ($odk) { "{0} ({1})" -f (Mask-Key $odk), (Get-Sha1 $odk).Substring(0,12) } else { $null }
            $dispNewVK = if ($nvk) { "{0} ({1})" -f (Mask-Key $nvk), (Get-Sha1 $nvk).Substring(0,12) } else { $null }
            $dispNewDK = if ($ndk) { "{0} ({1})" -f (Mask-Key $ndk), (Get-Sha1 $ndk).Substring(0,12) } else { $null }
        }

        [PSCustomObject]@{
            Url               = $url
            Change            = $change
            OldValidationKey  = $dispOldVK
            NewValidationKey  = $dispNewVK
            OldDecryptionKey  = $dispOldDK
            NewDecryptionKey  = $dispNewDK
            OldFile           = $OldFile
            NewFile           = $NewFile
        }
    }

    $results = $results | Sort-Object -Property Change, Url

    # Optional exports
    if ($OutCsv)  { $results | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $OutCsv }
    if ($OutJson) { $results | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $OutJson -Encoding UTF8 }

    # Colorized console table (simple padded columns)
    if (-not $NoConsoleTable) {
        $header = "{0,-10}  {1,-60}  {2,-28}  {3,-28}" -f 'Change','Url','Old (masked/hash)','New (masked/hash)'
        Write-Host $header -ForegroundColor Cyan
        foreach ($r in $results) {
            $color = Get-ColorForChange $r.Change
            $line  = "{0,-10}  {1,-60}  {2,-28}  {3,-28}" -f $r.Change, $r.Url, $r.OldValidationKey, $r.NewValidationKey
            Write-Host $line -ForegroundColor $color
        }
        # Note: table shows ValidationKey columns for brevity. Use -ShowKeys to reveal full values.
    }

    return $results
}

function Compare-SPMachineKeysInRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root,               # e.g. E:\temp\SharePoint_Config_MachineKeys
        [switch]$ShowKeys,
        [string]$OutDir,             # optional: where to drop per-server CSV/JSON
        [switch]$JsonToo,            # if set, creates JSON next to CSV
        [switch]$NoConsoleTable,
        [switch]$PassThru            # <-- NEW: only return objects when requested
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        throw "Root not found: $Root"
    }

    $serverDirs = Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name
    if ($serverDirs.Count -eq 0) {
        throw "No server subfolders found under '$Root'."
    }

    $all = @()
    foreach ($dir in $serverDirs) {
        $serverName = $dir.Name
        Write-Host ""
        Write-Host ("===== {0} =====" -f $serverName) -ForegroundColor Cyan

        try {
            $results = Compare-SPMachineKeys -Path $dir.FullName -ShowKeys:$ShowKeys -NoConsoleTable:$NoConsoleTable
            # annotate with Server
            $results = $results | Select-Object @{n='Server';e={$serverName}}, Url, Change,
                                            OldValidationKey, NewValidationKey,
                                            OldDecryptionKey, NewDecryptionKey,
                                            OldFile, NewFile
            $all += $results

            if ($OutDir) {
                if (-not (Test-Path -LiteralPath $OutDir)) {
                    New-Item -ItemType Directory -Path $OutDir | Out-Null
                }
                $csv = Join-Path $OutDir ("{0}_machineKeys_diff.csv" -f $serverName)
                $results | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $csv
                if ($JsonToo) {
                    $json = Join-Path $OutDir ("{0}_machineKeys_diff.json" -f $serverName)
                    $results | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $json -Encoding UTF8
                }
            }

            # Detailed dump ONLY with -Verbose
            if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
                foreach ($r in $results) {
                    Write-Verbose ("Server           : {0}" -f $r.Server)
                    Write-Verbose ("Url              : {0}" -f $r.Url)
                    Write-Verbose ("Change           : {0}" -f $r.Change)
                    Write-Verbose ("OldValidationKey : {0}" -f $r.OldValidationKey)
                    Write-Verbose ("NewValidationKey : {0}" -f $r.NewValidationKey)
                    Write-Verbose ("OldDecryptionKey : {0}" -f $r.OldDecryptionKey)
                    Write-Verbose ("NewDecryptionKey : {0}" -f $r.NewDecryptionKey)
                    Write-Verbose ("OldFile          : {0}" -f $r.OldFile)
                    Write-Verbose ("NewFile          : {0}" -f $r.NewFile)
                    Write-Verbose ""
                }
            }

        }
        catch {
            Write-Host ("[ERROR] {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
    }

    # Overall summary counts
    Write-Host ""
    Write-Host "===== SUMMARY =====" -ForegroundColor Cyan
    $summary = $all | Group-Object Server, Change | Sort-Object Name
    foreach ($g in $summary) {
        $server, $change = $g.Name -split ',\s*', 2
        $color = switch ($change) {
            'Unchanged' { 'DarkGray' }
            'Added'     { 'Green' }
            'Removed'   { 'Magenta' }
            default     { 'Yellow' }
        }
        Write-Host ("{0,-16}  {1,-30}  {2,5}" -f $server, $change, $g.Count) -ForegroundColor $color
    }

    # Only emit objects if -PassThru is set
    if ($PassThru) { return $all }
}


# ------------------ Quick-start examples ------------------
# Single server folder (auto-pick two newest files):
# Compare-SPMachineKeys -Path "E:\temp\SharePoint_Config_MachineKeys\SERVERNAME"

# Root with multiple servers (creates per-server CSVs):
# Compare-SPMachineKeysInRoot -Root  "E:\temp\SharePoint_Config_MachineKeys" `
#                             -OutDir "E:\temp\SharePoint_Config_MachineKeys\Diffs" `
#                             -JsonToo