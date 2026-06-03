window.ItUi = {
  escape(s) {
    const d = document.createElement('div');
    d.textContent = String(s ?? '');
    return d.innerHTML;
  },

  actionCard({ title, text, status = '', statusType = 'neutral', script = '', actions = [], cardId = '' }) {
    const sc = statusType === 'ok' ? 'status-ok' : statusType === 'warn' ? 'status-warn' : statusType === 'err' ? 'status-err' : statusType === 'pending' ? 'status-pending' : '';
    const btns = actions.map((a) =>
      `<button type="button" class="btn ${a.primary ? 'btn--primary' : 'btn--ghost'}" data-action="${a.id}"${a.disabled ? ' disabled' : ''}>${this.escape(a.label)}</button>`
    ).join('');
    const idAttr = cardId ? ` data-card-id="${this.escape(cardId)}"` : '';
    return `
      <article class="action-card" data-script="${this.escape(script)}"${idAttr}>
        <div class="action-card__head">
          <h3 class="action-card__title">${this.escape(title)}</h3>
          <span class="action-card__status ${sc}">${this.escape(status || 'Prêt')}</span>
        </div>
        <p class="action-card__text">${this.escape(text)}</p>
        ${script ? `<p class="action-card__script">${this.escape(script)}</p>` : ''}
        <div class="action-card__actions">${btns}</div>
        <pre class="action-card__log" hidden></pre>
      </article>`;
  },

  bindActions(root, handlers) {
    if (!root) return;
    root.querySelectorAll('[data-action]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const fn = handlers[btn.dataset.action];
        if (fn) fn(btn);
      });
    });
  },

  showResult(result, statusEl) {
    const r = result || {};
    const msg = r.message || r.status || '';
    if (statusEl?.matches?.('[data-ctrl-feedback]')) {
      statusEl.hidden = false;
      statusEl.textContent = r.ok
        ? (msg || 'Done')
        : (r.message ? String(r.message).slice(0, 160) : 'Error');
      statusEl.classList.toggle('ctrl-device__feedback--ok', !!r.ok);
      statusEl.classList.toggle('ctrl-device__feedback--err', !r.ok && r.status !== 'cancelled');
    } else if (statusEl) {
      if (r.status === 'not_implemented') {
        statusEl.textContent = 'À implémenter';
        statusEl.className = 'action-card__status status-warn';
      } else if (r.ok) {
        statusEl.textContent = r.status === 'ready' ? 'Prêt' : 'Succès';
        statusEl.className = 'action-card__status status-ok';
      } else if (r.status === 'cancelled') {
        statusEl.textContent = 'Annulé';
        statusEl.className = 'action-card__status status-pending';
      } else {
        statusEl.textContent = r.message ? String(r.message).slice(0, 120) : 'Erreur';
        statusEl.className = 'action-card__status status-err';
      }
    }
    const card = statusEl?.closest('.action-card');
    const log = card?.querySelector('.action-card__log');
    if (log) {
      log.hidden = false;
      log.textContent = JSON.stringify(r, null, 2);
    }
    this.toast(msg, !r.ok && r.status !== 'not_implemented' && r.status !== 'cancelled');
  },

  toast(msg, isError) {
    if (!msg) return;
    let el = document.getElementById('it-toast');
    if (!el) {
      el = document.createElement('div');
      el.id = 'it-toast';
      el.className = 'toast';
      document.body.appendChild(el);
    }
    el.textContent = msg;
    el.classList.toggle('toast--error', !!isError);
    el.classList.add('toast--visible');
    clearTimeout(el._t);
    el._t = setTimeout(() => el.classList.remove('toast--visible'), 5000);
  }
};
