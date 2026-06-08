const fs = require('fs');
const path = require('path');
const { shell } = require('electron');
const { spawn } = require('child_process');
const { getInstallersDir } = require('./paths');
const { runPs1ExitCode } = require('./ps-exit-runner');

const APP_RUNNER_LOG = path.join(
  process.env.ProgramData || path.join(process.env.SystemDrive || 'C:', 'ProgramData'),
  'Kojo',
  'Logs',
  'applications-runner.log'
);

const LOG_PREFIX = {
  discord: 'APP_DISCORD',
  battlenet: 'APP_BATTLENET',
  obs: 'APP_OBS'
};

const OPTIMIZE_SCRIPT = {
  discord: 'applications/discord/Optimize-Discord.ps1',
  battlenet: 'applications/battlenet/Optimize-BattleNet.ps1',
  obs: 'applications/obs/Optimize-OBS.ps1'
};

const INSTALLER_DEF = {
  discord: { subdir: 'applications/discord', file: 'DiscordSetup.exe' },
  battlenet: { subdir: 'applications/battlenet', file: 'BattleNetSetup.exe' },
  obs: { subdir: 'applications/obs', file: 'OBSSetup.exe' }
};

const APP_DEFS = {
  discord: {
    downloadUrl: 'https://discord.com/download',
    find() {
      const updateExe = path.join(process.env.LOCALAPPDATA || '', 'Discord', 'Update.exe');
      if (fs.existsSync(updateExe)) {
        return { type: 'exe', exe: updateExe, args: ['--processStart', 'Discord.exe'], cwd: undefined };
      }
      const discordDir = path.join(process.env.LOCALAPPDATA || '', 'Discord');
      if (fs.existsSync(discordDir)) {
        const appDirs = fs.readdirSync(discordDir)
          .filter((name) => name.startsWith('app-'))
          .sort()
          .reverse();
        for (const appDir of appDirs) {
          const exe = path.join(discordDir, appDir, 'Discord.exe');
          if (fs.existsSync(exe)) {
            return { type: 'exe', exe, args: [], cwd: path.dirname(exe) };
          }
        }
      }
      const lnk = path.join(
        process.env.APPDATA || '',
        'Microsoft',
        'Windows',
        'Start Menu',
        'Programs',
        'Discord Inc',
        'Discord.lnk'
      );
      if (fs.existsSync(lnk)) {
        return { type: 'lnk', path: lnk };
      }
      return null;
    }
  },
  battlenet: {
    downloadUrl: 'https://download.battle.net/',
    find() {
      const candidates = [
        path.join(process.env['ProgramFiles(x86)'] || '', 'Battle.net', 'Battle.net Launcher.exe'),
        path.join(process.env.ProgramFiles || '', 'Battle.net', 'Battle.net Launcher.exe')
      ];
      for (const exe of candidates) {
        if (fs.existsSync(exe)) {
          return { type: 'exe', exe, args: [], cwd: path.dirname(exe) };
        }
      }
      const lnk = path.join(
        process.env.ProgramData || '',
        'Microsoft',
        'Windows',
        'Start Menu',
        'Programs',
        'Battle.net',
        'Battle.net.lnk'
      );
      if (fs.existsSync(lnk)) {
        return { type: 'lnk', path: lnk };
      }
      return null;
    }
  },
  obs: {
    downloadUrl: 'https://obsproject.com/download',
    find() {
      const candidates = [
        path.join(process.env.ProgramFiles || '', 'obs-studio', 'bin', '64bit', 'obs64.exe'),
        path.join(process.env['ProgramFiles(x86)'] || '', 'obs-studio', 'bin', '64bit', 'obs64.exe')
      ];
      for (const exe of candidates) {
        if (fs.existsSync(exe)) {
          return { type: 'exe', exe, args: [], cwd: path.dirname(exe) };
        }
      }
      const lnk = path.join(
        process.env.ProgramData || '',
        'Microsoft',
        'Windows',
        'Start Menu',
        'Programs',
        'OBS Studio',
        'OBS Studio.lnk'
      );
      if (fs.existsSync(lnk)) {
        return { type: 'lnk', path: lnk };
      }
      return null;
    }
  }
};

function appRunnerLog(line) {
  try {
    const dir = path.dirname(APP_RUNNER_LOG);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(APP_RUNNER_LOG, `[${new Date().toISOString()}] ${line}\n`, 'utf8');
  } catch {
    /* ignore */
  }
  console.log(line);
}

function formatLaunchCommand(target) {
  if (!target) return '';
  if (target.type === 'lnk') return `shell.openPath ${target.path}`;
  const args = (target.args || []).map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(' ');
  return args ? `"${target.exe}" ${args}` : `"${target.exe}"`;
}

function getLocalInstallerPath(appId) {
  const def = INSTALLER_DEF[appId];
  if (!def) return null;
  const installerPath = path.join(getInstallersDir(), def.subdir, def.file);
  return fs.existsSync(installerPath) ? installerPath : null;
}

function launchTarget(target) {
  if (!target) {
    return { ok: false };
  }
  try {
    if (target.type === 'lnk') {
      shell.openPath(target.path);
      return { ok: true };
    }
    const opts = {
      detached: true,
      stdio: 'ignore',
      windowsHide: true
    };
    if (target.cwd) opts.cwd = target.cwd;
    spawn(target.exe, target.args || [], opts).unref();
    return { ok: true };
  } catch {
    return { ok: false };
  }
}

function detectApplication(appId) {
  const def = APP_DEFS[appId];
  if (!def) {
    return { ok: false, installed: false, hasLocalInstaller: false };
  }
  const target = def.find();
  const installerPath = getLocalInstallerPath(appId);
  return {
    ok: true,
    installed: !!target,
    hasLocalInstaller: !!installerPath,
    data: {
      launchType: target?.type || null,
      installerPath: installerPath || null
    }
  };
}

async function openApplication(appId) {
  const prefix = LOG_PREFIX[appId];
  const def = APP_DEFS[appId];
  if (!def || !prefix) {
    return { ok: false, status: 'error', message: 'Application inconnue.' };
  }

  const target = def.find();
  if (target) {
    const command = formatLaunchCommand(target);
    appRunnerLog(`${prefix}_OPEN_COMMAND=${command}`);
    const launched = launchTarget(target);
    const exitCode = launched.ok ? 0 : 1;
    appRunnerLog(`${prefix}_OPEN_EXIT_CODE=${exitCode}`);
    if (!launched.ok) {
      return { ok: false, status: 'error', message: 'Impossible de lancer l\'application.' };
    }
    return { ok: true, status: 'launched', message: 'Application lancée.' };
  }

  const installerPath = getLocalInstallerPath(appId);
  if (installerPath) {
    appRunnerLog(`${prefix}_OPEN_COMMAND="${installerPath}"`);
    try {
      spawn(installerPath, [], { detached: true, stdio: 'ignore', windowsHide: false }).unref();
      appRunnerLog(`${prefix}_OPEN_EXIT_CODE=0`);
      return { ok: true, status: 'setup_launched', message: 'Installation lancée.' };
    } catch {
      appRunnerLog(`${prefix}_OPEN_EXIT_CODE=1`);
      return { ok: false, status: 'error', message: 'Impossible de lancer l\'installateur.' };
    }
  }

  try {
    appRunnerLog(`${prefix}_OPEN_COMMAND=openExternal ${def.downloadUrl}`);
    await shell.openExternal(def.downloadUrl);
    appRunnerLog(`${prefix}_OPEN_EXIT_CODE=0`);
    return {
      ok: true,
      status: 'download_opened',
      message: 'Application non détectée. Ouverture du téléchargement officiel.'
    };
  } catch {
    appRunnerLog(`${prefix}_OPEN_EXIT_CODE=1`);
    return { ok: false, status: 'error', message: 'Application non détectée.' };
  }
}

async function optimizeApplication(appId) {
  const prefix = LOG_PREFIX[appId];
  const scriptRel = OPTIMIZE_SCRIPT[appId];
  if (!prefix || !scriptRel) {
    return { ok: false, status: 'error', message: 'Application inconnue.' };
  }

  const result = await runPs1ExitCode(scriptRel, { captureStdout: true, timeoutMs: 300000 });
  appRunnerLog(`${prefix}_OPTIMIZE_COMMAND=${result.commandLine}`);
  appRunnerLog(`${prefix}_OPTIMIZE_EXIT_CODE=${result.exitCode}`);

  const stdout = result.stdout || '';
  const limited = stdout.includes('BATTLENET_CONFIG_NOT_FOUND')
    || stdout.includes('OBS_SAFE_OPTIMIZATION_LIMITED')
    || stdout.includes('DISCORD_SETTINGS_NOT_FOUND');

  if (result.exitCode === 0) {
    const messages = {
      discord: 'Discord optimisé. Redémarrage de Discord conseillé.',
      battlenet: limited
        ? 'Battle.net détecté, optimisation limitée.'
        : 'Battle.net optimisé. Relance Battle.net conseillée.',
      obs: 'OBS optimisé. Vérifie ton profil OBS avant stream/enregistrement.'
    };
    return {
      ok: true,
      status: limited ? 'optimized_limited' : 'optimized',
      message: messages[appId] || 'Application optimisée.'
    };
  }

  return {
    ok: false,
    status: 'error',
    message: 'Impossible d\'optimiser l\'application.'
  };
}

/** @deprecated alias */
const openApp = openApplication;

module.exports = {
  detectApplication,
  openApplication,
  optimizeApplication,
  openApp
};
