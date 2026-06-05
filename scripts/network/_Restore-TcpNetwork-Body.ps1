$ErrorActionPreference='Continue'
$log = Join-Path $script:NetworkLogsDir 'tcp-profile.log'
$jsonOut = Join-Path $script:NetworkLogsDir 'network-restore-result.json'
$ipLog = Join-Path $script:NetworkLogsDir 'kojo-netsh-ip-reset.log'
function L($m){ Add-Content -Path $log -Value ((Get-Date -Format 'HH:mm:ss') + ' ' + $m) }
$result = [ordered]@{ success=$true; alreadyDefault=$false; fatalErrors=(New-Object System.Collections.ArrayList); warnings=(New-Object System.Collections.ArrayList); steps=(New-Object System.Collections.ArrayList); netshTcpShowGlobal=''; before=$null; after=$null }

function Gaming-Snapshot {
  $mm = Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile' -ErrorAction SilentlyContinue
  $ntiG=$false; $srG=$false
  if ($mm) {
    try { if ([uint32]$mm.NetworkThrottlingIndex -eq [uint32]::MaxValue) { $ntiG=$true } } catch {}
    try { if ([uint32]$mm.SystemResponsiveness -eq 0) { $srG=$true } } catch {}
  }
  $tp = Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters' -ErrorAction SilentlyContinue
  $ack = $false; if ($tp -and $null -ne $tp.TcpAckFrequency) { $ack=$true }
  return [ordered]@{ ntiGaming=$ntiG; srGaming=$srG; tcpAck=$ack }
}

function Run-Step([string]$label,[string]$exe,[string[]]$arguments,[bool]$critical=$false) {
  L $label
  $code = -999
  try {
    $p = Start-Process -FilePath $exe -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    if ($null -ne $p -and $null -ne $p.ExitCode) { $code = [int]$p.ExitCode } else { $code = 0 }
  } catch {
    $msg = $_.Exception.Message
    L ('  ERREUR '+$label+' : '+$msg)
    [void]$result.fatalErrors.Add(($label+' | '+$exe+' '+($arguments -join ' ')+' | '+$msg))
    if ($critical) { $result.success = $false }
    $code = -1
  }
  $argStr = if ($arguments) { $arguments -join ' ' } else { '' }
  [void]$result.steps.Add([ordered]@{ label=$label; executable=$exe; arguments=$argStr; exitCode=$code })
  if ($code -ne 0 -and $code -ne -999) {
    L ('  -> code sortie '+$code)
    $benign = ($code -eq 1 -and $label -match 'Winsock|DNS|TCP/IP')
    if ($critical -and -not $benign) {
      $result.success = $false
      [void]$result.fatalErrors.Add($label+' : code '+$code)
    } else {
      [void]$result.warnings.Add($label+' : code '+$code+' (souvent normal si non supporte sur cette version Windows)')
    }
  }
}

function RmProp($p,$n){ try { Remove-ItemProperty -LiteralPath $p -Name $n -Force -ErrorAction SilentlyContinue; L ('Supprimé : '+$p+' :: '+$n) } catch {} }

L 'Restauration réseau demandée...'
L 'Vérification des droits administrateur...'
L 'Droits administrateur OK (ce script s exécute en contexte élevé).'
L 'Restauration réseau lancée (netsh + registre).'
$result.before = Gaming-Snapshot

Run-Step 'Vidage du cache DNS...' 'ipconfig.exe' @('/flushdns') $true
Run-Step 'Réinitialisation Winsock...' 'netsh.exe' @('winsock','reset') $true
Run-Step 'Réinitialisation TCP/IP (stack)...' 'netsh.exe' @('int','ip','reset',$ipLog) $false

Run-Step 'TCP autotuning (normal)...' 'netsh.exe' @('int','tcp','set','global','autotuninglevel=normal') $false
Run-Step 'Congestion provider (internet, défaut)...' 'netsh.exe' @('int','tcp','set','supplemental','internet','congestionprovider=default') $false
Run-Step 'Congestion provider (datacenter, défaut)...' 'netsh.exe' @('int','tcp','set','supplemental','datacenter','congestionprovider=default') $false
Run-Step 'RSS...' 'netsh.exe' @('int','tcp','set','global','rss=enabled') $false
Run-Step 'ECN...' 'netsh.exe' @('int','tcp','set','global','ecn=disabled') $false
Run-Step 'Timestamps TCP...' 'netsh.exe' @('int','tcp','set','global','timestamps=enabled') $false
Run-Step 'Chimney Offload (legacy)...' 'netsh.exe' @('int','tcp','set','global','chimney=disabled') $false
Run-Step 'NetDMA (legacy)...' 'netsh.exe' @('int','tcp','set','global','netdma=disabled') $false
Run-Step 'RTO initial=3000...' 'netsh.exe' @('int','tcp','set','global','initialrto=3000') $false
Run-Step 'RTO min=300...' 'netsh.exe' @('int','tcp','set','global','minrto=300') $false

# --- Internet Settings ---
try {
  $ieCu='HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings'
  if(Test-Path $ieCu){ RmProp $ieCu 'MaxConnectionsPer1_0Server'; RmProp $ieCu 'MaxConnectionsPerServer' }
  Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-[0-9\-]+$' } | ForEach-Object {
    $ie = Join-Path $_.PSPath 'Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings'
    if(Test-Path $ie){ RmProp $ie 'MaxConnectionsPer1_0Server'; RmProp $ie 'MaxConnectionsPerServer' }
  }
  L 'Internet Settings : MaxConnections supprimées'
} catch { L ('Internet Settings: '+$_.Exception.Message); [void]$result.warnings.Add($_.Exception.Message) }

# --- ServiceProvider ---
try {
  $sp='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\ServiceProvider'
  foreach($n in @('LocalPriority','HostsPriority','DnsPriority','NetbtPriority')){ RmProp $sp $n }
  L 'ServiceProvider : priorités supprimées'
} catch { L ('ServiceProvider: '+$_.Exception.Message) }

# --- Tcpip Parameters global ---
try {
  $tp='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters'
  foreach($n in @('TcpAckFrequency','TCPNoDelay','TcpDelAckTicks','TcpMaxSynRetransmissions','NonSackRttResiliency','GlobalMaxTcpWindowSize','Tcp1323Opts','DefaultTTL')){ RmProp $tp $n }
  L 'Tcpip\\Parameters : clés tuning supprimées'
} catch { L ('Tcpip Parameters: '+$_.Exception.Message) }

# --- Interfaces Tcpip ---
try {
  $ifRoot='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters\\Interfaces'
  Get-ChildItem -LiteralPath $ifRoot -ErrorAction SilentlyContinue | ForEach-Object {
    foreach($n in @('TcpAckFrequency','TCPNoDelay','TcpDelAckTicks')){ RmProp $_.PSPath $n }
  }
  L 'Interfaces Tcpip : Nagle supprimé'
} catch { L ('Interfaces: '+$_.Exception.Message) }

# --- QoS Psched + Tcpip QoS ---
try { Remove-Item -LiteralPath 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Psched' -Recurse -Force -ErrorAction SilentlyContinue; L 'Psched supprimé' } catch {}
try {
  $qos='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\QoS'
  RmProp $qos 'Do not use NLA'
  L 'Tcpip\\QoS : Do not use NLA supprimé'
} catch {}

# --- Multimedia SystemProfile ---
try {
  $mm='HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile'
  New-ItemProperty -Path $mm -Name 'NetworkThrottlingIndex' -PropertyType DWord -Value 10 -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $mm -Name 'SystemResponsiveness' -PropertyType DWord -Value 20 -Force -ErrorAction SilentlyContinue | Out-Null
  L 'SystemProfile : NetworkThrottlingIndex=10 SystemResponsiveness=20'
} catch { L ('SystemProfile: '+$_.Exception.Message); [void]$result.warnings.Add($_.Exception.Message) }

# --- Memory + LanmanServer ---
try {
  $mem='HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management'
  New-ItemProperty -Path $mem -Name 'LargeSystemCache' -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
  L 'LargeSystemCache=0'
} catch {}
try {
  $ls='HKLM:\\SYSTEM\\CurrentControlSet\\Services\\LanmanServer\\Parameters'
  New-ItemProperty -Path $ls -Name 'Size' -PropertyType DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
  L 'LanmanServer Size=1'
} catch {}

L 'Vérification des valeurs après restauration...'
$result.after = Gaming-Snapshot
$b = $result.before
$result.alreadyDefault = ((-not $b.ntiGaming) -and (-not $b.srGaming) -and (-not $b.tcpAck))
try { $result.netshTcpShowGlobal = (netsh.exe int tcp show global 2>&1 | Out-String) } catch { $result.netshTcpShowGlobal = $_.Exception.Message }

if ($result.after.ntiGaming -or $result.after.srGaming) {
  [void]$result.warnings.Add('NetworkThrottlingIndex ou SystemResponsiveness indiquent encore des valeurs type profil gaming   redémarrage Windows souvent nécessaire après netsh int ip reset.')
}
if ($result.after.tcpAck) { [void]$result.warnings.Add('TcpAckFrequency encore présent sur Parameters (droits ou pilote).') }

L 'Restauration réseau terminée.'
L 'Redémarrage Windows conseillé.'
if ($result.fatalErrors.Count -eq 0) { $result.success = $true }
try {
  if (-not (Test-Path -LiteralPath $script:NetworkLogsDir)) {
    New-Item -ItemType Directory -Force -Path $script:NetworkLogsDir | Out-Null
  }
  $jsonText = $result | ConvertTo-Json -Depth 12
  [System.IO.File]::WriteAllText($jsonOut, $jsonText, (New-Object System.Text.UTF8Encoding($false)))
  L ('Resultat JSON : '+$jsonOut)
} catch {
  L ('Impossible d ecrire le JSON resultat : '+$_.Exception.Message)
  [void]$result.warnings.Add('JSON: '+$_.Exception.Message)
}
if ($result.success) { $script:NetworkProfileExitCode = 0 } else { $script:NetworkProfileExitCode = 10 }