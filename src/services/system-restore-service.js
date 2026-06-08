const fs = require('fs');
const path = require('path');
const { runPs1ExitCode } = require('./ps-exit-runner');
const { isProcessElevated } = require('./controller-oc');

const SYSTEM_RUNNER_LOG = path.join(
  process.env.ProgramData || path.join(process.env.SystemDrive || 'C:', 'ProgramData'),
  'Kojo',
  'Logs',
  'system-runner.log'
);

const MSG_ADMIN = 'Lance Kojo en administrateur pour créer un point de restauration.';

function systemRunnerLog(line) {
  try {
    const dir = path.dirname(SYSTEM_RUNNER_LOG);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(SYSTEM_RUNNER_LOG, `[${new Date().toISOString()}] ${line}\n`, 'utf8');
  } catch {
    /* ignore */
  }
  console.log(line);
}

async function createRestorePoint() {
  systemRunnerLog('RESTORE_POINT_MANUAL_START');

  if (!isProcessElevated()) {
    systemRunnerLog('RESTORE_POINT_OK=false');
    return {
      ok: false,
      status: 'error',
      message: MSG_ADMIN
    };
  }

  const result = await runPs1ExitCode('system/Create-RestorePoint.ps1', {
    captureStdout: true,
    timeoutMs: 300000
  });

  systemRunnerLog(`RESTORE_POINT_COMMAND=${result.commandLine}`);
  systemRunnerLog(`RESTORE_POINT_EXIT_CODE=${result.exitCode}`);

  const stdout = result.stdout || '';
  const rateLimited = stdout.includes('RESTORE_POINT_SKIPPED_RATE_LIMIT');

  if (result.exitCode === 0) {
    if (rateLimited) {
      systemRunnerLog('RESTORE_POINT_SKIPPED_RATE_LIMIT=true');
      return {
        ok: true,
        status: 'rate_limited',
        message: 'Un point de restauration récent existe déjà.'
      };
    }
    systemRunnerLog('RESTORE_POINT_OK=true');
    return {
      ok: true,
      status: 'success',
      message: 'Point de restauration créé.'
    };
  }

  systemRunnerLog('RESTORE_POINT_OK=false');
  return {
    ok: false,
    status: 'error',
    message: 'Impossible de créer le point de restauration.'
  };
}

module.exports = { createRestorePoint };
