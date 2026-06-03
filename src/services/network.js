const { runScript } = require('./script-runner');

module.exports = {
  getStatus: () => runScript('network/Get-NetworkStatus.ps1', [], { read: true }),
  applyGamingProfile: () => runScript('network/Apply-GamingNetworkProfile.ps1'),
  applyDownloadProfile: () => runScript('network/Apply-DownloadNetworkProfile.ps1'),
  restoreDefaults: () => runScript('network/Restore-NetworkDefaults.ps1'),
  applyOptimization: () => runScript('network/Apply-NetworkOptimization.ps1'),
  applyLatencyReduction: () => runScript('network/Apply-LatencyReduction.ps1'),
  launchTcpOptimizer: () => runScript('network/Launch-TcpOptimizer.ps1')
};
