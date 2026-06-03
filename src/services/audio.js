const { runScript } = require('./script-runner');
const { shell } = require('electron');

module.exports = {
  getStatus: () => runScript('audio/Get-AudioStatus.ps1', [], { read: true }),
  applyProfile: () => runScript('audio/Apply-AudioProfile.ps1'),
  restoreDefaults: () => runScript('audio/Restore-AudioDefaults.ps1'),
  async openSoundSettings() {
    await shell.openExternal('ms-settings:sound');
    return { ok: true, status: 'success', message: 'Paramètres son ouverts', action: 'OpenSoundSettings', data: {} };
  }
};
