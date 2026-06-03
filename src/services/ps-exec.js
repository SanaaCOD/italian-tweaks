const path = require('path');
const { logStatsDiag } = require('./stats-diag');

/**
 * Arguments PowerShell pour -File (scriptPath immédiatement après -File, sans shell).
 */
function buildPowerShellFileArgs(scriptPath, namedParams = {}, trailingArgs = []) {
  const script = path.resolve(String(scriptPath || ''));
  if (!script.toLowerCase().endsWith('.ps1')) {
    throw new Error(`Chemin script invalide (extension .ps1 requise): ${script}`);
  }

  const psArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script];

  for (const [key, value] of Object.entries(namedParams)) {
    if (value === undefined || value === null) continue;
    const s = String(value);
    if (s === '') continue;
    psArgs.push(key, s);
  }

  for (let i = 0; i < trailingArgs.length; i += 2) {
    const flag = trailingArgs[i];
    const val = trailingArgs[i + 1];
    if (!flag || val === undefined || val === null || String(val) === '') continue;
    psArgs.push(flag, String(val));
  }

  return psArgs;
}

function logPowerShellArgs(label, psArgs) {
  const msg = `${label} argv=${JSON.stringify(psArgs)}`;
  logStatsDiag(msg);
}

module.exports = { buildPowerShellFileArgs, logPowerShellArgs };
