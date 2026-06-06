/** Appels IPC + retour UI standardisé */
function kojoApi() {
  return window.kojo || window.italianTweaks;
}

function itUpdatesApi() {
  const u = kojoApi()?.updates;
  if (!u) {
    const missing = () => Promise.resolve({
      ok: false,
      status: 'error',
      message: 'API updates indisponible (preload)',
      data: {}
    });
    return {
      check: missing,
      download: missing,
      install: missing,
      getStatus: () => Promise.resolve({ ok: true, status: 'idle', data: {} }),
      getVersion: () => Promise.resolve({ ok: true, data: { version: '?' } }),
      onStatus: () => () => {}
    };
  }
  return u;
}

window.ItApi = {
  async run(invokeFn, buttonEl) {
    const card = buttonEl?.closest('.action-card');
    const statusEl = card?.querySelector('.action-card__status')
      || buttonEl?.closest('.ctrl-device')?.querySelector('[data-ctrl-feedback]');
    if (buttonEl) buttonEl.disabled = true;
    if (statusEl) statusEl.textContent = 'En cours…';
    try {
      const result = await invokeFn();
      ItUi.showResult(result, statusEl);
      return result;
    } catch (e) {
      const err = { ok: false, status: 'error', message: String(e.message || e) };
      ItUi.showResult(err, statusEl);
      return err;
    } finally {
      if (buttonEl) buttonEl.disabled = false;
    }
  },

  bindPage(root, handlers) {
    ItUi.bindActions(root, Object.fromEntries(
      Object.entries(handlers).map(([id, fn]) => [id, (btn) => ItApi.run(() => fn(btn), btn)])
    ));
  },

  updates: {
    check: () => itUpdatesApi().check(),
    download: () => itUpdatesApi().download(),
    install: () => itUpdatesApi().install(),
    getStatus: () => itUpdatesApi().getStatus(),
    getVersion: () => itUpdatesApi().getVersion(),
    onStatus: (callback) => itUpdatesApi().onStatus(callback)
  },
  app: {
    getBuildInfo: () => kojoApi()?.app?.getBuildInfo?.() ?? Promise.resolve({
      version: '?',
      displayLine: 'v? · build ? · local',
      devMode: true,
      packaged: false
    })
  }
};
