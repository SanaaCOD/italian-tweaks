const { ipcMain, dialog } = require('electron');
const system = require('../services/system');
const controllerOc = require('../services/controller-oc');
const drivers = require('../services/drivers');
const network = require('../services/network');
const optimizations = require('../services/optimizations');
const optimizationModules = require('../services/optimization-modules-service');
const audio = require('../services/audio');
const games = require('../services/games');
const settings = require('../services/settings');
const updateService = require('../services/update-service');
const { getBuildInfo } = require('../services/build-info');

async function confirmDangerous(title, message) {
  if (!settings.load().confirmDangerousActions) return true;
  const { response } = await dialog.showMessageBox({
    type: 'warning',
    buttons: ['Annuler', 'Continuer'],
    defaultId: 0,
    cancelId: 0,
    title,
    message
  });
  return response === 1;
}

function registerIpcHandlers() {
  ipcMain.handle('system:getStats', (_e, opts) => system.getStats(opts));
  ipcMain.handle('system:restoreDefaults', () => system.restoreAll());
  ipcMain.handle('system:revertAll', () => system.revertAll());
  ipcMain.handle('system:masterRunAll', () => system.masterRunAll());

  controllerOc.registerControllerOcHandlers(ipcMain);

  ipcMain.handle('drivers:getNvidiaStatus', () => drivers.getNvidiaStatus());
  ipcMain.handle('drivers:runDdu', async () => {
    if (!(await confirmDangerous('DDU', 'Ouvrir DDU / téléchargement ?'))) return { ok: false, status: 'cancelled' };
    return drivers.runDdu();
  });
  ipcMain.handle('drivers:runNvclean', () => drivers.runNvcleanInstall());
  ipcMain.handle('drivers:installLatest', () => drivers.installLatestDriver());
  ipcMain.handle('drivers:applyOptimization', () => drivers.applyNvidiaOptimization());
  ipcMain.handle('drivers:applySqEngine', () => drivers.applySqEngine());
  ipcMain.handle('drivers:nvidiaGuide', () => drivers.nvidiaPanelGuide());
  ipcMain.handle('drivers:gpuOverclock', () => require('../services/script-runner').runScript('drivers/GPU-Overclock.ps1'));
  ipcMain.handle('drivers:openNip', () => drivers.openNipProfile());

  ipcMain.handle('network:status', () => network.getStatus());
  ipcMain.handle('network:gaming', () => network.applyGamingProfile());
  ipcMain.handle('network:download', () => network.applyDownloadProfile());
  ipcMain.handle('network:restore', () => network.restoreDefaults());
  ipcMain.handle('network:applyTcpGaming', () => network.applyTcpGaming());
  ipcMain.handle('network:optimization', () => network.applyOptimization());
  ipcMain.handle('network:tcp', () => network.launchTcpOptimizer());
  ipcMain.handle('network:runNetworkTest', () => network.runNetworkTest());

  ipcMain.handle('optim:modulesApply', async (_e, payload) => {
    if (!(await confirmDangerous(
      'Optimisation',
      'Appliquer les modules sélectionnés ? Les scripts PowerShell seront exécutés selon l\'état des toggles.'
    ))) return { ok: false, status: 'cancelled' };
    return optimizationModules.applyModules(payload);
  });

  ipcMain.handle('optim:status', () => optimizations.getStatus());
  ipcMain.handle('optim:debloat', async () => {
    if (!(await confirmDangerous('Debloat', 'Appliquer Debloat Windows ?'))) return { ok: false, status: 'cancelled' };
    return optimizations.applyDebloat();
  });
  ipcMain.handle('optim:debloatRestore', () => optimizations.restoreDebloat());
  ipcMain.handle('optim:gameMode', () => optimizations.applyGameMode());
  ipcMain.handle('optim:gameModeRestore', () => optimizations.restoreGameMode());
  ipcMain.handle('optim:power', () => optimizations.applyPowerPlan());
  ipcMain.handle('optim:powerRestore', () => optimizations.restorePowerPlan());
  ipcMain.handle('optim:windowed', () => optimizations.applyWindowedGameOptimizations());
  ipcMain.handle('optim:windows', () => optimizations.applyWindowsOptimization());
  ipcMain.handle('optim:deepDebloat', async () => {
    if (!(await confirmDangerous('Deep Debloat', 'Debloat profond ?'))) return { ok: false, status: 'cancelled' };
    return optimizations.applyDeepDebloat();
  });
  ipcMain.handle('optim:undoDeepDebloat', () => optimizations.undoDeepDebloat());
  ipcMain.handle('optim:copilot', () => optimizations.disableCopilot());
  ipcMain.handle('optim:wuOff', () => optimizations.windowsUpdateOff());
  ipcMain.handle('optim:wuOn', () => optimizations.windowsUpdateOn());
  ipcMain.handle('optim:standard', () => optimizations.standardWindowsSettings());

  ipcMain.handle('audio:status', () => audio.getStatus());
  ipcMain.handle('audio:apply', () => audio.applyProfile());
  ipcMain.handle('audio:restore', () => audio.restoreDefaults());
  ipcMain.handle('audio:openSettings', () => audio.openSoundSettings());

  ipcMain.handle('games:warzoneDetect', () => games.detectWarzonePath());
  ipcMain.handle('games:warzoneApply', async () => {
    if (!(await confirmDangerous('Warzone', 'Copier les fichiers config ?'))) return { ok: false, status: 'cancelled' };
    return games.applyWarzoneProfile();
  });
  ipcMain.handle('games:warzoneRestore', () => games.restoreWarzoneProfile());
  ipcMain.handle('games:apply', (_e, gameId) => games.applyGame(gameId));

  ipcMain.handle('settings:get', () => settings.load());
  ipcMain.handle('settings:save', (_e, d) => settings.save(d));
  ipcMain.handle('settings:reset', () => settings.reset());

  ipcMain.handle('updates:check', () => updateService.checkForUpdates());
  ipcMain.handle('updates:download', () => updateService.downloadUpdate());
  ipcMain.handle('updates:install', () => updateService.quitAndInstall());
  ipcMain.handle('updates:getStatus', () => updateService.getStatus());
  ipcMain.handle('updates:getVersion', () => ({
    ok: true,
    status: 'success',
    message: '',
    data: {
      version: updateService.getAppVersion(),
      updateMode: updateService.getUpdateMode()
    }
  }));

  ipcMain.handle('app:getBuildInfo', () => getBuildInfo());
}

module.exports = { registerIpcHandlers };
