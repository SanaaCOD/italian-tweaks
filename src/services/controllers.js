const { runScript } = require('./script-runner');

function deviceArgs(device) {
  const d = device || {};
  return [
    '-InstanceId', d.instanceId || d.InstanceId || d.deviceInstanceId || d.DeviceInstanceId || '',
    '-ControllerId', d.id || d.CardId || d.controllerId || '',
    '-Type', d.type || d.Type || '',
    '-Vid', d.vendorId || d.Vid || d.vid || '',
    '-controllerProductId', d.productId || d.Pid || d.pid || ''
  ];
}

module.exports = {
  list: () => runScript('controllers/Get-Controllers.ps1', [], { read: true, timeoutMs: 5000 }),
  applyPolling: (device, targetHz) => {
    const d = device || {};
    const hz = targetHz || d.targetPollingRate || (d.type === 'PS5' ? 8000 : 1000);
    return runScript('controllers/Apply-ControllerPolling.ps1', [
      ...deviceArgs(d),
      '-TargetHz', String(hz)
    ], { timeoutMs: 300000 });
  },
  restorePolling: (device) =>
    runScript('controllers/Restore-ControllerPolling.ps1', deviceArgs(device), { timeoutMs: 300000 }),
  applyControllerOc: (device) =>
    runScript('controllers/Apply-ControllerOC.ps1', [
      '-DeviceInstanceId', device?.instanceId || device?.DeviceInstanceId || ''
    ], { timeoutMs: 300000 }),
  detectUsb: () => runScript('controllers/Detect-USBDevices.ps1', [], { read: true })
};
