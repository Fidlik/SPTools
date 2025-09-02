<# 
.SYNOPSIS
  Audits and applies <authorizedType> entries under:
  configuration/system.workflow.componentmodel/workflowCompiler/authorizedTypes/targetFx[@version='v4.0']

.DESCRIPTION
  - Applies a named "set" (e.g., NintexFix_20250902) of authorizedType entries.
  - Adds only what’s missing. Makes a timestamped backup before changes.
  - Can source the set from: 
      a) Built-in hashtables in this script, or 
      b) A GitHub JSON file (one file per set), schema below.

.EXAMPLES
  .\Invoke-WorkflowAuthorizedTypesFix.ps1 -WebConfigPath 'C:\inetpub\wwwroot\web.config' -SetName NintexFix_20250902
  .\Invoke-WorkflowAuthorizedTypesFix.ps1 -WebConfigPath .\web.config -SetName NintexFix_20250902 -AutoAdd
  .\Invoke-WorkflowAuthorizedTypesFix.ps1 -WebConfigPath .\web.config -SetName NintexFix_20250902 -GitHubRawBase 'https://raw.githubusercontent.com/ORG/REPO/MAIN/sets' -AutoAdd
  .\Invoke-WorkflowAuthorizedTypesFix.ps1 -WebConfigPath .\web.config -SetPath .\sets\NintexFix_20250902.json -AutoAdd -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$WebConfigPath,

    # Choose one way to supply the set:
    [string]$SetName = 'NintexFix_20250902',     # built-in or remote file `${SetName}.json`
    [string]$SetPath,                             # explicit local JSON path (overrides -SetName/-GitHubRawBase)
    [string]$GitHubRawBase,                       # e.g. https://raw.githubusercontent.com/ORG/REPO/main/sets

    [switch]$AutoAdd                              # skip confirmation prompt
)

# ----------------- Helpers -----------------
function New-XmlElem { param($Doc,[string]$Name) $Doc.CreateElement($Name) }
function Is-Element($n,[string]$name) { $n -and $n.NodeType -eq [System.Xml.XmlNodeType]::Element -and $n.LocalName -ieq $name }
function Normalize-Attr([string]$s) { if ($null -eq $s) { return $null } $s.Trim() }

function Ensure-Path {
    param([System.Xml.XmlDocument]$Doc,[string]$PathDesc)
    $root = $Doc.DocumentElement
    if (-not $root -or $root.LocalName -ine 'configuration') {
        $root = $Doc.SelectSingleNode("//*[local-name()='configuration']")
        if (-not $root) { throw "No <configuration> element found in $PathDesc" }
    }
    $sys = $root.SelectSingleNode("*[local-name()='system.workflow.componentmodel']")
    if (-not $sys) { $sys = New-XmlElem $Doc 'system.workflow.componentmodel'; [void]$root.AppendChild($sys) }

    $wfc = $sys.SelectSingleNode("*[local-name()='workflowCompiler']")
    if (-not $wfc) { $wfc = New-XmlElem $Doc 'workflowCompiler'; [void]$sys.AppendChild($wfc) }

    $auth = $wfc.SelectSingleNode("*[local-name()='authorizedTypes']")
    if (-not $auth) { $auth = New-XmlElem $Doc 'authorizedTypes'; [void]$wfc.AppendChild($auth) }

    $fx40 = $null
    foreach ($n in $auth.ChildNodes) {
        if (Is-Element $n 'targetFx') {
            $ver = $n.Attributes['version']?.Value
            if ($ver -and $ver -ieq 'v4.0') { $fx40 = $n; break }
        }
    }
    if (-not $fx40) {
        $fx40 = New-XmlElem $Doc 'targetFx'
        $a = $Doc.CreateAttribute('version'); $a.Value = 'v4.0'
        [void]$fx40.Attributes.Append($a)
        [void]$auth.AppendChild($fx40)
    }

    return $fx40
}

function Get-ExistingAuthorizedTypes {
    param([System.Xml.XmlElement]$TargetFx)
    $items = @()
    foreach ($n in $TargetFx.ChildNodes) {
        if (-not (Is-Element $n 'authorizedType')) { continue }
        $items += [pscustomobject]@{
            Assembly  = Normalize-Attr $n.Attributes['Assembly'] ?.Value
            Namespace = Normalize-Attr $n.Attributes['Namespace']?.Value
            TypeName  = Normalize-Attr $n.Attributes['TypeName'] ?.Value
            Authorized= Normalize-Attr $n.Attributes['Authorized']?.Value
            _node     = $n
        }
    }
    $items
}

function Same-AuthorizedType($a,$b) {
    ($a.Assembly  -ieq $b.Assembly)  -and
    ($a.Namespace -ieq $b.Namespace) -and
    ($a.TypeName  -ieq $b.TypeName)  -and
    ($a.Authorized-ieq $b.Authorized)
}

function Add-AuthorizedType {
    param(
        [System.Xml.XmlDocument]$Doc,
        [System.Xml.XmlElement]$TargetFx,
        [hashtable]$Spec
    )
    $e = New-XmlElem $Doc 'authorizedType'
    foreach ($k in 'Assembly','Namespace','TypeName','Authorized') {
        $v = $Spec[$k]
        if ($null -ne $v -and $v -ne '') {
            $attr = $Doc.CreateAttribute($k)
            $attr.Value = [string]$v
            [void]$e.Attributes.Append($attr)
        }
    }
    [void]$TargetFx.AppendChild($e)
    return $e
}

function Load-Set {
    param([string]$SetName,[string]$SetPath,[string]$GitHubRawBase)

    # 1) From explicit local JSON path
    if ($SetPath) {
        if (-not (Test-Path $SetPath -PathType Leaf)) { throw "Set file not found: $SetPath" }
        return Get-Content -Raw -Path $SetPath | ConvertFrom-Json
    }

    # 2) From GitHub raw: ${GitHubRawBase}/${SetName}.json
    if ($GitHubRawBase) {
        $url = ($GitHubRawBase.TrimEnd('/')) + '/' + $SetName + '.json'
        try {
            $wc = New-Object System.Net.WebClient
            $json = $wc.DownloadString($url)
            if ($json) { return $json | ConvertFrom-Json }
        } catch {
            throw "Failed to fetch set from GitHub: $url `n$($_.Exception.Message)"
        }
    }

    # 3) Built-in sets (fallback)
    switch -Regex ($SetName) {
        '^NintexFix_20250902$' {
            return @{
                name = 'NintexFix_20250902'
                description = 'Nintex + WF compiler auth types refresh'
                authorizedTypes = @(
                    @{ Assembly='Microsoft.Office.Access.Server.Application, Version=15.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c'; Namespace='Microsoft.Office.Access.Server.Macro.Runtime'; TypeName='*'; Authorized='True' },
                    @{ Assembly='Microsoft.SharePoint.WorkflowActions, Version=15.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c'; Namespace='Microsoft.SharePoint.WorkflowActions'; TypeName='*'; Authorized='True' },
                    @{ Assembly='Microsoft.SharePoint.WorkflowActions, Version=16.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c'; Namespace='Microsoft.SharePoint.WorkflowActions.WithKey'; TypeName='*'; Authorized='True' },
                    @{ Assembly='Microsoft.SharePoint.WorkflowActions, Version=16.0.0.0, Culture=neutral, PublicKeyToken=null'; Namespace='Microsoft.SharePoint.WorkflowActions.WithKey'; TypeName='*'; Authorized='True' },
                    @{ Assembly='Nintex.Workflow, Version=1.0.0.0, Culture=neutral, PublicKeyToken=913f6bae0ca5ae12'; Namespace='Nintex.Workflow'; TypeName='RunNowParameterOptions'; Authorized='True' },
                    @{ Assembly='Nintex.Workflow, Version=1.0.0.0, Culture=neutral, PublicKeyToken=913f6bae0ca5ae12'; Namespace='Nintex.Workflow.'; TypeName=''; Authorized='True' },
                    @{ Assembly='Nintex.Workflow.Live, Version=1.0.0.0, Culture=neutral, PublicKeyToken=bd539bd4aa1e2820'; Namespace='Nintex.Workflow.Live.Actions'; TypeName='*'; Authorized='True' },
                    @{ Assembly='System, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089'; Namespace='System.CodeDom'; TypeName='*'; Authorized='True' },
                    @{ Assembly='System.Workflow.ComponentModel, Version=3.0.0.0, Culture=neutral,PublicKeyToken=31bf3856ad364e35'; Namespace='System.Workflow.*'; TypeName='ArrayExtension'; Authorized='True' },
                    @{ Assembly='System.Workflow.ComponentModel, Version=3.0.0.0, Culture=neutral,PublicKeyToken=31bf3856ad364e35'; Namespace='System.Workflow.*'; TypeName='TypeExtension'; Authorized='True' },
                    @{ Assembly='System.Workflow.ComponentModel, Version=4.0.0.0, Culture=neutral,PublicKeyToken=31bf3856ad364e35'; Namespace='System.Workflow.*'; TypeName='ArrayExtension'; Authorized='True' },
                    @{ Assembly='System.Workflow.ComponentModel, Version=4.0.0.0, Culture=neutral,PublicKeyToken=31bf3856ad364e35'; Namespace='System.Workflow.*'; TypeName='TypeExtension'; Authorized='True' },
                    @{ Assembly='mscorlib, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089'; Namespace='System'; TypeName='Int64'; Authorized='True' },
                    @{ Assembly='mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089'; Namespace='System'; TypeName='Int64'; Authorized='True' }
                )
            }
        }
        default { throw "Unknown set '$SetName'. Provide -SetPath or -GitHubRawBase, or add a built-in case." }
    }
}

# ----------------- Main -----------------
Write-Verbose "Loading $WebConfigPath …"
[xml]$xml = Get-Content -Raw -Path $WebConfigPath
$fx40 = Ensure-Path -Doc $xml -PathDesc $WebConfigPath

$existing = Get-ExistingAuthorizedTypes -TargetFx $fx40
$set     = Load-Set -SetName $SetName -SetPath $SetPath -GitHubRawBase $GitHubRawBase

$target  = @($set.authorizedTypes | ForEach-Object {
    [pscustomobject]@{
        Assembly   = Normalize-Attr $_.Assembly
        Namespace  = Normalize-Attr $_.Namespace
        TypeName   = Normalize-Attr $_.TypeName
        Authorized = Normalize-Attr $_.Authorized
    }
})

# Find missing entries (exact match on 4 attrs)
$missing = foreach ($t in $target) {
    $match = $existing | Where-Object { Same-AuthorizedType $_ $t }
    if (-not $match) { $t }
}

Write-Host "Set: $($set.name) — $($set.description)" -ForegroundColor Cyan
Write-Host "Existing entries: $($existing.Count)"
Write-Host "Target entries:   $($target.Count)"
Write-Host "Missing entries:  $($missing.Count)" -ForegroundColor Yellow

if ($missing.Count -eq 0) {
    Write-Host "Nothing to add. You're good. ✅" -ForegroundColor Green
    return
}

# Preview table
$missing | Select-Object Assembly,Namespace,TypeName,Authorized | Format-Table | Out-Host

$proceed = $false
if ($AutoAdd) {
    $proceed = $true
} else {
    $answer = Read-Host "Add the missing $($missing.Count) item(s) to $WebConfigPath ? (Y/N)"
    if ($answer -match '^(y|yes)$') { $proceed = $true }
}

if (-not $proceed) {
    Write-Host "Aborted by user. No changes written." -ForegroundColor DarkYellow
    return
}

# Backup and write
$backup = "{0}.{1:yyyyMMdd_HHmmss}.bak" -f $WebConfigPath,(Get-Date)
if ($PSCmdlet.ShouldProcess($WebConfigPath,"Backup to $backup and add $($missing.Count) entries"))) {

    Copy-Item -Path $WebConfigPath -Destination $backup -Force

    foreach ($m in $missing) {
        [void](Add-AuthorizedType -Doc $xml -TargetFx $fx40 -Spec ([hashtable]$m))
    }

    $xml.Save($WebConfigPath)
    Write-Host "Saved. Backup: $backup" -ForegroundColor Green
}
