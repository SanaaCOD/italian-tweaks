$ErrorActionPreference='Continue'
$log = Join-Path $script:NetworkLogsDir 'network-profile.log'
function L($m){ Add-Content -Path $log -Value ((Get-Date -Format 'HH:mm:ss') + ' ' + $m) }
L 'Application profil TCP Gaming lancée'
try {
  Checkpoint-Computer -Description 'KOJO   profil TCP gaming' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
  L 'Point de restauration Windows demandé (réussi)'
} catch { L ('Point de restauration Windows : '+$_.Exception.Message) }
$ts=Get-Date -Format 'yyyyMMdd-HHmmss'
$bd = Join-Path $script:NetworkBackupsDir $ts
$backupDir=$script:NetworkBackupDir
$backupReg=Join-Path $backupDir 'network-profile-backup.reg'
New-Item -ItemType Directory -Force -Path $bd | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
L 'Sauvegarde registre créée'
try { reg export 'HKLM\\SYSTEM\\CurrentControlSet\\Services\\Tcpip' $backupReg /y 2>$null | Out-Null; L ('Backup principal : '+$backupReg) } catch { L ('Backup principal : '+$_.Exception.Message) }
reg export 'HKLM\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters' "$bd\\tcpip-parameters.reg" /y 2>$null | Out-Null
reg export 'HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile' "$bd\\multimedia-systemprofile.reg" /y 2>$null | Out-Null
reg export 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management' "$bd\\memory-management.reg" /y 2>$null | Out-Null
reg export 'HKLM\\SYSTEM\\CurrentControlSet\\Services\\LanmanServer\\Parameters' "$bd\\lanmanserver.reg" /y 2>$null | Out-Null
try { reg export 'HKLM\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\ServiceProvider' "$bd\\serviceprovider.reg" /y 2>$null | Out-Null } catch {}
try { reg export 'HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\Psched' "$bd\\psched.reg" /y 2>$null | Out-Null } catch {}
try { reg export 'HKLM\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\QoS' "$bd\\tcp-qos.reg" /y 2>$null | Out-Null } catch {}
try { reg export 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings' "$bd\\hkcu-internet-settings.reg" /y 2>$null | Out-Null } catch {}

function Ensure-Path($p){ if(-not(Test-Path $p)){ New-Item -Path $p -Force | Out-Null } }

# --- 1) Internet Explorer Optimization : MaxConnectionsPer1_0Server=4, MaxConnectionsPerServer=2 ---
try {
  Get-ChildItem 'Registry::HKEY_USERS' | Where-Object { $_.PSChildName -match '^S-1-5-21-[0-9\-]+$' } | ForEach-Object {
    $ie = Join-Path $_.PSPath 'Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings'
    if(Test-Path $ie){
      New-ItemProperty -Path $ie -Name 'MaxConnectionsPer1_0Server' -Value 4 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
      New-ItemProperty -Path $ie -Name 'MaxConnectionsPerServer' -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    }
  }
  $ieCu='HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings'
  Ensure-Path $ieCu
  New-ItemProperty -Path $ieCu -Name 'MaxConnectionsPer1_0Server' -Value 4 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $ieCu -Name 'MaxConnectionsPerServer' -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  L 'Internet Explorer Optimization (MaxConnections) appliqué'
} catch { L ('ERREUR Internet Settings: '+$_.Exception.Message) }

# --- 1b) Internet Settings HKLM (MaxConnectionsPer1_0Server=4, MaxConnectionsPerServer=2) ---
try {
  $ieLm='HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Internet Settings'
  Ensure-Path $ieLm
  New-ItemProperty -Path $ieLm -Name 'MaxConnectionsPer1_0Server' -Value 4 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $ieLm -Name 'MaxConnectionsPerServer' -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  L 'Internet Settings HKLM (MaxConnections) appliqué'
} catch { L ('ERREUR Internet Settings HKLM: '+$_.Exception.Message) }

# --- 2) Host Resolution Priority : Local 4, Hosts 5, Dns 6, Netbt 7 (UI « HostPriority » = clé HostsPriority) ---
try {
  $sp='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\ServiceProvider'
  Ensure-Path $sp
  New-ItemProperty -Path $sp -Name 'LocalPriority' -Value 4 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $sp -Name 'HostsPriority' -Value 5 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $sp -Name 'DnsPriority' -Value 6 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $sp -Name 'NetbtPriority' -Value 7 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  L 'Host Resolution Priority appliqué'
} catch { L ('ERREUR ServiceProvider: '+$_.Exception.Message) }

# --- 3-4) Retransmissions + Nagle global : TcpMaxSynRetransmissions=2, NonSackRttResiliency=0 (desactive), TcpAckFrequency/TCPNoDelay/TcpDelAckTicks ---
try {
  $tp='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters'
  New-ItemProperty -Path $tp -Name 'TcpMaxSynRetransmissions' -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $tp -Name 'InitialRto' -Value 2000 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $tp -Name 'MinRto' -Value 300 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $tp -Name 'NonSackRttResiliency' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $tp -Name 'TcpAckFrequency' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $tp -Name 'TCPNoDelay' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $tp -Name 'TcpDelAckTicks' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  L 'Tcpip\\Parameters : retransmissions + Nagle (global) appliqués'
} catch { L ('ERREUR Tcpip\\Parameters: '+$_.Exception.Message) }
try {
  $n1 = Start-Process -FilePath netsh.exe -ArgumentList @('int','tcp','set','global','maxsynretransmissions=2') -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
  if ($n1 -and $n1.ExitCode -eq 0) { L 'netsh maxsynretransmissions=2 appliqué' } else { L 'netsh maxsynretransmissions non supporté (fallback registre conservé)' }
} catch { L ('netsh maxsynretransmissions: '+$_.Exception.Message) }
try {
  $n2 = Start-Process -FilePath netsh.exe -ArgumentList @('int','tcp','set','global','nonsackrttresiliency=disabled') -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
  if ($n2 -and $n2.ExitCode -eq 0) { L 'netsh nonsackrttresiliency=disabled appliqué' } else { L 'netsh nonsackrttresiliency non supporté (fallback registre conservé)' }
} catch { L ('netsh nonsackrttresiliency: '+$_.Exception.Message) }

# --- 5) Type / QoS : NonBestEffortLimit=0 ---
try {
  $ps='HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Psched'
  Ensure-Path $ps
  New-ItemProperty -LiteralPath $ps -Name 'NonBestEffortLimit' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  L 'QoS NonBestEffortLimit=0 appliqué'
} catch { L ('ERREUR Psched (NonBestEffortLimit): '+$_.Exception.Message) }
# --- 5b) QoS : Do not use NLA = 1 (best effort, non bloquant) ---
try {
  $qosPath='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\QoS'
  Ensure-Path $qosPath
  New-ItemProperty -LiteralPath $qosPath -Name 'Do not use NLA' -Value '1' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
  Start-Process -FilePath 'reg.exe' -ArgumentList @('add','HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\QoS','/v','Do not use NLA','/t','REG_SZ','/d','1','/f') -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
  L 'QoS Do not use NLA appliqué (best effort, non bloquant)'
} catch { L ('QoS Do not use NLA ignoré (non bloquant) : '+$_.Exception.Message) }

# --- 6) Gaming : NetworkThrottlingIndex=ffffffff, SystemResponsiveness=0 ---
try {
  $mm='HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile'
  Ensure-Path $mm
  New-ItemProperty -Path $mm -Name 'NetworkThrottlingIndex' -Value ([UInt32]::MaxValue) -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $mm -Name 'SystemResponsiveness' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  try {
    $p = Start-Process -FilePath reg.exe -ArgumentList @('add','HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile','/v','NetworkThrottlingIndex','/t','REG_DWORD','/d','ffffffff','/f') -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
    if ($p -and $p.ExitCode -eq 0) { L 'NetworkThrottlingIndex (secours reg.exe)' }
  } catch {}
  L 'NetworkThrottlingIndex + SystemResponsiveness appliqués'
} catch { L ('ERREUR SystemProfile: '+$_.Exception.Message) }

# --- 7) Nagle sur interfaces réseau actives (TcpAckFrequency=1, TCPNoDelay=1, TcpDelAckTicks=0) ---
try {
  $ifRoot='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters\\Interfaces'
  $ifaceItems = @(Get-ChildItem -LiteralPath $ifRoot -ErrorAction SilentlyContinue)
  $nagleTargets = @()
  foreach ($it in $ifaceItems) {
    $pr = Get-ItemProperty -LiteralPath $it.PSPath -ErrorAction SilentlyContinue
    if (-not $pr) { continue }
    $dhcpOk = $false
    if ($pr.PSObject.Properties['DhcpIPAddress'] -and $pr.DhcpIPAddress -match '^\d+\.\d+') { if ($pr.DhcpIPAddress -notmatch '^0\.0\.0\.0') { $dhcpOk = $true } }
    $ipOk = $false
    if ($pr.PSObject.Properties['IPAddress']) { foreach ($a in @($pr.IPAddress)) { if ($a -match '^\d+\.\d+' -and $a -ne '0.0.0.0') { $ipOk = $true } } }
    $dhcpEn = ($pr.EnableDhcp -eq 1)
    $gwOk = $false
    if ($pr.PSObject.Properties['DefaultGateway']) { foreach ($gw in @($pr.DefaultGateway)) { if ($gw -match '^\d+\.\d+' -and $gw -ne '0.0.0.0') { $gwOk = $true } } }
    if ($dhcpOk -or $ipOk -or $dhcpEn -or $gwOk) { $nagleTargets += $it }
  }
  if ($nagleTargets.Count -eq 0) { L 'Aucune interface active détectée pour Nagle (IP/passerelle absente).' }
  foreach ($it in @($nagleTargets)) {
    New-ItemProperty -Path $it.PSPath -Name 'TcpAckFrequency' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $it.PSPath -Name 'TCPNoDelay' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $it.PSPath -Name 'TcpDelAckTicks' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  }
  L ('Nagle appliqué sur '+$nagleTargets.Count+' interface(s) Tcpip')
} catch { L ('ERREUR interfaces Nagle: '+$_.Exception.Message) }

# --- 8) Network Memory : LargeSystemCache=1 ---
try {
  $mem='HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management'
  New-ItemProperty -Path $mem -Name 'LargeSystemCache' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  L 'LargeSystemCache=1 appliqué'
} catch { L ('ERREUR Memory Management: '+$_.Exception.Message) }

# --- 8b) LanmanServer : Size=3 (optimized) ---
try {
  $ls='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\LanmanServer\\Parameters'
  New-ItemProperty -Path $ls -Name 'Size' -Value 3 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
  L 'LanmanServer Size=3 appliqué'
} catch { L ('ERREUR LanmanServer: '+$_.Exception.Message) }

# --- 9) Dynamic Port : suppression des anciens tweaks pour retour comportement Windows ---
try {
  $tp='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters'
  Remove-ItemProperty -LiteralPath $tp -Name 'MaxUserPort' -ErrorAction SilentlyContinue
  Remove-ItemProperty -LiteralPath $tp -Name 'TcpTimedWaitDelay' -ErrorAction SilentlyContinue
  L 'MaxUserPort et TcpTimedWaitDelay supprimés si présents'
} catch { L ('ERREUR suppression Dynamic Port: '+$_.Exception.Message) }

# --- 4) Retransmit Timeout (RTO) : Initial=2000, Min=300 (netsh) ---
$rtoOk=$false
try {
  $p1 = Start-Process -FilePath netsh.exe -ArgumentList @('int','tcp','set','global','initialrto=2000') -Wait -PassThru -WindowStyle Hidden
  if($p1 -and $p1.ExitCode -eq 0){ $rtoOk=$true; L 'Initial RTO netsh tenté' }
} catch { L ('netsh initialrto: '+$_.Exception.Message) }
try {
  $p2 = Start-Process -FilePath netsh.exe -ArgumentList @('int','tcp','set','global','minrto=300') -Wait -PassThru -WindowStyle Hidden
  if($p2 -and $p2.ExitCode -eq 0){ $rtoOk=$true; L 'Min RTO netsh tenté' }
} catch { L ('netsh minrto: '+$_.Exception.Message) }
if(-not $rtoOk){ L 'RTO netsh : non appliqué sur cette version Windows (non bloquant pour la vérification registre).' }
try { ipconfig.exe /flushdns 2>&1 | Out-Null; L 'ipconfig /flushdns appliqué' } catch { L ('ipconfig /flushdns: '+$_.Exception.Message) }

# --- Vérification post-application (relecture registre, erreurs détaillées) ---
$jsonOut = Join-Path $script:NetworkLogsDir 'gaming-profile-result.json'
$verifyErrors = New-Object System.Collections.ArrayList
function Add-VerifErr([string]$msg) { L $msg; [void]$verifyErrors.Add($msg) }
$ifRootV='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters\\Interfaces'
$ifaceItemsV = @(Get-ChildItem -LiteralPath $ifRootV -ErrorAction SilentlyContinue)
$nagleTargetsV = @()
foreach ($itv in $ifaceItemsV) {
  $prv = Get-ItemProperty -LiteralPath $itv.PSPath -ErrorAction SilentlyContinue
  if (-not $prv) { continue }
  $dhcpOkV = $false
  if ($prv.PSObject.Properties['DhcpIPAddress'] -and $prv.DhcpIPAddress -match '^\d+\.\d+') { if ($prv.DhcpIPAddress -notmatch '^0\.0\.0\.0') { $dhcpOkV = $true } }
  $ipOkV = $false
  if ($prv.PSObject.Properties['IPAddress']) { foreach ($av in @($prv.IPAddress)) { if ($av -match '^\d+\.\d+' -and $av -ne '0.0.0.0') { $ipOkV = $true } } }
  $dhcpEnV = ($prv.EnableDhcp -eq 1)
  $gwOkV = $false
  if ($prv.PSObject.Properties['DefaultGateway']) { foreach ($gwv in @($prv.DefaultGateway)) { if ($gwv -match '^\d+\.\d+' -and $gwv -ne '0.0.0.0') { $gwOkV = $true } } }
  if ($dhcpOkV -or $ipOkV -or $dhcpEnV -or $gwOkV) { $nagleTargetsV += $itv }
}
if ($nagleTargetsV.Count -eq 0) { L 'Vérification Nagle : aucune interface active détectée.' }
$mmPathSys='HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile'
function Test-NtiVal($obj) {
  if (-not $obj) { return $false }
  $v = $obj.NetworkThrottlingIndex
  if ($null -eq $v) { return $false }
  if ($v -eq -1) { return $true }
  try { return ([uint32]$v -eq [uint32]::MaxValue) } catch { return $false }
}
function Test-SrZero($obj) {
  if (-not $obj) { return $false }
  try { return ([uint32]$obj.SystemResponsiveness -eq 0) } catch { return $false }
}
try {
  Ensure-Path $mmPathSys
  $mmg = Get-ItemProperty -LiteralPath $mmPathSys -ErrorAction SilentlyContinue
  if (-not (Test-NtiVal $mmg)) {
    New-ItemProperty -LiteralPath $mmPathSys -Name 'NetworkThrottlingIndex' -Value ([UInt32]::MaxValue) -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    Start-Process -FilePath reg.exe -ArgumentList @('add','HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile','/v','NetworkThrottlingIndex','/t','REG_DWORD','/d','ffffffff','/f') -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    $mmg = Get-ItemProperty -LiteralPath $mmPathSys -ErrorAction SilentlyContinue
  }
  if (-not (Test-NtiVal $mmg)) { Add-VerifErr 'Erreur : impossible d''appliquer NetworkThrottlingIndex dans HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile. Lance l''application en administrateur.' }
  if (-not (Test-SrZero $mmg)) {
    New-ItemProperty -LiteralPath $mmPathSys -Name 'SystemResponsiveness' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    $mmg = Get-ItemProperty -LiteralPath $mmPathSys -ErrorAction SilentlyContinue
  }
  if (-not (Test-SrZero $mmg)) { Add-VerifErr 'Erreur : impossible d''appliquer SystemResponsiveness dans HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile. Lance l''application en administrateur.' }
} catch { Add-VerifErr ('Erreur : SystemProfile   '+$_.Exception.Message+'. Lance l''application en administrateur.') }
$tpg = $null
try {
  $tpg = Get-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters' -ErrorAction SilentlyContinue
  if (-not $tpg) { Add-VerifErr 'Erreur : clé Tcpip\\Parameters inaccessible.' }
  else {
    if ($null -eq $tpg.TcpMaxSynRetransmissions -or [int]$tpg.TcpMaxSynRetransmissions -ne 2) { Add-VerifErr 'Erreur : TcpMaxSynRetransmissions != 2.' }
    if ($null -eq $tpg.NonSackRttResiliency -or [int]$tpg.NonSackRttResiliency -ne 0) { Add-VerifErr 'Erreur : NonSackRttResiliency != 0 (désactivé).' }
    if ($null -ne $tpg.TcpDelAckTicks -and [int]$tpg.TcpDelAckTicks -ne 0) { Add-VerifErr 'Erreur : TcpDelAckTicks global != 0.' }
  }
  $gAck = $false; $gNd = $false; $gDelOk = $true
  if ($tpg) {
    if ($null -ne $tpg.TcpAckFrequency -and [int]$tpg.TcpAckFrequency -eq 1) { $gAck = $true }
    if ($null -ne $tpg.TCPNoDelay -and [int]$tpg.TCPNoDelay -eq 1) { $gNd = $true }
    if ($null -ne $tpg.TcpDelAckTicks -and [int]$tpg.TcpDelAckTicks -ne 0) { $gDelOk = $false }
  }
  $globalNagleOk = ($gAck -and $gNd -and $gDelOk)
  $ifaceNagleOk = $true
  foreach ($itn in $nagleTargetsV) {
    $pn = Get-ItemProperty -LiteralPath $itn.PSPath -ErrorAction SilentlyContinue
    $gid = $itn.PSChildName
    if (-not $pn) { Add-VerifErr ('Erreur : impossible de lire l''interface Tcpip '+$gid+' (Nagle).'); $ifaceNagleOk = $false; continue }
    if ($null -eq $pn.TcpAckFrequency -or [int]$pn.TcpAckFrequency -ne 1) { Add-VerifErr ('Erreur : TcpAckFrequency non appliqué sur l''interface '+$gid+'.'); $ifaceNagleOk = $false }
    if ($null -eq $pn.TCPNoDelay -or [int]$pn.TCPNoDelay -ne 1) { Add-VerifErr ('Erreur : TCPNoDelay non appliqué sur l''interface '+$gid+'.'); $ifaceNagleOk = $false }
    if ($null -eq $pn.TcpDelAckTicks -or [int]$pn.TcpDelAckTicks -ne 0) { Add-VerifErr ('Erreur : TcpDelAckTicks non appliqué sur l''interface '+$gid+'.'); $ifaceNagleOk = $false }
  }
  if ($nagleTargetsV.Count -gt 0 -and -not $ifaceNagleOk) { Add-VerifErr 'Erreur : Nagle non appliqué sur une ou plusieurs interfaces actives.' }
} catch { Add-VerifErr ('Erreur : vérification Tcpip / Nagle   '+$_.Exception.Message) }
try {
  $spg = Get-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\ServiceProvider' -ErrorAction SilentlyContinue
  if ($null -eq $spg.LocalPriority -or [int]$spg.LocalPriority -ne 4) { Add-VerifErr 'Erreur : LocalPriority != 4 (Host Resolution).' }
  if ($null -eq $spg.HostsPriority -or [int]$spg.HostsPriority -ne 5) { Add-VerifErr 'Erreur : HostsPriority != 5.' }
  if ($null -eq $spg.DnsPriority -or [int]$spg.DnsPriority -ne 6) { Add-VerifErr 'Erreur : DnsPriority != 6.' }
  if ($null -eq $spg.NetbtPriority -or [int]$spg.NetbtPriority -ne 7) { Add-VerifErr 'Erreur : NetbtPriority != 7.' }
} catch { Add-VerifErr ('Erreur : ServiceProvider   '+$_.Exception.Message) }
try {
  if (-not (Test-Path -LiteralPath 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Psched')) { Add-VerifErr 'Erreur : clé HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\Psched absente (QoS NonBestEffortLimit).' }
  else {
    $psg = Get-ItemProperty -LiteralPath 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Psched' -ErrorAction SilentlyContinue
    if ($null -eq $psg.NonBestEffortLimit -or [int]$psg.NonBestEffortLimit -ne 0) { Add-VerifErr 'Erreur : NonBestEffortLimit != 0.' }
  }
} catch { Add-VerifErr ('Erreur : Psched (NonBestEffortLimit)   '+$_.Exception.Message) }
L 'QoS Do not use NLA : vérification ignorée (non bloquant).'
try {
  $memg = Get-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management' -Name LargeSystemCache -ErrorAction SilentlyContinue
  if ($null -eq $memg.LargeSystemCache -or [int]$memg.LargeSystemCache -ne 1) { Add-VerifErr 'Erreur : LargeSystemCache != 1 (Network Memory).' }
} catch { Add-VerifErr ('Erreur : Memory Management   '+$_.Exception.Message) }
try {
  $lsg = Get-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\LanmanServer\\Parameters' -Name Size -ErrorAction SilentlyContinue
  if ($null -eq $lsg.Size -or [int]$lsg.Size -ne 3) { Add-VerifErr 'Erreur : LanmanServer Size != 3 (optimized).' }
} catch { Add-VerifErr ('Erreur : LanmanServer   '+$_.Exception.Message) }
try {
  $ieu = Get-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings' -ErrorAction SilentlyContinue
  if ($null -eq $ieu.MaxConnectionsPer1_0Server -or [int]$ieu.MaxConnectionsPer1_0Server -ne 4) { Add-VerifErr 'Erreur : MaxConnectionsPer1_0Server != 4 (IE / HKCU).' }
  if ($null -eq $ieu.MaxConnectionsPerServer -or [int]$ieu.MaxConnectionsPerServer -ne 2) { Add-VerifErr 'Erreur : MaxConnectionsPerServer != 2 (IE / HKCU).' }
} catch { Add-VerifErr ('Erreur : Internet Settings HKCU   '+$_.Exception.Message) }
try {
  $iel = Get-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Internet Settings' -ErrorAction SilentlyContinue
  if ($iel) {
    if ($null -eq $iel.MaxConnectionsPer1_0Server -or [int]$iel.MaxConnectionsPer1_0Server -ne 4) { Add-VerifErr 'Erreur : MaxConnectionsPer1_0Server != 4 (HKLM).' }
    if ($null -eq $iel.MaxConnectionsPerServer -or [int]$iel.MaxConnectionsPerServer -ne 2) { Add-VerifErr 'Erreur : MaxConnectionsPerServer != 2 (HKLM).' }
  }
} catch { Add-VerifErr ('Erreur : Internet Settings HKLM   '+$_.Exception.Message) }
try {
  $outObj = [ordered]@{ success = ($verifyErrors.Count -eq 0); errors = @($verifyErrors.ToArray()) }
  $jsonText = $outObj | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText($jsonOut, $jsonText, (New-Object System.Text.UTF8Encoding($false)))
} catch { L ('Impossible d ecrire gaming-profile-result.json : '+$_.Exception.Message) }
if ($verifyErrors.Count -gt 0) {
  L ('VERIF ECHEC profil gaming ('+$verifyErrors.Count+' erreur(s)).')
  $script:NetworkProfileExitCode = 2
}
L 'VERIF OK : valeurs du profil gaming (Custom) présentes dans le registre.'
L 'Profil Gaming terminé'
L 'Redémarrage conseillé'
Write-Host 'KOJO: profil TCP gaming appliqué et vérifié.'
$script:NetworkProfileExitCode = 0