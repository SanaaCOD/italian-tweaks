const fs = require('fs');
const { getSettingsPath, getLogsDir } = require('./paths');
const { ensureDir } = require('./ps-runner');

const DEFAULTS = {
  theme: 'dark',
  language: 'fr',
  confirmDangerousActions: true,
  showHiddenLogs: false
};

function load() {
  const p = getSettingsPath();
  try {
    if (fs.existsSync(p)) {
      return { ...DEFAULTS, ...JSON.parse(fs.readFileSync(p, 'utf8')) };
    }
  } catch {
    /* ignore */
  }
  return { ...DEFAULTS };
}

function save(partial) {
  ensureDir(getLogsDir());
  const next = { ...load(), ...partial };
  fs.writeFileSync(getSettingsPath(), JSON.stringify(next, null, 2), 'utf8');
  return next;
}

function reset() {
  ensureDir(getLogsDir());
  const next = { ...DEFAULTS };
  fs.writeFileSync(getSettingsPath(), JSON.stringify(next, null, 2), 'utf8');
  return next;
}

module.exports = { load, save, reset, DEFAULTS };
