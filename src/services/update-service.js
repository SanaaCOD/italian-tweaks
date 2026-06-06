const { app } = require('electron');
const fs = require('fs');
const path = require('path');
const { autoUpdater } = require('electron-updater');
const { getLogsDir } = require('./paths');

const GITHUB_RELEASES_LATEST =
  'https://api.github.com/repos/SanaaCOD/kojo/releases/latest';

let getMainWindow = () => null;
let initialized = false;

let lastPayload = {
  ok: true,
  status: 'idle',
  message: 'PrÃªt',
  data: { currentVersion: app.getVersion(), updateMode: 'dev' }
};

let checkWaiter = null;
let downloadWaiter = null;

function getAppUpdateYmlPath() {
  return path.join(process.resourcesPath, 'app-update.yml');
}

function hasAppUpdateYml() {
  try {
    return fs.existsSync(getAppUpdateYmlPath());
  } catch {
    return false;
  }
}

function isWinUnpackedBuild() {
  try {
    const exe = (process.execPath || '').replace(/\//g, '\\');
    return /\\win-unpacked\\/i.test(exe) || /win-unpacked/i.test(exe);
  } catch {
    return false;
  }
}

/** @returns {'dev'|'local_build'|'installed'} */
function getUpdateMode() {
  if (!app.isPackaged) return 'dev';
  if (!hasAppUpdateYml() || isWinUnpackedBuild()) return 'local_build';
  return 'installed';
}

function writeLog(line) {
  const file = path.join(getLogsDir(), 'updates.log');
  try {
    const dir = path.dirname(file);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);
    fs.appendFileSync(file, `[${ts}] ${line}\n`, 'utf8');
  } catch {
    /* ignore */
  }
}

function makePayload(partial) {
  const mode = getUpdateMode();
  return {
    ok: partial.ok !== false,
    status: partial.status || 'idle',
    message: partial.message || '',
    data: {
      currentVersion: app.getVersion(),
      updateMode: mode,
      devMode: mode === 'dev',
      localBuild: mode === 'local_build',
      packaged: app.isPackaged,
      ...(partial.data || {})
    }
  };
}

function broadcast(partial) {
  lastPayload = makePayload(partial);
  writeLog(`${lastPayload.status} | ${lastPayload.message}`);
  const win = getMainWindow();
  if (win && !win.isDestroyed()) {
    win.webContents.send('updates:status', lastPayload);
  }
}

function resolveWaiter(waiter, payload) {
  if (!waiter) return;
  waiter.resolve(payload);
}

function clearWaiter(type) {
  if (type === 'check') checkWaiter = null;
  if (type === 'download') downloadWaiter = null;
}

function parseVersionParts(v) {
  const s = String(v || '')
    .replace(/^v/i, '')
    .trim();
  const m = s.match(/^(\d+)(?:\.(\d+))?(?:\.(\d+))?/);
  if (!m) return [0, 0, 0];
  return [Number(m[1]) || 0, Number(m[2]) || 0, Number(m[3]) || 0];
}

function compareVersions(a, b) {
  const va = parseVersionParts(a);
  const vb = parseVersionParts(b);
  for (let i = 0; i < 3; i += 1) {
    if (va[i] !== vb[i]) return va[i] - vb[i];
  }
  return 0;
}

async function checkGitHubReleaseReadOnly() {
  const currentVersion = app.getVersion();
  try {
    const res = await fetch(GITHUB_RELEASES_LATEST, {
      headers: {
        Accept: 'application/vnd.github+json',
        'User-Agent': 'KOJO-UpdateCheck'
      }
    });

    if (res.status === 404 || res.status === 401 || res.status === 403) {
      writeLog(`github releases/latest ${res.status} (private or missing)`);
      return {
        ok: false,
        privateRepo: true,
        message:
          'Repo privÃ© â€” update rÃ©el nÃ©cessitera une release accessible ou un token'
      };
    }

    if (!res.ok) {
      writeLog(`github releases/latest HTTP ${res.status}`);
      return {
        ok: false,
        message: `GitHub API indisponible (${res.status})`
      };
    }

    const data = await res.json();
    const tagName = data?.tag_name || '';
    const remoteDisplay = tagName || data?.name || 'â€”';
    const remoteVer = tagName.replace(/^v/i, '');
    const newer = compareVersions(remoteVer, currentVersion) > 0;

    writeLog(`github latest ${remoteDisplay} (current ${currentVersion}, newer=${newer})`);

    return {
      ok: true,
      tagName: remoteDisplay,
      remoteVersion: remoteDisplay,
      newer,
      message: `DerniÃ¨re release GitHub : ${remoteDisplay}`
    };
  } catch (err) {
    const msg = err?.message || String(err);
    writeLog(`github fetch error: ${msg}`);
    return { ok: false, message: msg };
  }
}

function localBuildCheckPayload(githubResult) {
  const missingYml = !hasAppUpdateYml();
  const base =
    'Mode test local â€” installe la version Setup pour tester les mises Ã  jour rÃ©elles';

  if (githubResult?.privateRepo) {
    return makePayload({
      ok: false,
      status: 'local_build',
      message: githubResult.message,
      data: {
        missing: missingYml ? 'app-update.yml' : undefined,
        privateRepo: true,
        githubChecked: true
      }
    });
  }

  if (githubResult?.ok && githubResult.remoteVersion) {
    const ghLine = githubResult.message || `DerniÃ¨re release GitHub : ${githubResult.remoteVersion}`;
    const newerHint = githubResult.newer
      ? ' (version plus rÃ©cente que la vÃ´tre)'
      : '';
    return makePayload({
      ok: githubResult.newer,
      status: 'local_build',
      message: `${base}. ${ghLine}${newerHint}`,
      data: {
        missing: missingYml ? 'app-update.yml' : undefined,
        githubRelease: githubResult.remoteVersion,
        remoteVersion: githubResult.remoteVersion,
        githubChecked: true,
        githubNewer: githubResult.newer
      }
    });
  }

  const fallbackMsg = missingYml
    ? 'Mode test local â€” update rÃ©el disponible seulement avec lâ€™application installÃ©e'
    : base;

  return makePayload({
    ok: false,
    status: 'local_build',
    message: fallbackMsg,
    data: {
      missing: missingYml ? 'app-update.yml' : undefined,
      githubChecked: !!githubResult,
      githubError: githubResult?.message
    }
  });
}

function initUpdateService(mainWindowGetter) {
  if (initialized) {
    getMainWindow = mainWindowGetter;
    return;
  }
  initialized = true;
  getMainWindow = mainWindowGetter;

  const mode = getUpdateMode();
  lastPayload = makePayload({
    ok: true,
    status: 'idle',
    message: 'PrÃªt',
    data: { currentVersion: app.getVersion() }
  });

  autoUpdater.autoDownload = false;
  autoUpdater.autoInstallOnAppQuit = false;
  autoUpdater.allowDowngrade = false;

  if (mode !== 'installed') {
    writeLog(`init ${mode} â€” autoUpdater disabled (no app-update.yml or dev)`);
    return;
  }

  autoUpdater.on('checking-for-update', () => {
    broadcast({ ok: true, status: 'checking', message: 'VÃ©rification des mises Ã  jourâ€¦' });
  });

  autoUpdater.on('update-available', (info) => {
    const ver = info?.version || '';
    const payload = makePayload({
      ok: true,
      status: 'available',
      message: ver ? `Nouvelle version disponible (${ver})` : 'Nouvelle version disponible',
      data: {
        version: ver,
        releaseNotes: info?.releaseNotes,
        releaseDate: info?.releaseDate
      }
    });
    broadcast(payload);
    resolveWaiter(checkWaiter, payload);
    clearWaiter('check');
  });

  autoUpdater.on('update-not-available', (info) => {
    const payload = makePayload({
      ok: true,
      status: 'not_available',
      message: 'Application Ã  jour',
      data: { remoteVersion: info?.version || app.getVersion() }
    });
    broadcast(payload);
    resolveWaiter(checkWaiter, payload);
    clearWaiter('check');
  });

  autoUpdater.on('download-progress', (progress) => {
    const percent = Math.round(progress?.percent || 0);
    broadcast({
      ok: true,
      status: 'downloading',
      message: `TÃ©lÃ©chargementâ€¦ ${percent}%`,
      data: {
        percent,
        transferred: progress?.transferred,
        total: progress?.total,
        bytesPerSecond: progress?.bytesPerSecond
      }
    });
  });

  autoUpdater.on('update-downloaded', (info) => {
    const ver = info?.version || '';
    const payload = makePayload({
      ok: true,
      status: 'downloaded',
      message: `Mise Ã  jour ${ver} prÃªte Ã  installer`,
      data: { version: ver, percent: 100 }
    });
    broadcast(payload);
    resolveWaiter(downloadWaiter, payload);
    clearWaiter('download');
  });

  autoUpdater.on('error', (err) => {
    const msg = err?.message || String(err);
    if (/app-update\.yml/i.test(msg) || /ENOENT/i.test(msg)) {
      writeLog(`autoUpdater error suppressed: ${msg}`);
      const payload = localBuildCheckPayload(null);
      broadcast(payload);
      resolveWaiter(checkWaiter, payload);
      resolveWaiter(downloadWaiter, payload);
      clearWaiter('check');
      clearWaiter('download');
      return;
    }
    const payload = makePayload({
      ok: false,
      status: 'error',
      message: msg,
      data: { errorDetails: msg }
    });
    broadcast(payload);
    resolveWaiter(checkWaiter, payload);
    resolveWaiter(downloadWaiter, payload);
    clearWaiter('check');
    clearWaiter('download');
  });

  writeLog('init installed â€” autoUpdater ready (Kojo)');
}

function getStatus() {
  return lastPayload;
}

function getAppVersion() {
  return app.getVersion();
}

async function checkForUpdates() {
  const mode = getUpdateMode();
  writeLog(`checkForUpdates mode=${mode}`);

  if (mode === 'dev') {
    const payload = makePayload({
      ok: true,
      status: 'not_available',
      message: 'Mode dev â€” update rÃ©el indisponible',
      data: { devMode: true, packaged: false }
    });
    broadcast(payload);
    return payload;
  }

  if (mode === 'local_build') {
    broadcast({
      ok: true,
      status: 'checking',
      message: 'VÃ©rification GitHub (lecture seule)â€¦'
    });
    const github = await checkGitHubReleaseReadOnly();
    const payload = localBuildCheckPayload(github);
    broadcast(payload);
    return payload;
  }

  if (!hasAppUpdateYml()) {
    const github = await checkGitHubReleaseReadOnly();
    const payload = localBuildCheckPayload(github);
    broadcast(payload);
    return payload;
  }

  if (checkWaiter) {
    return makePayload({
      ok: false,
      status: 'checking',
      message: 'VÃ©rification dÃ©jÃ  en coursâ€¦'
    });
  }

  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      if (!checkWaiter) return;
      const payload = makePayload({
        ok: false,
        status: 'error',
        message: 'DÃ©lai dÃ©passÃ© lors de la vÃ©rification GitHub'
      });
      broadcast(payload);
      checkWaiter = null;
      resolve(payload);
    }, 120000);

    checkWaiter = {
      resolve: (p) => {
        clearTimeout(timeout);
        resolve(p);
      }
    };

    writeLog('checkForUpdates start (autoUpdater)');
    autoUpdater.checkForUpdates().catch((err) => {
      clearTimeout(timeout);
      const msg = err?.message || String(err);
      if (/app-update\.yml/i.test(msg) || /ENOENT/i.test(msg)) {
        writeLog(`check suppressed ENOENT: ${msg}`);
        checkGitHubReleaseReadOnly().then((github) => {
          const payload = localBuildCheckPayload(github);
          broadcast(payload);
          checkWaiter = null;
          resolve(payload);
        });
        return;
      }
      const payload = makePayload({
        ok: false,
        status: 'error',
        message: msg
      });
      broadcast(payload);
      checkWaiter = null;
      resolve(payload);
    });
  });
}

async function downloadUpdate() {
  const mode = getUpdateMode();

  if (mode === 'dev') {
    return makePayload({
      ok: false,
      status: 'error',
      message: 'Mode dev â€” update rÃ©el indisponible'
    });
  }

  if (mode === 'local_build') {
    return makePayload({
      ok: false,
      status: 'local_build',
      message:
        'Mode test local â€” tÃ©lÃ©chargement indisponible (installez via Setup NSIS)'
    });
  }

  if (lastPayload.status !== 'available') {
    return makePayload({
      ok: false,
      status: 'error',
      message: 'Aucune mise Ã  jour disponible â€” cliquez dâ€™abord sur Check update'
    });
  }

  if (downloadWaiter) {
    return makePayload({
      ok: false,
      status: 'downloading',
      message: 'TÃ©lÃ©chargement dÃ©jÃ  en coursâ€¦'
    });
  }

  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      if (!downloadWaiter) return;
      const payload = makePayload({
        ok: false,
        status: 'error',
        message: 'DÃ©lai dÃ©passÃ© lors du tÃ©lÃ©chargement'
      });
      broadcast(payload);
      downloadWaiter = null;
      resolve(payload);
    }, 600000);

    downloadWaiter = {
      resolve: (p) => {
        clearTimeout(timeout);
        resolve(p);
      }
    };

    writeLog('downloadUpdate start');
    broadcast({ ok: true, status: 'downloading', message: 'TÃ©lÃ©chargementâ€¦ 0%', data: { percent: 0 } });

    autoUpdater.downloadUpdate().catch((err) => {
      clearTimeout(timeout);
      const msg = err?.message || String(err);
      const payload = makePayload({
        ok: false,
        status: 'error',
        message: msg
      });
      broadcast(payload);
      downloadWaiter = null;
      resolve(payload);
    });
  });
}

function quitAndInstall() {
  const mode = getUpdateMode();

  if (mode === 'dev') {
    return makePayload({
      ok: false,
      status: 'error',
      message: 'Mode dev â€” update rÃ©el indisponible'
    });
  }

  if (mode === 'local_build') {
    return makePayload({
      ok: false,
      status: 'local_build',
      message:
        'Mode test local â€” installation indisponible (installez via Setup NSIS)'
    });
  }

  if (lastPayload.status !== 'downloaded') {
    return makePayload({
      ok: false,
      status: 'error',
      message: 'TÃ©lÃ©chargez la mise Ã  jour avant dâ€™installer'
    });
  }

  writeLog('quitAndInstall');
  setImmediate(() => {
    autoUpdater.quitAndInstall(false, true);
  });

  return makePayload({
    ok: true,
    status: 'downloaded',
    message: 'RedÃ©marrage pour installer la mise Ã  jourâ€¦',
    data: { installing: true }
  });
}

module.exports = {
  initUpdateService,
  getStatus,
  getAppVersion,
  getUpdateMode,
  checkForUpdates,
  downloadUpdate,
  quitAndInstall
};

