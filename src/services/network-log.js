const fs = require('fs');
const path = require('path');
const os = require('os');

function getNetworkLogDir() {
  const programData = process.env.ProgramData
    || path.join(process.env.SystemDrive || 'C:', 'ProgramData');
  return path.join(programData, 'Kojo', 'Logs');
}

function getNetworkLogPath() {
  return path.join(getNetworkLogDir(), 'network.log');
}

function ensureNetworkLogDir() {
  const dir = getNetworkLogDir();
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function networkLog(tag, extra = '') {
  const line = extra ? `[network] ${tag} ${extra}` : `[network] ${tag}`;
  console.log(line);
  try {
    ensureNetworkLogDir();
    const entry = `[${new Date().toISOString()}] ${tag}${extra ? ` ${extra}` : ''}\n`;
    fs.appendFileSync(getNetworkLogPath(), entry, 'utf8');
  } catch {
    /* ignore */
  }
}

module.exports = { networkLog, getNetworkLogPath };
