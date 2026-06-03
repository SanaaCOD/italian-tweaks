/** Chargement async non bloquant + logs de navigation. */
window.ItPageLoader = {
  READ_MS: 4500,

  log(pageId, phase, ms) {
    const tail = ms != null ? ` ${Math.round(ms)}ms` : '';
    console.log(`[Nav ${pageId}] ${phase}${tail}`);
  },

  run(ipcPromise, timeoutMs = this.READ_MS) {
    return Promise.race([
      Promise.resolve(ipcPromise),
      new Promise((_, reject) => {
        setTimeout(() => reject(Object.assign(new Error('timeout'), { code: 'TIMEOUT' })), timeoutMs);
      })
    ]);
  },

  setCardStatus(main, cardId, status, statusType = 'pending') {
    const card = main?.querySelector?.(`[data-card-id="${cardId}"]`);
    const el = card?.querySelector('.action-card__status');
    if (!el) return;
    const map = { ok: 'status-ok', warn: 'status-warn', err: 'status-err', pending: 'status-pending', neutral: '' };
    el.textContent = status;
    el.className = `action-card__status ${map[statusType] || map.pending}`;
  },

  setCardText(main, cardId, text) {
    const card = main?.querySelector?.(`[data-card-id="${cardId}"]`);
    const el = card?.querySelector('.action-card__text');
    if (el) el.textContent = text;
  }
};
