const fs = require('fs');
const path = require('path');
const { runPs1ExitCode } = require('./ps-exit-runner');
const debloatService = require('./debloat-service');
const { isProcessElevated } = require('./controller-oc');

const OPTIM_RUNNER_LOG = path.join(
  process.env.ProgramData || path.join(process.env.SystemDrive || 'C:', 'ProgramData'),
  'Kojo',
  'Logs',
  'optimization-runner.log'
);

const MSG_ADMIN = 'Lance Kojo en administrateur pour appliquer cette optimisation.';

const MODULES = [
  {
    key: 'debloat',
    label: 'Debloat',
    needsAdmin: true,
    run: (enable) => (enable ? debloatService.enable() : debloatService.disable())
  },
  {
    key: 'gameMode',
    label: 'Mode Jeu',
    enableScript: 'optimizations/mode-jeu/enable.ps1',
    disableScript: 'optimizations/mode-jeu/disable.ps1',
    logPrefix: 'GAMEMODE',
    needsAdmin: false
  },
  {
    key: 'power',
    label: 'Gestion de l\'alimentation',
    enableScript: 'optimizations/gestion-alimentation/enable.ps1',
    disableScript: 'optimizations/gestion-alimentation/disable.ps1',
    logPrefix: 'POWER',
    needsAdmin: true
  },
  {
    key: 'regXboxMonitoring',
    label: 'Xbox Game Monitoring',
    enableScript: 'optimizations/registry/xbox-game-monitoring/enable.ps1',
    disableScript: 'optimizations/registry/xbox-game-monitoring/disable.ps1',
    logPrefix: 'REG_XBOX_GAMEMONITORING',
    needsAdmin: true
  },
  {
    key: 'regGameBarDvr',
    label: 'Game Bar / GameDVR',
    enableScript: 'optimizations/registry/gamebar-dvr/enable.ps1',
    disableScript: 'optimizations/registry/gamebar-dvr/disable.ps1',
    logPrefix: 'REG_GAMEBAR',
    needsAdmin: false
  },
  {
    key: 'regGamesMmcss',
    label: 'Priorité Jeux MMCSS',
    enableScript: 'optimizations/registry/games-mmcss/enable.ps1',
    disableScript: 'optimizations/registry/games-mmcss/disable.ps1',
    logPrefix: 'REG_GAMES_MMCSS',
    needsAdmin: true
  },
  {
    key: 'regMouseRaw',
    label: 'Souris précision brute',
    enableScript: 'optimizations/registry/mouse-raw/enable.ps1',
    disableScript: 'optimizations/registry/mouse-raw/disable.ps1',
    logPrefix: 'REG_MOUSE',
    needsAdmin: false
  },
  {
    key: 'regMultimediaProfile',
    label: 'Profil Multimédia Gaming',
    enableScript: 'optimizations/registry/multimedia-profile/enable.ps1',
    disableScript: 'optimizations/registry/multimedia-profile/disable.ps1',
    logPrefix: 'REG_MULTIMEDIA',
    needsAdmin: true
  },
  {
    key: 'regTcpipLowLatency',
    label: 'TCP/IP faible latence',
    enableScript: 'optimizations/registry/tcpip-low-latency/enable.ps1',
    disableScript: 'optimizations/registry/tcpip-low-latency/disable.ps1',
    logPrefix: 'REG_TCPIP',
    needsAdmin: true
  },
  {
    key: 'regVisualEffects',
    label: 'Effets visuels performance',
    enableScript: 'optimizations/registry/visual-effects-performance/enable.ps1',
    disableScript: 'optimizations/registry/visual-effects-performance/disable.ps1',
    logPrefix: 'REG_VISUAL_EFFECTS',
    needsAdmin: false
  }
];

function optimRunnerLog(line) {
  try {
    const dir = path.dirname(OPTIM_RUNNER_LOG);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(OPTIM_RUNNER_LOG, `[${new Date().toISOString()}] ${line}\n`, 'utf8');
  } catch {
    /* ignore */
  }
  console.log(line);
}

async function runScriptModule(mod, enable) {
  if (mod.needsAdmin && !isProcessElevated()) {
    return { ok: false, status: 'error', exitCode: -1, message: MSG_ADMIN };
  }

  const relativePath = enable ? mod.enableScript : mod.disableScript;
  const result = await runPs1ExitCode(relativePath);
  const cmdTag = enable ? `${mod.logPrefix}_ENABLE_COMMAND` : `${mod.logPrefix}_DISABLE_COMMAND`;
  const exitTag = enable ? `${mod.logPrefix}_ENABLE_EXIT_CODE` : `${mod.logPrefix}_DISABLE_EXIT_CODE`;
  optimRunnerLog(`${cmdTag}=${result.commandLine}`);
  optimRunnerLog(`${exitTag}=${result.exitCode}`);

  if (result.ok) {
    return {
      ok: true,
      status: 'success',
      exitCode: result.exitCode,
      message: `${mod.label} ${enable ? 'activé' : 'désactivé'}.`
    };
  }

  return {
    ok: false,
    status: 'error',
    exitCode: result.exitCode,
    message: `Erreur ${mod.label}. Consulte optimization-runner.log.`
  };
}

function buildChanges(ui, saved) {
  const changes = [];
  for (const mod of MODULES) {
    const uiOn = !!ui[mod.key];
    const savedOn = !!saved[mod.key];
    if (uiOn === savedOn) continue;
    changes.push({ mod, enable: uiOn });
  }
  return changes;
}

async function applyModules(payload) {
  const ui = payload?.ui || {};
  const saved = { ...(payload?.saved || {}) };
  const changes = buildChanges(ui, saved);

  if (!changes.length) {
    return {
      ok: true,
      status: 'noop',
      message: 'Aucune modification à appliquer.',
      data: { saved }
    };
  }

  optimRunnerLog(`apply start modules=${changes.map((c) => c.mod.key).join(',')}`);

  for (const { mod, enable } of changes) {
    const result = mod.run
      ? await mod.run(enable)
      : await runScriptModule(mod, enable);

    if (!result.ok) {
      return {
        ok: false,
        status: result.status || 'error',
        message: result.message,
        data: { saved }
      };
    }

    saved[mod.key] = enable;
  }

  optimRunnerLog('apply done ok=true');

  return {
    ok: true,
    status: 'success',
    message: 'Optimisations appliquées.',
    data: { saved }
  };
}

module.exports = { applyModules };
