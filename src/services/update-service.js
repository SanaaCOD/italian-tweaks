const { app } = require('electron');
const fs = require('fs');
const path = require('path');
const { autoUpdater } = require('electron-updater');
const { getLogsDir } = require('./paths');

let getMainWindow = () => null;
let initialized = false;

let lastPayload = {
  ok: true,
  status: 'idle',
  message: 'Prêt',
  data: { currentVersion: app.getVersion() }
};

let checkWaiter = null;
let downloadWaiter = null;

function getLogPath() {
  return path.join(getLogsDir(), 'updates.log');
}

function writeLog(line) {
  const file = getLogPath();
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
  return {
    ok: partial.ok !== false,
    status: partial.status || 'idle',
    message: partial.message || '',
    data: {
      currentVersion: app.getVersion(),
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

function initUpdateService(mainWindowGetter) {
  if (initialized) {
    getMainWindow = mainWindowGetter;
    return;
  }
  initialized = true;
  getMainWindow = mainWindowGetter;

  autoUpdater.autoDownload = false;
  autoUpdater.autoInstallOnAppQuit = false;
  autoUpdater.allowDowngrade = false;

  if (!app.isPackaged) {
    autoUpdater.forceDevUpdateConfig = false;
    writeLog('init dev mode — updates disabled until packaged build');
    return;
  }

  autoUpdater.on('checking-for-update', () => {
    broadcast({ ok: true, status: 'checking', message: 'Vérification des mises à jour…' });
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
      message: 'Application à jour',
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
      message: `Téléchargement… ${percent}%`,
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
      message: `Mise à jour ${ver} prête à installer`,
      data: { version: ver, percent: 100 }
    });
    broadcast(payload);
    resolveWaiter(downloadWaiter, payload);
    clearWaiter('download');
  });

  autoUpdater.on('error', (err) => {
    const msg = err?.message || String(err);
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

  writeLog('init packaged — autoUpdater ready (github SanaaCOD/italian-tweaks)');
}

function getStatus() {
  return lastPayload;
}

function getAppVersion() {
  return app.getVersion();
}

async function checkForUpdates() {
  if (!app.isPackaged) {
    const payload = makePayload({
      ok: true,
      status: 'not_available',
      message: 'Mode développement — les mises à jour GitHub sont actives uniquement sur l’installateur.',
      data: { devMode: true }
    });
    broadcast(payload);
    return payload;
  }

  if (checkWaiter) {
    return makePayload({
      ok: false,
      status: 'checking',
      message: 'Vérification déjà en cours…'
    });
  }

  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      if (!checkWaiter) return;
      const payload = makePayload({
        ok: false,
        status: 'error',
        message: 'Délai dépassé lors de la vérification GitHub'
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

    writeLog('checkForUpdates start');
    autoUpdater.checkForUpdates().catch((err) => {
      clearTimeout(timeout);
      const payload = makePayload({
        ok: false,
        status: 'error',
        message: err?.message || String(err)
      });
      broadcast(payload);
      checkWaiter = null;
      resolve(payload);
    });
  });
}

async function downloadUpdate() {
  if (!app.isPackaged) {
    return makePayload({
      ok: false,
      status: 'error',
      message: 'Téléchargement indisponible en mode développement'
    });
  }

  if (lastPayload.status !== 'available') {
    return makePayload({
      ok: false,
      status: 'error',
      message: 'Aucune mise à jour disponible — cliquez d’abord sur Check update'
    });
  }

  if (downloadWaiter) {
    return makePayload({
      ok: false,
      status: 'downloading',
      message: 'Téléchargement déjà en cours…'
    });
  }

  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      if (!downloadWaiter) return;
      const payload = makePayload({
        ok: false,
        status: 'error',
        message: 'Délai dépassé lors du téléchargement'
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
    broadcast({ ok: true, status: 'downloading', message: 'Téléchargement… 0%', data: { percent: 0 } });

    autoUpdater.downloadUpdate().catch((err) => {
      clearTimeout(timeout);
      const payload = makePayload({
        ok: false,
        status: 'error',
        message: err?.message || String(err)
      });
      broadcast(payload);
      downloadWaiter = null;
      resolve(payload);
    });
  });
}

function quitAndInstall() {
  if (!app.isPackaged) {
    return makePayload({
      ok: false,
      status: 'error',
      message: 'Installation indisponible en mode développement'
    });
  }

  if (lastPayload.status !== 'downloaded') {
    return makePayload({
      ok: false,
      status: 'error',
      message: 'Téléchargez la mise à jour avant d’installer'
    });
  }

  writeLog('quitAndInstall');
  setImmediate(() => {
    autoUpdater.quitAndInstall(false, true);
  });

  return makePayload({
    ok: true,
    status: 'downloaded',
    message: 'Redémarrage pour installer la mise à jour…',
    data: { installing: true }
  });
}

module.exports = {
  initUpdateService,
  getStatus,
  getAppVersion,
  checkForUpdates,
  downloadUpdate,
  quitAndInstall
};
