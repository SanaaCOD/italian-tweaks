const { contextBridge, ipcRenderer } = require('electron');

/** API preload interne (nom historique italianTweaks — non affiché à l'utilisateur). */
contextBridge.exposeInMainWorld('italianTweaks', {
  app: {
    getBuildInfo: () => ipcRenderer.invoke('app:getBuildInfo')
  },
  system: {
    getStats: (opts) => ipcRenderer.invoke('system:getStats', opts),
    restoreDefaults: () => ipcRenderer.invoke('system:restoreDefaults'),
    revertAll: () => ipcRenderer.invoke('system:revertAll'),
    masterRunAll: () => ipcRenderer.invoke('system:masterRunAll')
  },
  controllerOc: {
    isElevated: () => ipcRenderer.invoke('controllerOc:isElevated'),
    enumerate: () => ipcRenderer.invoke('controllerOc:enumerate'),
    applyOverclock: (instanceId, usbParentId, rateHz) =>
      ipcRenderer.invoke('controllerOc:applyOverclock', instanceId, usbParentId, rateHz),
    removeOverclock: (instanceId, usbParentId) =>
      ipcRenderer.invoke('controllerOc:removeOverclock', instanceId, usbParentId)
  },
  drivers: {
    getNvidiaStatus: () => ipcRenderer.invoke('drivers:getNvidiaStatus'),
    runDdu: () => ipcRenderer.invoke('drivers:runDdu'),
    runNvclean: () => ipcRenderer.invoke('drivers:runNvclean'),
    installLatest: () => ipcRenderer.invoke('drivers:installLatest'),
    applyOptimization: () => ipcRenderer.invoke('drivers:applyOptimization'),
    applySqEngine: () => ipcRenderer.invoke('drivers:applySqEngine'),
    nvidiaGuide: () => ipcRenderer.invoke('drivers:nvidiaGuide'),
    gpuOverclock: () => ipcRenderer.invoke('drivers:gpuOverclock'),
    openNip: () => ipcRenderer.invoke('drivers:openNip')
  },
  network: {
    status: () => ipcRenderer.invoke('network:status'),
    gaming: () => ipcRenderer.invoke('network:gaming'),
    download: () => ipcRenderer.invoke('network:download'),
    restore: () => ipcRenderer.invoke('network:restore'),
    applyTcpGaming: () => ipcRenderer.invoke('network:applyTcpGaming'),
    optimization: () => ipcRenderer.invoke('network:optimization'),
    tcp: () => ipcRenderer.invoke('network:tcp'),
    runNetworkTest: () => ipcRenderer.invoke('network:runNetworkTest'),
    onNetworkTestProgress: (callback) => {
      if (typeof callback !== 'function') return () => {};
      const handler = (_event, payload) => callback(payload);
      ipcRenderer.on('network:testProgress', handler);
      return () => ipcRenderer.removeListener('network:testProgress', handler);
    }
  },
  optimModules: {
    apply: (payload) => ipcRenderer.invoke('optim:modulesApply', payload)
  },
  optim: {
    status: () => ipcRenderer.invoke('optim:status'),
    debloat: () => ipcRenderer.invoke('optim:debloat'),
    debloatRestore: () => ipcRenderer.invoke('optim:debloatRestore'),
    gameMode: () => ipcRenderer.invoke('optim:gameMode'),
    gameModeRestore: () => ipcRenderer.invoke('optim:gameModeRestore'),
    power: () => ipcRenderer.invoke('optim:power'),
    powerRestore: () => ipcRenderer.invoke('optim:powerRestore'),
    windowed: () => ipcRenderer.invoke('optim:windowed'),
    windows: () => ipcRenderer.invoke('optim:windows'),
    deepDebloat: () => ipcRenderer.invoke('optim:deepDebloat'),
    undoDeepDebloat: () => ipcRenderer.invoke('optim:undoDeepDebloat'),
    copilot: () => ipcRenderer.invoke('optim:copilot'),
    wuOff: () => ipcRenderer.invoke('optim:wuOff'),
    wuOn: () => ipcRenderer.invoke('optim:wuOn'),
    standard: () => ipcRenderer.invoke('optim:standard')
  },
  audio: {
    status: () => ipcRenderer.invoke('audio:status'),
    apply: () => ipcRenderer.invoke('audio:apply'),
    restore: () => ipcRenderer.invoke('audio:restore'),
    openSettings: () => ipcRenderer.invoke('audio:openSettings')
  },
  games: {
    warzoneDetect: () => ipcRenderer.invoke('games:warzoneDetect'),
    warzoneApply: () => ipcRenderer.invoke('games:warzoneApply'),
    warzoneRestore: () => ipcRenderer.invoke('games:warzoneRestore'),
    apply: (gameId) => ipcRenderer.invoke('games:apply', gameId),
    list: () => Promise.resolve([
      'blackops7', 'fortnite', 'valorant', 'cs2', 'arcraiders', 'apex', 'tarkov', 'rust',
      'r6', 'battlefield6', 'marvelrivals', 'lol', 'dota2', 'fivem', 'eafc26', 'overwatch2', 'marathon', 'rocketleague'
    ])
  },
  settings: {
    get: () => ipcRenderer.invoke('settings:get'),
    save: (d) => ipcRenderer.invoke('settings:save', d),
    reset: () => ipcRenderer.invoke('settings:reset')
  },
  updates: {
    check: () => ipcRenderer.invoke('updates:check'),
    download: () => ipcRenderer.invoke('updates:download'),
    install: () => ipcRenderer.invoke('updates:install'),
    getStatus: () => ipcRenderer.invoke('updates:getStatus'),
    getVersion: () => ipcRenderer.invoke('updates:getVersion'),
    onStatus: (callback) => {
      if (typeof callback !== 'function') return () => {};
      const handler = (_event, payload) => callback(payload);
      ipcRenderer.on('updates:status', handler);
      return () => ipcRenderer.removeListener('updates:status', handler);
    }
  }
});
