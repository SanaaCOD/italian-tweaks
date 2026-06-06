/**
 * Polling Accueil — collecte stats toutes les 8 s (GPU timeout 4 s)
 */
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const {
  getBundledContentRoot,
  getLogsDir,
  resolveScriptPath,
  scriptExists
} = require('./paths');
const { logStatsDiag } = require('./stats-diag');
const { buildPowerShellFileArgs, logPowerShellArgs } = require('./ps-exec');

const POLL_MS = 8000;
const GPU_TIMEOUT_SEC = 4;
const COLLECT_REL = 'system/Collect-HomeStats.ps1';

let cache = {
  cpu: null,
  gpu: null,
  ram: null,
  updatedAt: 0,
  hardware: null
};
let pollTimer = null;
let collectBusy = false;

function getResultPath() {
  return path.join(getLogsDir(), 'home-stats-result.json');
}

function readResultFile() {
  const p = getResultPath();
  try {
    if (!fs.existsSync(p)) return null;
    const raw = fs.readFileSync(p, 'utf8');
    const data = JSON.parse(raw);
    logStatsDiag(`readResultFile path=${p} json=${raw.trim()}`);
    return data;
  } catch (e) {
    logStatsDiag(`readResultFile failed path=${p} err=${e.message}`);
    return null;
  }
}

function applyLiveFromFile() {
  const data = readResultFile();
  if (!data) return false;
  if (data.cpu != null && !Number.isNaN(Number(data.cpu))) cache.cpu = Number(data.cpu);
  if (data.gpu != null && !Number.isNaN(Number(data.gpu))) cache.gpu = Number(data.gpu);
  if (data.ram != null && !Number.isNaN(Number(data.ram))) cache.ram = Number(data.ram);
  cache.updatedAt = Date.now();
  return true;
}

function runCollectScript() {
  if (collectBusy) return;
  collectBusy = true;

  const appRoot = path.resolve(getBundledContentRoot());
  const logDir = path.resolve(getLogsDir());
  const script = path.resolve(resolveScriptPath(COLLECT_REL));
  const outPath = getResultPath();
  const exists = scriptExists(COLLECT_REL);

  logStatsDiag(
    `runCollect exists=${exists} scriptPath=${script} appRoot=${appRoot} logDir=${logDir} outPath=${outPath}`
  );

  if (!exists) {
    collectBusy = false;
    return;
  }

  if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });

  try {
    if (fs.existsSync(outPath)) fs.unlinkSync(outPath);
  } catch {
    /* ignore */
  }

  let psArgs;
  try {
    psArgs = buildPowerShellFileArgs(script, {
      '-AppRoot': appRoot,
      '-LogDir': logDir,
      '-OutPath': outPath,
      '-GpuTimeoutSec': String(GPU_TIMEOUT_SEC)
    });
  } catch (err) {
    logStatsDiag(`runCollect buildArgs error=${err.message}`);
    collectBusy = false;
    return;
  }

  logPowerShellArgs('runCollect', psArgs);

  const child = spawn('powershell.exe', psArgs, { windowsHide: true, cwd: appRoot, shell: false });

  let stderr = '';
  child.stderr?.on('data', (d) => { stderr += d.toString('utf8'); });

  child.on('close', (code) => {
    const ok = applyLiveFromFile();
    logStatsDiag(`runCollect close code=${code} applied=${ok} stderr=${stderr.slice(0, 300)}`);
    collectBusy = false;
  });

  child.on('error', (err) => {
    logStatsDiag(`runCollect spawn error=${err.message}`);
    collectBusy = false;
  });
}

function startPolling() {
  stopPolling();
  logStatsDiag(`startPolling intervalMs=${POLL_MS}`);
  runCollectScript();
  pollTimer = setInterval(runCollectScript, POLL_MS);
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

function setHardwareSnapshot(hw) {
  cache.hardware = hw;
}

function setLiveStats({ cpu, gpu, ram }) {
  if (cpu != null && !Number.isNaN(Number(cpu))) cache.cpu = Number(cpu);
  if (gpu != null && !Number.isNaN(Number(gpu))) cache.gpu = Number(gpu);
  if (ram != null && !Number.isNaN(Number(ram))) cache.ram = Number(ram);
  cache.updatedAt = Date.now();
}

function getCachedPayload() {
  applyLiveFromFile();
  const hw = cache.hardware || {};
  const cpuU = cache.cpu ?? hw.cpu?.usage ?? null;
  const gpuU = cache.gpu ?? hw.gpu?.usage ?? null;
  const ramU = cache.ram ?? hw.ram?.usage ?? null;

  return {
    ok: true,
    status: 'success',
    action: 'GetSystemStats',
    message: 'Statistiques système (cache)',
    data: {
      cpu: { usage: cpuU, name: hw.cpu?.name || 'CPU' },
      gpu: { usage: gpuU, name: hw.gpu?.name || 'GPU' },
      ram: {
        usage: ramU,
        modules: hw.ram?.modules || '',
        speed: hw.ram?.speed || '',
        xmp: hw.ram?.xmp || 'N/D'
      },
      windows: hw.windows || {},
      uptime: hw.uptime || '',
      timestamp: new Date().toLocaleString('fr-FR', {
        day: '2-digit', month: '2-digit', year: 'numeric',
        hour: '2-digit', minute: '2-digit'
      }).replace(',', ' -'),
      updatedAt: cache.updatedAt
    }
  };
}

module.exports = {
  startPolling,
  stopPolling,
  runCollectScript,
  readResultFile,
  applyLiveFromFile,
  setHardwareSnapshot,
  setLiveStats,
  getCachedPayload,
  getCache: () => ({ ...cache }),
  getCollectScriptPath: () => resolveScriptPath(COLLECT_REL)
};
