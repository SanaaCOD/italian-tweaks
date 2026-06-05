const { runPs1ExitCode } = require('./ps-exit-runner');
const fs = require('fs');
const path = require('path');
const { isProcessElevated } = require('./controller-oc');

const ENABLE_SCRIPT = 'optimizations/debloat/enable.ps1';
const DISABLE_SCRIPT = 'optimizations/debloat/disable.ps1';

const MSG_ADMIN = 'Lance Kojo en administrateur pour appliquer le Debloat.';
const MSG_ENABLE_OK = 'Extreme Gaming Debloat appliqué. Redémarrage conseillé.';
const MSG_DISABLE_OK = 'Debloat restauré. Redémarrage conseillé.';
const MSG_ENABLE_ERR = 'Erreur Debloat. Consulte les logs.';
const MSG_DISABLE_ERR = 'Erreur restauration Debloat. Consulte les logs.';

const RUNNER_LOG = path.join(
  process.env.ProgramData || path.join(process.env.SystemDrive || 'C:', 'ProgramData'),
  'Kojo',
  'Logs',
  'debloat-runner.log'
);

function runnerLog(line) {
  try {
    const dir = path.dirname(RUNNER_LOG);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(RUNNER_LOG, `[${new Date().toISOString()}] ${line}\n`, 'utf8');
  } catch {
    /* ignore */
  }
  console.log(line);
}

async function runDebloat(enable) {
  runnerLog('DEBLOAT_UI_APPLY_CLICK');
  runnerLog(`DEBLOAT_TOGGLE_STATE=${enable ? 'on' : 'off'}`);

  if (!isProcessElevated()) {
    return { ok: false, status: 'error', exitCode: -1, message: MSG_ADMIN };
  }

  const relativePath = enable ? ENABLE_SCRIPT : DISABLE_SCRIPT;
  const result = await runPs1ExitCode(relativePath, { extraArgs: ['-Force'] });
  const cmdTag = enable ? 'DEBLOAT_ENABLE_COMMAND' : 'DEBLOAT_DISABLE_COMMAND';
  const exitTag = enable ? 'DEBLOAT_ENABLE_EXIT_CODE' : 'DEBLOAT_DISABLE_EXIT_CODE';
  runnerLog(`${cmdTag}=${result.commandLine}`);
  runnerLog(`${exitTag}=${result.exitCode}`);

  return {
    ok: result.ok,
    status: result.ok ? 'success' : 'error',
    exitCode: result.exitCode,
    message: result.ok
      ? (enable ? MSG_ENABLE_OK : MSG_DISABLE_OK)
      : (enable ? MSG_ENABLE_ERR : MSG_DISABLE_ERR)
  };
}

function enable() {
  return runDebloat(true);
}

function disable() {
  return runDebloat(false);
}

module.exports = { enable, disable, runnerLog };
