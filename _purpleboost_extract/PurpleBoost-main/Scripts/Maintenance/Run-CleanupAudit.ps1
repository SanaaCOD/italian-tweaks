#Requires -Version 5.1
param(
    [string]$ProjectRoot = "",
    [switch]$QuarantineOnly,
    [switch]$EncodingOnly,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$quarantineRoot = Join-Path $ProjectRoot "_cleanup_quarantine"
$auditPath = Join-Path $ProjectRoot "CLEANUP_AUDIT.md"
$labelsPath = Join-Path $ProjectRoot "src\constants\labels.js"

function Fix-Mojibake([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return $s }
    try {
        $enc28591 = [System.Text.Encoding]::GetEncoding(28591)
        $bytes = $enc28591.GetBytes($s)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        return $s
    }
}

function Repair-TextEncoding([string]$text) {
    $t = $text
    $arrow = [string][char]0x2192
    $prePairs = @(
        @([string]([char]0xE2) + [char]0x80 + [char]0xA0 + [char]0xE2 + [char]0x80 + [char]0x99), $arrow),
        @([string]([char]0xE2) + [char]0x80 + [char]0x99), [string][char]0x2019),
        @([string]([char]0xE2) + [char]0x80 + [char]0x9C), [string][char]0x201C),
        @([string]([char]0xE2) + [char]0x80 + [char]0x9D), [string][char]0x201D),
        @([string]([char]0xE2) + [char]0x80 + [char]0x93), [string][char]0x2013),
        @([string]([char]0xC2) + [char]0xAB), [string][char]0x00AB),
        @([string]([char]0xC2) + [char]0xBB), [string][char]0x00BB),
        @([string]([char]0xC2) + [char]0xB0), [string][char]0x00B0)
    )
    foreach ($pair in $prePairs) { $t = $t.Replace($pair[0], $pair[1]) }
    if ($t -match [char]0x00C3 -or $t -match [string]([char]0xE2)) {
        $t = Fix-Mojibake $t
    }
    foreach ($pair in $prePairs) { $t = $t.Replace($pair[0], $pair[1]) }
    $t = $t -replace '\uFFFD''', $arrow
    return $t
}

function Test-NeedsEncodingRepair([string]$text) {
    return ($text -match [char]0x00C3) -or ($text -match [string]([char]0xE2 + [char]0x80)) -or ($text -match [string]([char]0xC2)) -or ($text -match [char]0xFFFD)
}

function Move-ToQuarantine {
    param([string]$SourcePath, [string]$Reason, [string]$Risk)
    if (-not (Test-Path $SourcePath)) { return $null }
    $rel = $SourcePath.Substring($ProjectRoot.Length).TrimStart('\', '/')
    $dest = Join-Path $quarantineRoot $rel
    $destDir = Split-Path $dest -Parent
    if (-not $WhatIf) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        if (Test-Path $dest) {
            $dest = Join-Path $destDir ("dup_" + [Guid]::NewGuid().ToString('N').Substring(0, 8) + "_" + [System.IO.Path]::GetFileName($SourcePath))
        }
        Move-Item -LiteralPath $SourcePath -Destination $dest -Force
    }
    return [pscustomobject]@{
        Original    = $rel
        Destination = "_cleanup_quarantine/" + ($dest.Substring($quarantineRoot.Length).TrimStart('\', '/').Replace('\', '/'))
        Reason      = $Reason
        Risk        = $Risk
    }
}

$allFiles = @(Get-ChildItem -Path $ProjectRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\_cleanup_quarantine\\|\\node_modules\\|\\\.git\\' })
$scannedCount = $allFiles.Count
$moved = New-Object System.Collections.Generic.List[object]
$suspects = New-Object System.Collections.Generic.List[object]
$kept = New-Object System.Collections.Generic.List[object]
$encodingFixes = New-Object System.Collections.Generic.List[object]
$tests = New-Object System.Collections.Generic.List[string]

if (-not $EncodingOnly) {
    if (-not $WhatIf) { New-Item -ItemType Directory -Path $quarantineRoot -Force | Out-Null }

    $runtimeJsonKeep = @(
        'controller-devices-final.json', 'controller-devices-present.json', 'controller-device-signature.json',
        'controller-devices-cache.json', 'controller-hidusbf-status-all.json', 'controller-overclocker-status.json',
        'controller-overclocker-detect.json', 'controller-overclocker-params.json',
        'controller-overclocker-apply-result.json', 'controller-oc-result.json', 'controller-overclocker-exitcode.txt'
    )
    $logsDir = Join-Path $ProjectRoot "logs"
    if (Test-Path $logsDir) {
        Get-ChildItem -Path $logsDir -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $name = $_.Name
            $rel = $_.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/')
            if (($runtimeJsonKeep -contains $name) -and ($_.DirectoryName -eq $logsDir)) {
                [void]$kept.Add([pscustomobject]@{ File = $rel; Reason = "JSON etat runtime" })
                return
            }
            if (($name -eq 'controller-overclocker.log') -and ($_.DirectoryName -eq $logsDir)) {
                [void]$kept.Add([pscustomobject]@{ File = $rel; Reason = "Journal runtime recreatable" })
                return
            }
            $q = '(?i)(dump|before|after|diff|uia|debug|trace|test|radio-dump|live\.txt|\.reg$|_diag|_fixline|_fetch|_composite|_resolve|_usb-parent|oc-backups|hidusbf-probe|hidusbf-registry-diff|hidusbf-setup-.*-dump|nvcleaninstall-auto-live|ddu-auto-clean-live|safepoint-coordinate)'
            if ($name -match $q -or $rel -match '\\logs\\controller-oc-backups\\') {
                $m = Move-ToQuarantine -SourcePath $_.FullName -Reason "Log/debug/dump/backup obsolete" -Risk "Faible"
                if ($m) { [void]$moved.Add($m) }
                return
            }
            if ($name -match '\.log$' -and $_.Length -gt 2MB -and $name -ne 'controller-overclocker.log') {
                $m = Move-ToQuarantine -SourcePath $_.FullName -Reason "Ancien log volumineux" -Risk "Faible"
                if ($m) { [void]$moved.Add($m) }
                return
            }
            if ($_.DirectoryName -eq $logsDir -and $name -match '^_.*\.ps1$') {
                $m = Move-ToQuarantine -SourcePath $_.FullName -Reason "Script diagnostic temporaire logs/" -Risk "Faible"
                if ($m) { [void]$moved.Add($m) }
            }
        }
    }

    $backupDir = Join-Path $ProjectRoot "backup"
    if (Test-Path $backupDir) {
        Get-ChildItem -Path $backupDir -Recurse -File -Force | ForEach-Object {
            $m = Move-ToQuarantine -SourcePath $_.FullName -Reason "Backup manuel archive" -Risk "Faible"
            if ($m) { [void]$moved.Add($m) }
        }
    }

    $nvBroken = Join-Path $ProjectRoot "Scripts\NVIDIA-PS1-BROKEN-BACKUP"
    if (Test-Path $nvBroken) {
        Get-ChildItem -Path $nvBroken -Recurse -File -Force | ForEach-Object {
            $m = Move-ToQuarantine -SourcePath $_.FullName -Reason "Scripts NVIDIA backup casses" -Risk "Faible"
            if ($m) { [void]$moved.Add($m) }
        }
    }

    $strayEq = Join-Path $ProjectRoot "="
    if (Test-Path $strayEq) {
        $m = Move-ToQuarantine -SourcePath $strayEq -Reason "Fichier parasite racine" -Risk "Faible"
        if ($m) { [void]$moved.Add($m) }
    }

    $suspectScripts = @(
        'Scripts\Devices\Detect-USBControllers-Fast.ps1',
        'Scripts\Devices\Detect-Controllers-HidusbfLink.ps1',
        'Scripts\Devices\Sync-ControllerDevices.ps1',
        'Scripts\Devices\Merge-ControllerDevices.ps1',
        'Scripts\Devices\Get-ControllerPresentDevices.ps1'
    )
    foreach ($rel in $suspectScripts) {
        if (Test-Path (Join-Path $ProjectRoot $rel)) {
            [void]$suspects.Add([pscustomobject]@{
                    File        = $rel
                    WhySuspect  = "Reference HTA legacy; flux principal = Detect-USBControllers.ps1"
                    WhyNotMoved = "Chemin encore dans Unreal.hta"
                })
        }
    }
}

if (-not $QuarantineOnly) {
    $textExtensions = @('.hta', '.ps1', '.js', '.json', '.md', '.html', '.css', '.scss', '.bat', '.cmd', '.xml')
    foreach ($f in $allFiles) {
        if ($textExtensions -notcontains $f.Extension.ToLowerInvariant()) { continue }
        if ($f.FullName -match '\\_cleanup_quarantine\\|\\node_modules\\|\\tools\\nvidia-automation-v2\\.*\\bin\\|\\tools\\nvidia-automation-v2\\.*\\obj\\') { continue }
        try { $before = [System.IO.File]::ReadAllText($f.FullName, [System.Text.UTF8Encoding]::new($false)) } catch { continue }
        if (-not (Test-NeedsEncodingRepair $before)) { continue }
        $after = Repair-TextEncoding $before
        if ($after -eq $before) { continue }
        $rel = $f.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/')
        if (-not $WhatIf) {
            if ($f.Extension -eq '.ps1') {
                $enc = New-Object System.Text.UTF8Encoding $true
            } else {
                $enc = New-Object System.Text.UTF8Encoding $false
            }
            [System.IO.File]::WriteAllText($f.FullName, $after, $enc)
        }
        [void]$encodingFixes.Add([pscustomobject]@{ File = $rel; Note = "Mojibake repare UTF-8" })
    }

    if (-not $WhatIf) {
        $labelsDir = Split-Path $labelsPath -Parent
        New-Item -ItemType Directory -Path $labelsDir -Force | Out-Null
        $labelsContent = @'
/**
 * Labels UI principaux (PurpleBoost / Unreal.hta).
 */
(function (root) {
  var LABELS = {
    nav: { home: "Accueil", devices: "Périphériques", drivers: "Drivers", connection: "Connexion", game: "Jeu", optimization: "Optimisation", sound: "Son", network: "Réseau", system: "Système" },
    hardware: { processor: "Processeur", gpu: "Carte graphique", memory: "Mémoire" },
    status: { optimized: "Optimisé", notOptimized: "Non optimisé", detected: "Détecté", notDetected: "Non détecté", verification: "Vérification" },
    actions: { restore: "Restaurer", boost: "Booster", removeBoost: "Retirer le boost" }
  };
  if (typeof module !== "undefined" && module.exports) { module.exports = LABELS; }
  else { root.UNREAL_LABELS = LABELS; }
})(typeof window !== "undefined" ? window : this);
'@
        [System.IO.File]::WriteAllText($labelsPath, $labelsContent, (New-Object System.Text.UTF8Encoding $false))
        [void]$encodingFixes.Add([pscustomobject]@{ File = "src/constants/labels.js"; Note = "Cree centralisation labels" })
    }
}

$htaPath = Join-Path $ProjectRoot "Unreal.hta"
if (Test-Path $htaPath) {
    $hta = [System.IO.File]::ReadAllText($htaPath, [System.Text.UTF8Encoding]::new($false))
    $bad = [char]0x00C3
    [void]$tests.Add("Mojibake C3 absent: $(if ($hta -notmatch $bad) { 'OK' } else { 'ECHEC' })")
    [void]$tests.Add("Detect-USBControllers.ps1: $(if ($hta -match 'Detect-USBControllers\.ps1') { 'OK' } else { 'ECHEC' })")
    [void]$tests.Add("Apply-ControllerOC.ps1: $(if ($hta -match 'Apply-ControllerOC\.ps1') { 'OK' } else { 'ECHEC' })")
    [void]$tests.Add("runControllerDetect: $(if ($hta -match 'function runControllerDetect') { 'OK' } else { 'ECHEC' })")
    [void]$tests.Add("Label Reseau menu: $(if ($hta -match 'Réseau|reseau') { 'OK' } else { 'ECHEC' })")
}

$csproj = Join-Path $ProjectRoot "PurpleBoost.csproj"
if (Test-Path $csproj) {
    try {
        & dotnet build $csproj -v q 2>&1 | Out-Null
        [void]$tests.Add("dotnet build: $(if ($LASTEXITCODE -eq 0) { 'OK' } else { 'ECHEC' })")
    } catch {
        [void]$tests.Add("dotnet build: skip ($($_.Exception.Message))")
    }
}

$md = "# Audit nettoyage projet Unreal / PurpleBoost`n`n"
$md += "## Resume`n"
$md += "- Fichiers scannes : $scannedCount`n"
$md += "- Deplaces quarantaine : $($moved.Count)`n"
$md += "- Suspects non touches : $($suspects.Count)`n"
$md += "- Corrections encodage : $($encodingFixes.Count)`n"
$md += "- Date : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n`n"
$md += "## Fichiers deplaces en quarantaine`n| Fichier original | Destination | Raison | Risque |`n|---|---|---|---|`n"
foreach ($m in $moved) { $md += "| $($m.Original) | $($m.Destination) | $($m.Reason) | $($m.Risk) |`n" }
if ($moved.Count -eq 0) { $md += "| (aucun) | - | - | - |`n" }
$md += "`n## Fichiers conserves volontairement`n| Fichier | Raison |`n|---|---|`n"
foreach ($k in $kept) { $md += "| $($k.File) | $($k.Reason) |`n" }
$md += "| Unreal.hta | Application principale |`n| Scripts/Devices/Apply-ControllerOC.ps1 | Apply Hz |`n| Scripts/Devices/Detect-USBControllers.ps1 | Detection PnP |`n"
$md += "`n## Fichiers suspects non touches`n| Fichier | Suspect | Non deplace |`n|---|---|---|`n"
foreach ($s in $suspects) { $md += "| $($s.File) | $($s.WhySuspect) | $($s.WhyNotMoved) |`n" }
$md += "`n## Corrections encodage`n| Fichier | Note |`n|---|---|`n"
foreach ($e in $encodingFixes) { $md += "| $($e.File) | $($e.Note) |`n" }
$md += "`n## Tests apres nettoyage`n"
foreach ($t in $tests) { $md += "- $t`n" }
$md += "`n_Quarantaine: _cleanup_quarantine/ — pas de suppression definitive._`n"

if (-not $WhatIf) {
    [System.IO.File]::WriteAllText($auditPath, $md, (New-Object System.Text.UTF8Encoding $false))
}
Write-Output "Done scanned=$scannedCount moved=$($moved.Count) encoding=$($encodingFixes.Count)"
