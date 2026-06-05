const { spawn } = require('child_process');
const path = require('path');
const { resolveScriptPath } = require('./paths');
const { buildPowerShellFileArgs } = require('./ps-exec');

const DEFAULT_TIMEOUT_MS = 600000;

/**
 * Lance un script .ps1 et retourne uniquement le code de sortie (pas de parsing stdout).
 */
function runPs1ExitCode(relativePath, options = {}) {
  const scriptPath = path.resolve(resolveScriptPath(relativePath));
  const extraArgs = options.extraArgs || [];
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  let psArgs;
  try {
    psArgs = buildPowerShellFileArgs(scriptPath, {}, extraArgs);
  } catch (err) {
    return Promise.resolve({
      ok: false,
      exitCode: -1,
      commandLine: `powershell.exe -File ${scriptPath}`,
      error: String(err.message || err)
    });
  }

  const commandLine = `powershell.exe ${psArgs.map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(' ')}`;

  return new Promise((resolve) => {
    const child = spawn('powershell.exe', psArgs, {
      windowsHide: true,
      shell: false
    });

    let settled = false;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ ...result, commandLine });
    };

    const timer = setTimeout(() => {
      try {
        child.kill();
      } catch {
        /* ignore */
      }
      finish({ ok: false, exitCode: -2, error: 'timeout' });
    }, timeoutMs);

    child.on('error', (err) => {
      finish({ ok: false, exitCode: -1, error: String(err.message || err) });
    });

    child.on('close', (code) => {
      finish({ ok: code === 0, exitCode: code ?? -1 });
    });
  });
}

module.exports = { runPs1ExitCode };
