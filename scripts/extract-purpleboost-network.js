/**
 * Extrait buildPsTcpGamingProfile / buildPsTcpRestoreNetwork depuis Unreal.hta (PurpleBoost).
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const htaPath = path.join(__dirname, '..', '_purpleboost_extract', 'PurpleBoost-main', 'Unreal.hta');
const outDir = path.join(__dirname, 'network');

function extractFunctionBody(src, name) {
  const start = src.indexOf(`function ${name}()`);
  if (start < 0) throw new Error(`Function ${name} not found`);
  let i = src.indexOf('{', start);
  let depth = 0;
  for (; i < src.length; i++) {
    const ch = src[i];
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) {
        return src.slice(start, i + 1);
      }
    }
  }
  throw new Error(`Unclosed function ${name}`);
}

function evalHtaFunction(src, name) {
  const UNREAL_LOGS = 'C:\\ProgramData\\Kojo\\Logs';
  const body = extractFunctionBody(src, name);
  const ctx = {
    UNREAL_LOGS,
    console
  };
  vm.createContext(ctx);
  vm.runInContext(`${body}; ${name};`, ctx);
  return ctx[name]();
}

function toPs1Header() {
  return `#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\\_common\\Kojo.Json.ps1')
. (Join-Path $PSScriptRoot '_Network-Paths.ps1')
Initialize-NetworkPaths -LogDir $LogDir

`;
}

function adaptPurplePs(psText) {
  let s = psText
    .replace(/C:\\\\ProgramData\\\\Unreal\\\\logs/gi, 'KOJO_LOGS')
    .replace(/C:\\\\ProgramData\\\\Unreal\\\\Logs/gi, 'KOJO_LOGS')
    .replace(/C:\\\\ProgramData\\\\Unreal\\\\Backups/gi, 'KOJO_BACKUPS')
    .replace(/C:\\\\ProgramData\\\\Unreal\\\\backup/gi, 'KOJO_BACKUP')
    .replace(/C:\\\\ProgramData\\\\Unreal\\\\Scripts/gi, 'KOJO_SCRIPTS')
    .replace(/C:\\\\ProgramData\\\\Unreal/gi, 'KOJO_ROOT')
    .replace(/UNREAL/g, 'KOJO')
    .replace(/unreal-netsh-ip-reset/gi, 'kojo-netsh-ip-reset');

  s = s.replace(/\$log='KOJO_LOGS\\\\([^']+)'/g, "$log = Join-Path $script:NetworkLogsDir '$1'");
  s = s.replace(/\$jsonOut='KOJO_LOGS\\\\([^']+)'/g, "$jsonOut = Join-Path $script:NetworkLogsDir '$1'");
  s = s.replace(/\$ipLog='KOJO_LOGS\\\\([^']+)'/g, "$ipLog = Join-Path $script:NetworkLogsDir '$1'");
  s = s.replace(/'KOJO_LOGS\\\\([^']+)'/g, "(Join-Path $script:NetworkLogsDir '$1')");
  s = s.replace(/\$bd='KOJO_BACKUPS\\\\'/g, '$bd = Join-Path $script:NetworkBackupsDir ');
  s = s.replace(/\$bd = Join-Path \$script:NetworkBackupsDir \+\$ts/g, '$bd = Join-Path $script:NetworkBackupsDir $ts');
  s = s.replace(/'KOJO_BACKUPS\\\\'/g, "(Join-Path $script:NetworkBackupsDir '')");
  s = s.replace(/'KOJO_BACKUP'/g, '$script:NetworkBackupDir');
  s = s.replace(/'KOJO_SCRIPTS'/g, '$script:NetworkScriptsDir');
  s = s.replace(/'KOJO_ROOT'/g, '$script:NetworkDataRoot');
  s = s.replace(/\$jsonOut='C:\\\\ProgramData\\\\Kojo\\\\Logs\\\\+([^']+)'/gi, "$jsonOut = Join-Path $script:NetworkLogsDir '$1'");
  s = s.replace(/\$ipLog='C:\\\\ProgramData\\\\Kojo\\\\Logs\\\\+([^']+)'/gi, "$ipLog = Join-Path $script:NetworkLogsDir '$1'");
  s = s.replace(/'C:\\\\ProgramData\\\\Kojo\\\\Logs\\\\([^']+)'/gi, "(Join-Path $script:NetworkLogsDir '$1')");
  s = s.replace(/\bexit 10\b/g, '$script:NetworkProfileExitCode = 10');
  s = s.replace(/\bexit 2\b/g, '$script:NetworkProfileExitCode = 2');
  s = s.replace(/\bexit 0\b/g, '$script:NetworkProfileExitCode = 0');
  return s;
}

function wrapActionScript(innerName, action, messageOk, messageErr) {
  return `${toPs1Header()}
${innerName}

if ($LASTEXITCODE -eq 0) {
  Write-KojoJson -Ok $true -Status 'success' -Action '${action}' -Message '${messageOk}' -Data @{ exitCode = 0 }
} elseif ($LASTEXITCODE -eq 2) {
  $detail = ''
  try {
    $rp = Join-Path $script:NetworkLogsDir 'gaming-profile-result.json'
    if (Test-Path -LiteralPath $rp) {
      $o = Get-Content -LiteralPath $rp -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($o.errors -and $o.errors.Count) { $detail = ($o.errors -join ' | ') }
    }
  } catch {}
  Write-KojoJson -Ok $false -Status 'error' -Action '${action}' -Message $(if ($detail) { $detail } else { '${messageErr}' }) -Data @{ exitCode = 2; errors = $detail }
} else {
  Write-KojoJson -Ok $false -Status 'error' -Action '${action}' -Message '${messageErr} (code ' + $LASTEXITCODE + ')' -Data @{ exitCode = $LASTEXITCODE }
}
`;
}

if (!fs.existsSync(htaPath)) {
  console.error('[extract] HTA missing:', htaPath);
  process.exit(1);
}

const hta = fs.readFileSync(htaPath, 'utf8');
const gamingPs = adaptPurplePs(evalHtaFunction(hta, 'buildPsTcpGamingProfile'));
const restorePs = adaptPurplePs(evalHtaFunction(hta, 'buildPsTcpRestoreNetwork'));

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, '_Apply-TcpGamingProfile-Body.ps1'), gamingPs, 'utf8');
fs.writeFileSync(path.join(outDir, '_Restore-TcpNetwork-Body.ps1'), restorePs, 'utf8');

const applyWrapper = `${toPs1Header()}Write-Host '[network] NETWORK_APPLY_START kind=tcp-gaming'
$script:NetworkProfileExitCode = -1
. (Join-Path $PSScriptRoot '_Apply-TcpGamingProfile-Body.ps1')
$code = if ($null -ne $script:NetworkProfileExitCode) { [int]$script:NetworkProfileExitCode } else { 1 }
Write-Host "[network] NETWORK_APPLY_RESULT kind=tcp-gaming code=$code"
if ($code -eq 0) {
  Update-NetworkState -Patch @{ tcpOptimizerApplied = $true; tcpOptimizerLastApplied = (Get-Date -Format 'yyyy-MM-dd HH:mm') }
  Write-KojoJson -Ok $true -Status 'success' -Action 'ApplyTcpGamingProfile' -Message 'Profil gaming appliqué avec succès. Redémarrage conseillé.' -Data @{ exitCode = 0 }
} elseif ($code -eq 2) {
  $detail = ''
  try {
    $rp = Join-Path $script:NetworkLogsDir 'gaming-profile-result.json'
    if (Test-Path -LiteralPath $rp) {
      $o = Get-Content -LiteralPath $rp -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($o.errors -and $o.errors.Count) { $detail = ($o.errors -join ' | ') }
    }
  } catch {}
  Write-KojoJson -Ok $false -Status 'error' -Action 'ApplyTcpGamingProfile' -Message $(if ($detail) { $detail } else { 'Vérification du profil gaming échouée.' }) -Data @{ exitCode = 2 }
} else {
  Write-KojoJson -Ok $false -Status 'error' -Action 'ApplyTcpGamingProfile' -Message ('Erreur profil gaming (code ' + $code + ')') -Data @{ exitCode = $code }
}
`;
fs.writeFileSync(path.join(outDir, 'Apply-TcpGamingProfile.ps1'), applyWrapper, 'utf8');
// Restore-TcpNetwork.ps1 wrapper : maintenu manuellement (détection succès / logs)

console.log('[extract] OK →', outDir);
