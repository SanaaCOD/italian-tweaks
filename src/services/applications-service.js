const fs = require('fs');
const path = require('path');
const { shell } = require('electron');
const { spawn } = require('child_process');

const APP_DEFS = {
  discord: {
    downloadUrl: 'https://discord.com/download',
    find() {
      const updateExe = path.join(process.env.LOCALAPPDATA || '', 'Discord', 'Update.exe');
      if (fs.existsSync(updateExe)) {
        return { exe: updateExe, args: ['--processStart', 'Discord.exe'] };
      }
      const discordDir = path.join(process.env.LOCALAPPDATA || '', 'Discord');
      if (!fs.existsSync(discordDir)) return null;
      const appDirs = fs.readdirSync(discordDir)
        .filter((name) => name.startsWith('app-'))
        .sort()
        .reverse();
      for (const appDir of appDirs) {
        const exe = path.join(discordDir, appDir, 'Discord.exe');
        if (fs.existsSync(exe)) return { exe, args: [] };
      }
      return null;
    }
  },
  battlenet: {
    downloadUrl: 'https://www.battle.net/download',
    find() {
      const candidates = [
        path.join(process.env['ProgramFiles(x86)'] || '', 'Battle.net', 'Battle.net Launcher.exe'),
        path.join(process.env.ProgramFiles || '', 'Battle.net', 'Battle.net Launcher.exe')
      ];
      for (const exe of candidates) {
        if (fs.existsSync(exe)) return { exe, args: [] };
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
        if (fs.existsSync(exe)) return { exe, args: [] };
      }
      return null;
    }
  }
};

async function openApp(appId) {
  const def = APP_DEFS[appId];
  if (!def) {
    return { ok: false, status: 'error', message: 'Application non détectée.' };
  }

  const found = def.find();
  if (found) {
    try {
      spawn(found.exe, found.args || [], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
      return { ok: true, status: 'success', message: 'Application lancée.' };
    } catch {
      return { ok: false, status: 'error', message: 'Impossible de lancer l\'application.' };
    }
  }

  try {
    await shell.openExternal(def.downloadUrl);
    return { ok: false, status: 'not_installed', message: 'Application non détectée.' };
  } catch {
    return { ok: false, status: 'error', message: 'Application non détectée.' };
  }
}

module.exports = { openApp };
