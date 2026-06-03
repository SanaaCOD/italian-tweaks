const { runScript } = require('./script-runner');

module.exports = {
  getStatus: () => runScript('optimizations/Get-OptimizationStatus.ps1', [], { read: true }),
  applyDebloat: () => runScript('optimizations/Apply-Debloat.ps1', [], { timeoutMs: 600000 }),
  restoreDebloat: () => runScript('optimizations/Restore-Debloat.ps1', [], { timeoutMs: 600000 }),
  applyGameMode: () => runScript('optimizations/Apply-GameMode.ps1'),
  restoreGameMode: () => runScript('optimizations/Restore-GameMode.ps1'),
  applyPowerPlan: () => runScript('optimizations/Apply-PowerPlan.ps1'),
  restorePowerPlan: () => runScript('optimizations/Restore-PowerPlan.ps1'),
  applyWindowedGameOptimizations: () => runScript('optimizations/Apply-WindowedGameOptimizations.ps1'),
  applyWindowsOptimization: () => runScript('optimizations/Apply-WindowsOptimization.ps1'),
  applyDeepDebloat: () => runScript('optimizations/Apply-DeepDebloat.ps1', [], { timeoutMs: 600000 }),
  undoDeepDebloat: () => runScript('optimizations/Undo-DeepDebloat.ps1', [], { timeoutMs: 600000 }),
  disableCopilot: () => runScript('optimizations/Disable-Copilot.ps1'),
  windowsUpdateOff: () => runScript('optimizations/Windows-Update-Off.ps1'),
  windowsUpdateOn: () => runScript('optimizations/Windows-Update-On.ps1'),
  standardWindowsSettings: () => runScript('optimizations/Apply-StandardWindowsSettings.ps1')
};
