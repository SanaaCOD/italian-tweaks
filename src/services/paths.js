const path = require('path');
const fs = require('fs');
const { app } = require('electron');

/** Racine projet (dev) ou contenu déballé (build) — scripts + package.json */
function getBundledContentRoot() {
  if (!app.isPackaged) {
    return path.join(__dirname, '..', '..');
  }
  const unpacked = path.join(process.resourcesPath, 'app.asar.unpacked');
  if (fs.existsSync(path.join(unpacked, 'scripts', 'system', 'Collect-HomeStats.ps1'))) {
    return unpacked;
  }
  const extraScripts = path.join(process.resourcesPath, 'scripts');
  if (fs.existsSync(path.join(extraScripts, 'system', 'Collect-HomeStats.ps1'))) {
    return process.resourcesPath;
  }
  return unpacked;
}

/** HIDUSBF : dev tools/hidusbf ; build app.asar.unpacked/tools ou resources/tools */
function getToolsDir() {
  if (!app.isPackaged) {
    return path.join(getBundledContentRoot(), 'tools');
  }
  const candidates = [
    path.join(process.resourcesPath, 'app.asar.unpacked', 'tools'),
    path.join(process.resourcesPath, 'tools'),
    path.join(getBundledContentRoot(), 'tools'),
    path.join(getAppRoot(), 'resources', 'tools')
  ];
  for (const dir of candidates) {
    if (fs.existsSync(path.join(dir, 'hidusbf', 'HIDUSBF_AS.INF'))) {
      return dir;
    }
  }
  return path.join(getBundledContentRoot(), 'tools');
}

/** Dossier d’installation (répertoire de l’EXE) */
function getAppRoot() {
  if (!app.isPackaged) {
    return path.join(__dirname, '..', '..');
  }
  return path.dirname(app.getPath('exe'));
}

function getScriptsDir() {
  return path.join(getBundledContentRoot(), 'scripts');
}

/** Logs en userData en build (écriture garantie hors Program Files) */
function getLogsDir() {
  if (app.isPackaged) {
    return path.join(app.getPath('userData'), 'logs');
  }
  return path.join(getAppRoot(), 'logs');
}

function resolveScriptPath(relativePath) {
  return path.join(getScriptsDir(), relativePath.replace(/\//g, path.sep));
}

function scriptExists(relativePath) {
  return fs.existsSync(resolveScriptPath(relativePath));
}

function getSettingsPath() {
  return path.join(getLogsDir(), 'app-settings.json');
}

module.exports = {
  getAppRoot,
  getBundledContentRoot,
  getToolsDir,
  getScriptsDir,
  getLogsDir,
  getSettingsPath,
  resolveScriptPath,
  scriptExists
};
