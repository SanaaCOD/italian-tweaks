const path = require('path');
const fs = require('fs');
const { app } = require('electron');

/** Racine dev (repo) ou resources/ en build — un seul arbre scripts (extraResources). */
function getBundledContentRoot() {
  if (!app.isPackaged) {
    return path.join(__dirname, '..', '..');
  }
  return process.resourcesPath;
}

/** Scripts PowerShell : uniquement resources/scripts (TunedPC). */
function getScriptsDir() {
  if (!app.isPackaged) {
    return path.join(__dirname, '..', '..', 'scripts');
  }
  return path.join(process.resourcesPath, 'scripts');
}

/** HIDUSBF bundle (TunedPC: resources/hidusbf uniquement). */
function getHidusbfDriverDir() {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'hidusbf');
  }
  const bundled = path.join(getBundledContentRoot(), 'resources', 'hidusbf');
  if (fs.existsSync(path.join(bundled, 'HIDUSBF_AS.INF'))) {
    return bundled;
  }
  return bundled;
}

/** Outils tiers (DDU, etc.) — jamais HIDUSBF. */
function getToolsDir() {
  if (!app.isPackaged) {
    return path.join(getBundledContentRoot(), 'tools');
  }
  const dir = path.join(process.resourcesPath, 'tools');
  if (fs.existsSync(dir)) {
    return dir;
  }
  return path.join(getBundledContentRoot(), 'tools');
}

function getAppRoot() {
  if (!app.isPackaged) {
    return getBundledContentRoot();
  }
  return path.dirname(app.getPath('exe'));
}

function resolveScriptPath(relativePath) {
  return path.join(getScriptsDir(), relativePath.replace(/\//g, path.sep));
}

function scriptExists(relativePath) {
  return fs.existsSync(resolveScriptPath(relativePath));
}

function getLogsDir() {
  if (app.isPackaged) {
    return path.join(app.getPath('userData'), 'logs');
  }
  return path.join(getAppRoot(), 'logs');
}

function getSettingsPath() {
  return path.join(getLogsDir(), 'app-settings.json');
}

module.exports = {
  getAppRoot,
  getBundledContentRoot,
  getHidusbfDriverDir,
  getToolsDir,
  getScriptsDir,
  getLogsDir,
  getSettingsPath,
  resolveScriptPath,
  scriptExists
};
