const fs = require('fs');
const path = require('path');
const { getLogsDir } = require('./paths');

function logStatsDiag(line) {
  const msg = `[${new Date().toISOString()}] ${line}`;
  console.log(`[ITALIAN-TWEAKS stats] ${line}`);
  try {
    const dir = getLogsDir();
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(path.join(dir, 'stats-diag.log'), `${msg}\n`, 'utf8');
  } catch {
    /* ignore */
  }
}

module.exports = { logStatsDiag };
