/** Cache mémoire des dernières réponses par onglet (affichage immédiat). */
window.ItPageCache = {
  _store: Object.create(null),

  get(pageId) {
    return this._store[pageId] ?? null;
  },

  set(pageId, payload) {
    if (payload == null) return;
    this._store[pageId] = { payload, at: Date.now() };
  },

  clear(pageId) {
    if (pageId) delete this._store[pageId];
    else this._store = Object.create(null);
  }
};
