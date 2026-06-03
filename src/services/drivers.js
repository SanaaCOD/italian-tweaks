const { runScript } = require('./script-runner');
const path = require('path');
const { getAppRoot } = require('./paths');
const { shell } = require('electron');

module.exports = {
  getNvidiaStatus: () => runScript('drivers/Get-NvidiaStatus.ps1', [], { read: true }),
  runDdu: () => runScript('drivers/Run-DDU.ps1'),
  runNvcleanInstall: () => runScript('drivers/Run-NVCleanInstall.ps1'),
  installLatestDriver: () => runScript('drivers/Install-LatestNvidiaDriver.ps1'),
  applyNvidiaOptimization: () => runScript('drivers/Apply-NvidiaOptimization.ps1'),
  applySqEngine: () => runScript('drivers/Apply-SQEngine.ps1'),
  nvidiaPanelGuide: () => runScript('drivers/NVIDIA-ControlPanel-Guide.ps1'),
  async openNipProfile() {
    const fs = require('fs');
    const root = getAppRoot();
    const nip = [path.join(root, 'tools', 'nvidia', 'sq_competitive.nip'), path.join(root, 'tools', 'sq_competitive.nip')].find((p) => fs.existsSync(p));
    if (!nip) {
      return {
        ok: false,
        status: 'error',
        message: 'Placez sq_competitive.nip dans tools/nvidia/',
        action: 'OpenNipProfile'
      };
    }
    await shell.openPath(nip);
    return { ok: true, status: 'success', message: 'Profil .nip ouvert', action: 'OpenNipProfile', data: { path: nip } };
  }
};
