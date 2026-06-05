const { app, BrowserWindow, nativeImage } = require('electron');
const path = require('path');
const { registerIpcHandlers } = require('./ipc/handlers');
const { initUpdateService } = require('./services/update-service');

const WINDOW_WIDTH = 1440;
const WINDOW_HEIGHT = 900;

let mainWindow = null;

const gotLock = app.requestSingleInstanceLock();

if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show();
      mainWindow.focus();
    }
  });

  app.whenReady().then(() => {
    registerIpcHandlers();
    const { getBundledContentRoot, getLogsDir, resolveScriptPath } = require('./services/paths');
    const { logStatsDiag } = require('./services/stats-diag');
    logStatsDiag(
      `app ready packaged=${app.isPackaged} contentRoot=${getBundledContentRoot()} ` +
      `logsDir=${getLogsDir()} collectScript=${resolveScriptPath('system/Collect-HomeStats.ps1')}`
    );
    const system = require('./services/system');
    system.startMonitor();
    createMainWindow();
    initUpdateService(() => mainWindow);
  });

  app.on('before-quit', () => {
    try {
      require('./services/system').stopMonitor();
    } catch {
      /* ignore */
    }
  });

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
  });

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createMainWindow();
  });
}

function createMainWindow() {
  const iconPath = path.join(__dirname, '..', 'assets', 'icon.png');
  const icon = nativeImage.createFromPath(iconPath);

  mainWindow = new BrowserWindow({
    width: WINDOW_WIDTH,
    height: WINDOW_HEIGHT,
    minWidth: 1100,
    minHeight: 700,
    center: true,
    show: false,
    backgroundColor: '#0a0a0a',
    autoHideMenuBar: true,
    title: 'Kojo',
    icon: icon.isEmpty() ? undefined : icon,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      devTools: !app.isPackaged
    }
  });

  mainWindow.once('ready-to-show', () => mainWindow.show());
  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  mainWindow.on('closed', () => { mainWindow = null; });
}
