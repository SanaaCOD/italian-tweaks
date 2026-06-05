const { runScript } = require('./script-runner');
const { networkLog } = require('./network-log');
const {
  runBufferbloatTest,
  isTestRunning,
  mapResultToKojo
} = require('./bufferbloat-test');

function netLog(tag, extra = '') {
  networkLog(tag, extra);
}

async function runNetwork(relativePath, options = {}) {
  const { tagStart, tagResult, read, timeoutMs } = options;
  if (tagStart) netLog(tagStart);
  const result = await runScript(relativePath, [], { read, timeoutMs });
  if (tagResult) {
    netLog(tagResult, `ok=${!!result?.ok} status=${result?.status || '?'}`);
  }
  return result;
}

module.exports = {
  getStatus: () => runNetwork('network/Get-NetworkConnectionStatus.ps1', {
    read: true,
    tagStart: 'NETWORK_DETECT_START',
    tagResult: 'NETWORK_DETECT_RESULT'
  }),

  applyGamingProfile: async () => {
    netLog('NETWORK_PROFILE_APPLY_START', 'gaming');
    const result = await runScript('network/Apply-GamingNetworkProfile.ps1');
    netLog('NETWORK_PROFILE_APPLY_RESULT', `ok=${!!result?.ok} profile=gaming`);
    if (result?.ok) netLog('NETWORK_PROFILE_ACTIVE', 'gaming');
    return result;
  },

  applyDownloadProfile: async () => {
    netLog('NETWORK_PROFILE_APPLY_START', 'download');
    const result = await runScript('network/Apply-DownloadNetworkProfile.ps1');
    netLog('NETWORK_PROFILE_APPLY_RESULT', `ok=${!!result?.ok} profile=download`);
    if (result?.ok) netLog('NETWORK_PROFILE_ACTIVE', 'download');
    return result;
  },

  restoreDefaults: async () => {
    netLog('NETWORK_RESTORE_START');
    const result = await runScript('network/Restore-TcpNetwork.ps1');
    const exitCode = result?.data?.exitCode ?? result?.exitCode ?? '?';
    netLog('NETWORK_RESTORE_EXIT_CODE', String(exitCode));
    if (result?.stdout) {
      netLog('NETWORK_RESTORE_STDOUT', String(result.stdout).slice(0, 600));
    }
    if (result?.stderr) {
      netLog('NETWORK_RESTORE_STDERR', String(result.stderr).slice(0, 600));
    }
    const confirmed = result?.ok === true || result?.data?.confirmed === true;
    netLog('NETWORK_RESTORE_CONFIRMED', String(confirmed));
    netLog('NETWORK_RESTORE_RESULT', `ok=${!!result?.ok} status=${result?.status || '?'}`);
    if (confirmed) {
      await runNetwork('network/Get-NetworkConnectionStatus.ps1', {
        read: true,
        tagStart: 'NETWORK_DETECT_START',
        tagResult: 'NETWORK_DETECT_RESULT'
      });
    }
    return result;
  },

  applyTcpGaming: async () => {
    netLog('NETWORK_APPLY_START', 'kind=tcp-gaming');
    const dl = await runScript('network/Download-TcpOptimizer.ps1');
    if (dl?.data?.path) netLog('TCP_OPTIMIZER_PATH', dl.data.path);
    const result = await runScript('network/Apply-TcpGamingProfile.ps1');
    netLog('NETWORK_APPLY_RESULT', `kind=tcp-gaming ok=${!!result?.ok}`);
    return result;
  },

  launchTcpOptimizer: async () => {
    netLog('TCP_OPTIMIZER_PATH', 'check');
    const dl = await runScript('network/Download-TcpOptimizer.ps1');
    if (dl?.data?.path) netLog('TCP_OPTIMIZER_PATH', dl.data.path);
    netLog('TCP_OPTIMIZER_RUN');
    return runScript('network/Launch-TcpOptimizer.ps1');
  },

  /** Compat preload — même workflow que applyTcpGaming */
  applyOptimization: () => module.exports.applyTcpGaming(),

  runNetworkTest: async () => {
    if (isTestRunning()) {
      netLog('NETWORK_TEST_ERROR', 'already_running');
      return {
        ok: false,
        status: 'busy',
        message: 'Un test est déjà en cours.',
        data: null
      };
    }

    netLog('NETWORK_TEST_START');

    try {
      const raw = await runBufferbloatTest((progress) => {
        netLog('NETWORK_TEST_PROGRESS', `phase=${progress.phase} overall=${Math.round(progress.overallProgress || 0)}`);
      });

      const data = mapResultToKojo(raw);
      netLog('NETWORK_TEST_RESULT', `grade=${data.grade} download=${data.downloadMbps ?? 'N/D'} upload=${data.uploadMbps ?? 'N/D'} delta=${data.bufferbloatDeltaMs ?? 'N/D'}`);

      return {
        ok: true,
        status: 'success',
        message: 'Test réseau terminé',
        data
      };
    } catch (err) {
      const code = err?.code || 'ERROR';
      const message = err instanceof Error ? err.message : String(err);

      if (code === 'TIMEOUT') {
        netLog('NETWORK_TEST_TIMEOUT');
        return {
          ok: false,
          status: 'timeout',
          message: 'Test interrompu — relance le test.',
          data: {
            partial: true,
            aborted: true,
            statusLabel: 'Test interrompu',
            gradeDisplay: '—',
            partialMessage: 'Test interrompu — relance le test.'
          }
        };
      }

      netLog('NETWORK_TEST_ERROR', message);
      return {
        ok: false,
        status: 'error',
        message,
        data: {
          partial: false,
          aborted: false,
          statusLabel: 'Erreur',
          gradeDisplay: '—',
          partialMessage: message
        }
      };
    }
  }
};
