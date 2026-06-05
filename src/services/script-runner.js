const { spawn, execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { getBundledContentRoot, getLogsDir, resolveScriptPath, scriptExists } = require('./paths');
const { logStatsDiag } = require('./stats-diag');
const { buildPowerShellFileArgs, logPowerShellArgs } = require('./ps-exec');

const DEFAULT_READ_MS = 4500;
const DEFAULT_ACTION_MS = 300000;

/**
 * Exécute scripts/<relativePath> et retourne le JSON du contrat Kojo.
 * options.read=true → timeout court (lecture statut, 4,5 s).
 */
function runScript(relativePath, extraArgs = [], options = {}) {
  const timeoutMs = options.timeoutMs ?? (options.read ? DEFAULT_READ_MS : DEFAULT_ACTION_MS);
  const appRoot = path.resolve(getBundledContentRoot());
  const scriptPath = path.resolve(resolveScriptPath(relativePath));
  const logDir = path.resolve(getLogsDir());
  const exists = fs.existsSync(scriptPath);

  if (!exists) {
    logStatsDiag(`runScript MISSING relative=${relativePath} scriptPath=${scriptPath}`);
    return Promise.resolve(
      normalizeResult(null, `Script introuvable: ${scriptPath}`, -1, relativePath, scriptPath)
    );
  }

  let psArgs;
  try {
    psArgs = buildPowerShellFileArgs(scriptPath, {
      '-AppRoot': appRoot,
      '-LogDir': logDir
    }, extraArgs);
  } catch (err) {
    return Promise.resolve(
      normalizeResult(null, String(err.message), -1, relativePath, scriptPath)
    );
  }

  logPowerShellArgs(`runScript relative=${relativePath}`, psArgs);

  return new Promise((resolve) => {
    const child = spawn('powershell.exe', psArgs, {
      cwd: appRoot,
      windowsHide: true,
      shell: false
    });

    let stdout = '';
    let stderr = '';
    let settled = false;

    const finish = (json, errText, code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(normalizeResult(json, errText, code, relativePath, scriptPath, stdout));
    };

    const timer = setTimeout(() => {
      try {
        if (options.killProcessTree && process.platform === 'win32' && child.pid) {
          try {
            execSync(`taskkill /F /T /PID ${child.pid}`, { windowsHide: true, stdio: 'ignore' });
          } catch {
            child.kill();
          }
        } else {
          child.kill();
        }
      } catch {
        /* ignore */
      }
      logStatsDiag(`runScript TIMEOUT ${timeoutMs}ms relative=${relativePath}`);
      finish(
        null,
        options.read ? 'Délai dépassé — vérification en arrière-plan' : 'Délai dépassé',
        -2
      );
    }, timeoutMs);

    child.stdout.on('data', (d) => { stdout += d.toString('utf8'); });
    child.stderr.on('data', (d) => { stderr += d.toString('utf8'); });

    child.on('error', (err) => {
      logStatsDiag(`runScript error relative=${relativePath} err=${err.message}`);
      finish(null, stderr || String(err), -1);
    });

    child.on('close', (code) => {
      const json = parseJsonStdout(stdout);
      if (!json?.ok) {
        logStatsDiag(
          `runScript close code=${code} relative=${relativePath} stderr=${(stderr || '').slice(0, 400)} ` +
          `stdoutTail=${(stdout || '').slice(-400)}`
        );
      }
      finish(json, stderr, code);
    });
  });
}

function parseJsonStdout(stdout) {
  const trimmed = (stdout || '').trim();
  if (!trimmed) return null;
  const lines = trimmed.split(/\r?\n/).filter((l) => l.trim().startsWith('{'));
  for (let i = lines.length - 1; i >= 0; i--) {
    try {
      return JSON.parse(lines[i]);
    } catch {
      /* try prev */
    }
  }
  try {
    return JSON.parse(trimmed);
  } catch {
    return null;
  }
}

function normalizeResult(json, stderr, exitCode, script, scriptPath, stdout = '') {
  if (json && typeof json.ok === 'boolean') {
    const outTail = (stdout || '').trim();
    return {
      ...json,
      exitCode,
      stderr: stderr || undefined,
      stdout: outTail ? outTail.slice(-800) : undefined,
      script,
      scriptPath
    };
  }
  return {
    ok: false,
    status: 'error',
    message: stderr || `Réponse JSON invalide (${script})`,
    action: script,
    data: null,
    exitCode,
    stderr,
    scriptPath
  };
}

module.exports = { runScript, parseJsonStdout, scriptExists };
