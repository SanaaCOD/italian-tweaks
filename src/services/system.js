const { runScript } = require('./script-runner');
const monitor = require('./system-monitor');
const { logStatsDiag } = require('./stats-diag');

function usageNumber(metric) {
  if (metric == null) return null;
  if (typeof metric === 'number') return Number.isNaN(metric) ? null : metric;
  if (typeof metric === 'object' && metric.usage != null && metric.usage !== '') {
    const n = Number(metric.usage);
    return Number.isNaN(n) ? null : n;
  }
  return null;
}

/** Normalise toujours data.cpu / data.gpu / data.ram avec .usage */
function normalizeStatsResponse(payload) {
  monitor.applyLiveFromFile();
  const live = monitor.readResultFile();
  const data = { ...(payload?.data || {}) };

  const cpuLive = live?.cpu != null ? Number(live.cpu) : null;
  const gpuLive = live?.gpu != null ? Number(live.gpu) : null;
  const ramLive = live?.ram != null ? Number(live.ram) : null;

  const cpuU = cpuLive ?? usageNumber(data.cpu) ?? usageNumber(data.cpu?.usage);
  const gpuU = gpuLive ?? usageNumber(data.gpu) ?? usageNumber(data.gpu?.usage);
  const ramU = ramLive ?? usageNumber(data.ram) ?? usageNumber(data.ram?.usage);

  return {
    ...payload,
    ok: payload?.ok !== false,
    data: {
      ...data,
      cpu: { ...(typeof data.cpu === 'object' ? data.cpu : {}), usage: cpuU, name: data.cpu?.name || data.cpu?.Name || 'CPU' },
      gpu: { ...(typeof data.gpu === 'object' ? data.gpu : {}), usage: gpuU, name: data.gpu?.name || data.gpu?.Name || 'GPU' },
      ram: {
        ...(typeof data.ram === 'object' ? data.ram : {}),
        usage: ramU,
        modules: data.ram?.modules || '',
        speed: data.ram?.speed || '',
        xmp: data.ram?.xmp || 'N/D'
      }
    }
  };
}

function hasLiveUsage(payload) {
  const u = payload?.data;
  return [u?.cpu?.usage, u?.gpu?.usage, u?.ram?.usage].some(
    (v) => v !== null && v !== undefined && !Number.isNaN(Number(v))
  );
}

/** @param {{ full?: boolean }} [opts] */
async function getStats(opts = {}) {
  if (!opts.full) {
    const cached = normalizeStatsResponse(monitor.getCachedPayload());
    if (hasLiveUsage(cached)) {
      logStatsDiag(`getStats cache cpu=${cached.data.cpu.usage} gpu=${cached.data.gpu.usage} ram=${cached.data.ram.usage}`);
      return cached;
    }
  }

  logStatsDiag(`getStats full=${!!opts.full} collectPath=${monitor.getCollectScriptPath()}`);
  const result = await runScript('system/Get-SystemStats.ps1');

  if (result?.data) {
    monitor.setHardwareSnapshot(result.data);
    monitor.setLiveStats({
      cpu: usageNumber(result.data.cpu),
      gpu: usageNumber(result.data.gpu),
      ram: usageNumber(result.data.ram)
    });
    logStatsDiag(
      `getStats script ok cpu=${result.data.cpu?.usage} gpu=${result.data.gpu?.usage} ram=${result.data.ram?.usage}`
    );
  } else {
    logStatsDiag(`getStats script failed message=${result?.message}`);
    monitor.runCollectScript();
  }

  return normalizeStatsResponse(monitor.getCachedPayload());
}

function startMonitor() {
  monitor.startPolling();
}

function stopMonitor() {
  monitor.stopPolling();
}

module.exports = {
  getStats,
  startMonitor,
  stopMonitor,
  restoreAll: () => runScript('system/Restore-Defaults.ps1'),
  revertAll: () => runScript('system/Revert-All.ps1'),
  masterRunAll: () => runScript('system/Master-Run-All.ps1')
};
