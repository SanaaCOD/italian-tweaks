/** Appels IPC + retour UI standardisé */
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
    check: () => window.italianTweaks.updates.check(),
    download: () => window.italianTweaks.updates.download(),
    install: () => window.italianTweaks.updates.install(),
    getStatus: () => window.italianTweaks.updates.getStatus(),
    getVersion: () => window.italianTweaks.updates.getVersion(),
    onStatus: (callback) => window.italianTweaks.updates.onStatus(callback)
  }
};
