/**
 * Bufferbloat / Network Test — logique TunedPC (Cloudflare speed + pings parallèles).
 * Porté depuis TunedPC dist-electron/main (registerBufferbloatHandlers / runSpeedTest).
 */
const { performance } = require('perf_hooks');
const { randomUUID } = require('crypto');
const { BrowserWindow } = require('electron');

const BUFFERBLOAT_GRADES = [
  { grade: 'A+', maxDelta: 5, labelFr: 'Excellent' },
  { grade: 'A', maxDelta: 30, labelFr: 'Très bon' },
  { grade: 'B', maxDelta: 60, labelFr: 'Correct' },
  { grade: 'C', maxDelta: 200, labelFr: 'Moyen' },
  { grade: 'D', maxDelta: 400, labelFr: 'Mauvais' },
  { grade: 'F', maxDelta: Infinity, labelFr: 'Très mauvais' }
];

const CF_BASE = 'https://speed.cloudflare.com';
const PING_ENDPOINT = `${CF_BASE}/__down?bytes=0`;
const DOWN_ENDPOINT = (bytes) => `${CF_BASE}/__down?bytes=${bytes}`;
const UP_ENDPOINT = `${CF_BASE}/__up`;
const DOWN_BYTES_PER_STREAM = 25 * 1024 * 1024;
const UP_BYTES_PER_STREAM = 10 * 1024 * 1024;
const PARALLEL_STREAMS = 6;
const IDLE_PING_COUNT = 20;
const IDLE_PING_INTERVAL_MS = 250;
const LOADED_PING_INTERVAL_MS = 300;
const FETCH_TIMEOUT_MS = 30000;
const GLOBAL_TIMEOUT_MS = 90000;

let activeAbort = null;

function isTestRunning() {
  return activeAbort !== null;
}

function computeGrade(maxDelta) {
  for (const tier of BUFFERBLOAT_GRADES) {
    if (maxDelta < tier.maxDelta) return tier.grade;
  }
  return 'F';
}

function getGradeInfo(grade) {
  return BUFFERBLOAT_GRADES.find((g) => g.grade === grade)
    || BUFFERBLOAT_GRADES[BUFFERBLOAT_GRADES.length - 1];
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

function sleep(ms, signal) {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(signal.reason || new DOMException('Aborted', 'AbortError'));
      return;
    }
    const onAbort = () => {
      clearTimeout(timer);
      reject(signal.reason || new DOMException('Aborted', 'AbortError'));
    };
    const timer = setTimeout(() => {
      signal.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    signal.addEventListener('abort', onAbort, { once: true });
  });
}

function combineSignals(...signals) {
  if (typeof AbortSignal.any === 'function') {
    return AbortSignal.any(signals);
  }
  const controller = new AbortController();
  const onAbort = () => controller.abort();
  for (const sig of signals) {
    if (sig.aborted) {
      controller.abort();
      return controller.signal;
    }
    sig.addEventListener('abort', onAbort, { once: true });
  }
  return controller.signal;
}

async function measurePing(signal) {
  const start = performance.now();
  try {
    const resp = await fetch(PING_ENDPOINT, {
      method: 'GET',
      cache: 'no-store',
      signal
    });
    await resp.arrayBuffer();
    return performance.now() - start;
  } catch {
    return -1;
  }
}

async function detectServerLocation(signal) {
  try {
    const resp = await fetch(PING_ENDPOINT, {
      method: 'GET',
      cache: 'no-store',
      signal
    });
    await resp.arrayBuffer();
    const ray = resp.headers.get('cf-ray') || '';
    const match = ray.match(/-([A-Z]{3})$/);
    return match ? match[1] : 'Unknown';
  } catch {
    return 'Unknown';
  }
}

function computePhaseStats(latencies) {
  const total = latencies.length;
  if (total === 0) {
    return { avgLatency: 0, minLatency: 0, maxLatency: 0, jitter: 0, packetLoss: 0, samples: 0 };
  }
  const failed = latencies.filter((l) => l < 0).length;
  const successful = latencies.filter((l) => l >= 0);
  const packetLoss = (failed / total) * 100;
  if (successful.length === 0) {
    return { avgLatency: 0, minLatency: 0, maxLatency: 0, jitter: 0, packetLoss: 100, samples: total };
  }
  const avg = successful.reduce((a, b) => a + b, 0) / successful.length;
  const min = Math.min(...successful);
  const max = Math.max(...successful);
  const variance = successful.reduce((sum, v) => sum + (v - avg) ** 2, 0) / successful.length;
  const jitter = Math.sqrt(variance);
  return {
    avgLatency: round2(avg),
    minLatency: round2(min),
    maxLatency: round2(max),
    jitter: round2(jitter),
    packetLoss: round2(packetLoss),
    samples: total
  };
}

function sendProgress(progress, onProgress) {
  if (typeof onProgress === 'function') {
    onProgress(progress);
  }
  try {
    const win = BrowserWindow.getAllWindows().find((w) => !w.isDestroyed());
    if (win) {
      win.webContents.send('network:testProgress', progress);
    }
  } catch {
    /* ignore */
  }
}

async function runIdlePhase(ctx) {
  const latencies = [];
  for (let i = 0; i < IDLE_PING_COUNT; i++) {
    if (ctx.signal.aborted) throw new DOMException('Aborted', 'AbortError');
    const rtt = await measurePing(ctx.signal);
    latencies.push(rtt);
    const sample = {
      timestamp: performance.now() - ctx.testStart,
      latency: rtt >= 0 ? round2(rtt) : -1,
      phase: 'idle'
    };
    ctx.allSamples.push(sample);
    const progress = {
      phase: 'idle',
      progress: ((i + 1) / IDLE_PING_COUNT) * 100,
      overallProgress: ((i + 1) / IDLE_PING_COUNT) * 15,
      currentLatency: rtt >= 0 ? round2(rtt) : undefined,
      latencySample: sample
    };
    ctx.sendProgress(progress);
    if (i < IDLE_PING_COUNT - 1) {
      await sleep(IDLE_PING_INTERVAL_MS, ctx.signal);
    }
  }
  return { stats: computePhaseStats(latencies), latencies };
}

async function downloadStream(signal, bytesAccumulator) {
  const timeoutSignal = AbortSignal.timeout(FETCH_TIMEOUT_MS);
  const combined = combineSignals(signal, timeoutSignal);
  const resp = await fetch(DOWN_ENDPOINT(DOWN_BYTES_PER_STREAM), {
    method: 'GET',
    cache: 'no-store',
    signal: combined
  });
  if (!resp.body) {
    const buf = await resp.arrayBuffer();
    bytesAccumulator.bytes += buf.byteLength;
    return;
  }
  const reader = resp.body.getReader();
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value) bytesAccumulator.bytes += value.byteLength;
    }
  } finally {
    reader.releaseLock();
  }
}

async function uploadStream(signal, bytesAccumulator) {
  const timeoutSignal = AbortSignal.timeout(FETCH_TIMEOUT_MS);
  const combined = combineSignals(signal, timeoutSignal);
  const buffer = Buffer.alloc(UP_BYTES_PER_STREAM);
  const resp = await fetch(UP_ENDPOINT, {
    method: 'POST',
    body: buffer,
    signal: combined,
    headers: { 'Content-Type': 'application/octet-stream' }
  });
  await resp.arrayBuffer();
  bytesAccumulator.bytes += UP_BYTES_PER_STREAM;
}

async function runDownloadPhase(ctx) {
  const loadedLatencies = [];
  const bytesAccum = { bytes: 0 };
  const phaseStart = performance.now();
  let streamsDone = false;
  const streamPromises = [];
  for (let i = 0; i < PARALLEL_STREAMS; i++) {
    streamPromises.push(downloadStream(ctx.signal, bytesAccum).catch(() => {}));
  }
  const latencyProbe = (async () => {
    while (!streamsDone) {
      if (ctx.signal.aborted) break;
      const rtt = await measurePing(ctx.signal);
      loadedLatencies.push(rtt);
      const elapsed = performance.now() - phaseStart;
      const currentSpeedMbps = elapsed > 0 ? (bytesAccum.bytes * 8) / (elapsed / 1e3) / 1e6 : 0;
      const sample = {
        timestamp: performance.now() - ctx.testStart,
        latency: rtt >= 0 ? round2(rtt) : -1,
        phase: 'download'
      };
      ctx.allSamples.push(sample);
      ctx.sendProgress({
        phase: 'download',
        progress: Math.min(100, (elapsed / 12000) * 100),
        overallProgress: 15 + Math.min(40, (elapsed / 12000) * 40),
        currentLatency: rtt >= 0 ? round2(rtt) : undefined,
        currentSpeed: round2(currentSpeedMbps),
        latencySample: sample
      });
      if (streamsDone) break;
      try {
        await sleep(LOADED_PING_INTERVAL_MS, ctx.signal);
      } catch {
        break;
      }
    }
  })();
  await Promise.allSettled(streamPromises);
  streamsDone = true;
  if (bytesAccum.bytes === 0) {
    throw new Error('All download streams failed -- check your internet connection');
  }
  await Promise.race([
    latencyProbe,
    new Promise((resolve) => setTimeout(resolve, 2000))
  ]);
  const phaseEnd = performance.now();
  const durationSec = (phaseEnd - phaseStart) / 1000;
  const speedMbps = durationSec > 0 ? (bytesAccum.bytes * 8) / durationSec / 1e6 : 0;
  const stats = computePhaseStats(loadedLatencies);
  return { ...stats, speedMbps: round2(speedMbps) };
}

async function runUploadPhase(ctx) {
  const loadedLatencies = [];
  const bytesAccum = { bytes: 0 };
  const phaseStart = performance.now();
  let streamsDone = false;
  const streamPromises = [];
  for (let i = 0; i < PARALLEL_STREAMS; i++) {
    streamPromises.push(uploadStream(ctx.signal, bytesAccum).catch(() => {}));
  }
  const latencyProbe = (async () => {
    while (!streamsDone) {
      if (ctx.signal.aborted) break;
      const rtt = await measurePing(ctx.signal);
      loadedLatencies.push(rtt);
      const elapsed = performance.now() - phaseStart;
      const currentSpeedMbps = elapsed > 0 ? (bytesAccum.bytes * 8) / (elapsed / 1e3) / 1e6 : 0;
      const sample = {
        timestamp: performance.now() - ctx.testStart,
        latency: rtt >= 0 ? round2(rtt) : -1,
        phase: 'upload'
      };
      ctx.allSamples.push(sample);
      ctx.sendProgress({
        phase: 'upload',
        progress: Math.min(100, (elapsed / 12000) * 100),
        overallProgress: 55 + Math.min(40, (elapsed / 12000) * 40),
        currentLatency: rtt >= 0 ? round2(rtt) : undefined,
        currentSpeed: round2(currentSpeedMbps),
        latencySample: sample
      });
      if (streamsDone) break;
      try {
        await sleep(LOADED_PING_INTERVAL_MS, ctx.signal);
      } catch {
        break;
      }
    }
  })();
  await Promise.allSettled(streamPromises);
  streamsDone = true;
  if (bytesAccum.bytes === 0) {
    throw new Error('All upload streams failed -- check your internet connection');
  }
  await Promise.race([
    latencyProbe,
    new Promise((resolve) => setTimeout(resolve, 2000))
  ]);
  const phaseEnd = performance.now();
  const durationSec = (phaseEnd - phaseStart) / 1000;
  const speedMbps = durationSec > 0 ? (bytesAccum.bytes * 8) / durationSec / 1e6 : 0;
  const stats = computePhaseStats(loadedLatencies);
  return { ...stats, speedMbps: round2(speedMbps) };
}

function mapResultToKojo(result) {
  const gradeInfo = getGradeInfo(result.grade);
  return {
    grade: result.grade,
    gradeDisplay: result.grade,
    statusLabel: gradeInfo.labelFr,
    unloadedMs: result.idle.avgLatency > 0 ? result.idle.avgLatency : null,
    baselineLatencyMs: result.idle.avgLatency > 0 ? result.idle.avgLatency : null,
    downloadMbps: result.download.speedMbps > 0 ? result.download.speedMbps : null,
    uploadMbps: result.upload.speedMbps > 0 ? result.upload.speedMbps : null,
    downloadDeltaMs: result.downloadDelta,
    uploadDeltaMs: result.uploadDelta,
    bufferbloatDeltaMs: result.maxDelta,
    serverLocation: result.serverLocation,
    partial: false,
    aborted: false
  };
}

async function runBufferbloatTest(onProgress) {
  if (isTestRunning()) {
    throw new Error('A bufferbloat test is already running');
  }

  const abortController = new AbortController();
  activeAbort = abortController;
  const myAbort = abortController;
  const { signal } = abortController;

  const globalTimer = setTimeout(() => {
    try {
      abortController.abort(new DOMException('Global timeout', 'TimeoutError'));
    } catch {
      abortController.abort();
    }
  }, GLOBAL_TIMEOUT_MS);

  const testId = randomUUID();
  const testStart = performance.now();
  const allSamples = [];
  const progressFn = (progress) => sendProgress(progress, onProgress);
  const ctx = { signal, testStart, allSamples, sendProgress: progressFn };

  try {
    progressFn({ phase: 'preparing', progress: 0, overallProgress: 0 });
    const serverLocation = await detectServerLocation(signal);
    if (signal.aborted) throw new DOMException('Aborted', 'AbortError');
    progressFn({ phase: 'preparing', progress: 100, overallProgress: 5 });
    progressFn({ phase: 'idle', progress: 0, overallProgress: 5 });

    const idle = await runIdlePhase(ctx);
    if (signal.aborted) throw new DOMException('Aborted', 'AbortError');
    progressFn({ phase: 'download', progress: 0, overallProgress: 15 });

    const download = await runDownloadPhase(ctx);
    if (signal.aborted) throw new DOMException('Aborted', 'AbortError');
    progressFn({ phase: 'upload', progress: 0, overallProgress: 55 });

    const upload = await runUploadPhase(ctx);
    if (signal.aborted) throw new DOMException('Aborted', 'AbortError');

    const downloadDelta = Math.max(0, download.avgLatency - idle.stats.avgLatency);
    const uploadDelta = Math.max(0, upload.avgLatency - idle.stats.avgLatency);
    const maxDelta = Math.max(downloadDelta, uploadDelta);
    const grade = computeGrade(maxDelta);

    const result = {
      id: testId,
      timestamp: new Date().toISOString(),
      idle: idle.stats,
      download,
      upload,
      downloadDelta: round2(downloadDelta),
      uploadDelta: round2(uploadDelta),
      maxDelta: round2(maxDelta),
      grade,
      latencySamples: allSamples,
      serverLocation
    };

    progressFn({ phase: 'complete', progress: 100, overallProgress: 100 });
    return result;
  } catch (err) {
    const isAbort = (err instanceof DOMException && err.name === 'AbortError')
      || (err instanceof Error && err.name === 'AbortError')
      || signal.aborted;
    const isTimeout = isAbort && (signal.reason?.name === 'TimeoutError'
      || String(signal.reason || err).includes('timeout')
      || String(err).includes('Timeout'));

    if (isAbort) {
      const errorMsg = isTimeout ? 'Test interrompu — relance le test.' : 'Test annulé';
      progressFn({ phase: 'error', progress: 0, overallProgress: 0, error: errorMsg });
      const timeoutErr = new Error(errorMsg);
      timeoutErr.code = isTimeout ? 'TIMEOUT' : 'ABORTED';
      throw timeoutErr;
    }

    const message = err instanceof Error ? err.message : String(err);
    progressFn({ phase: 'error', progress: 0, overallProgress: 0, error: message });
    throw err;
  } finally {
    clearTimeout(globalTimer);
    if (activeAbort === myAbort) {
      activeAbort = null;
    }
  }
}

function stopBufferbloatTest() {
  if (activeAbort) {
    activeAbort.abort();
    activeAbort = null;
    return true;
  }
  return false;
}

module.exports = {
  runBufferbloatTest,
  stopBufferbloatTest,
  isTestRunning,
  mapResultToKojo,
  computeGrade,
  getGradeInfo
};
