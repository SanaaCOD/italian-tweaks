/* Pages Kojo — chaque bouton → IPC → script .ps1 */
window.ItPages = {
  _api() {
    return window.kojo || window.italianTweaks;
  },
  /** Lit data.cpu / data.gpu / data.ram (objet .usage ou nombre) */
  _normalizeAccueilStats(r) {
    const raw = r?.data ?? r ?? {};
    const pick = (key) => {
      const block = raw[key];
      if (block == null) return null;
      if (typeof block === 'number') return Number.isNaN(block) ? null : block;
      if (typeof block === 'object' && block.usage != null && block.usage !== '') {
        const n = Number(block.usage);
        return Number.isNaN(n) ? null : n;
      }
      return null;
    };
    return {
      cpu: pick('cpu'),
      gpu: pick('gpu'),
      ram: pick('ram'),
      cpuName: raw.cpu?.name || 'CPU',
      gpuName: raw.gpu?.name || 'GPU',
      ramMeta: raw.ram || {},
      timestamp: raw.timestamp || '',
      windows: raw.windows || {},
      uptime: raw.uptime || ''
    };
  },

  _fmtPct(v) {
    if (v === null || v === undefined || Number.isNaN(Number(v))) return 'N/D';
    return `${v}%`;
  },

  _logAccueilUi(phase, received, applied) {
    const line = `[Accueil stats] ${phase} reçu cpu=${received.cpu} gpu=${received.gpu} ram=${received.ram} → appliqué cpu=${applied.cpu} gpu=${applied.gpu} ram=${applied.ram}`;
    console.log(line);
  },

  _header(title, subtitle) {
    return `<header class="page-header"><h1 class="page-header__title">${ItUi.escape(title)}</h1>${subtitle ? `<p class="page-header__subtitle">${ItUi.escape(subtitle)}</p>` : ''}</header>`;
  },

  _mapController(c) {
    if (!c) return null;
    const typeRaw = String(c.type || c.Type || 'other');
    const typeNorm = {
      ps5: 'PS5', ps4: 'PS4', xbox: 'Xbox', nintendo: 'Generic', mouse: 'Generic', other: 'Generic'
    };
    const type = typeNorm[typeRaw.toLowerCase()] || (typeRaw === 'DualSense' ? 'PS5' : typeRaw);
    const maxHz = Number(c.maxPollingRate ?? c.maxRateHz ?? c.MaxRateHz ?? (type === 'PS5' ? 8000 : 1000));
    const curHz = Number(c.currentPollingRate ?? c.currentRateHz ?? c.currentHz ?? 0);
    const inst = c.instanceId || c.InstanceId || c.deviceInstanceId || '';
    const parent = c.usbParentId || c.hidusbfTargetId || c.parentInstanceId || inst;
    return {
      id: c.id || c.CardId || parent || inst,
      name: c.name || c.friendlyName || c.DisplayName || 'Manette',
      type,
      vendorId: c.vendorId || c.Vid || '',
      productId: c.productId || c.Pid || '',
      instanceId: inst,
      parentInstanceId: parent,
      devicePath: c.devicePath || c.instanceId || '',
      present: c.present !== false,
      currentPollingRate: curHz,
      targetPollingRate: Number(c.targetPollingRate ?? (type === 'PS5' ? 8000 : 1000)),
      maxPollingRate: maxHz,
      canBoost: c.canBoost === true || (c.hasFilter !== true && type !== 'mouse'),
      boostButton: c.boostButton || (c.hasFilter ? 'remove' : (type === 'PS5' ? '8000' : '1000')),
      hidusbfTargetReliable: c.hidusbfTargetReliable !== false && Boolean(parent),
      compatible: c.compatible === true || (c.hidusbfTargetReliable !== false && c.present !== false),
      recommendedAction: c.recommendedAction || '',
      pollingLabel: c.pollingLabel || (curHz ? `${curHz} Hz` : 'Inconnu'),
      statusBadge: c.statusBadge || '—',
      statusBadgeType: c.statusBadgeType || 'neutral',
      hidusbfTargetId: parent,
      hasFilter: c.hasFilter === true
    };
  },

  _normalizeControllers(payload) {
    if (Array.isArray(payload?.devices)) {
      return payload.devices.map((x) => this._mapController(x)).filter(Boolean);
    }
    if (Array.isArray(payload?.controllers)) {
      return payload.controllers.map((x) => this._mapController(x)).filter(Boolean);
    }
    const data = payload?.data ?? payload ?? {};
    if (Array.isArray(data.devices)) {
      return data.devices.map((x) => this._mapController(x)).filter(Boolean);
    }
    let c = data.controllers;
    if (Array.isArray(c)) return c.map((x) => this._mapController(x)).filter(Boolean);
    if (c?.value && Array.isArray(c.value)) return c.value.map((x) => this._mapController(x)).filter(Boolean);
    return [];
  },

  _hidusbfFromPayload(payload) {
    const data = payload?.data ?? payload ?? {};
    const h = data.hidusbf ?? payload?.hidusbf;
    if (h && typeof h === 'object') {
      return {
        available: h.available !== false && h.ok !== false,
        message: h.message || ''
      };
    }
    const p = payload?.prerequisites;
    if (p && typeof p === 'object') {
      const ok = p.hidusbfDriverAvailable === true || p.ok === true;
      return { available: ok, message: ok ? 'HIDUSBF OK' : 'HIDUSBF missing' };
    }
    return { available: true, message: '' };
  },

  _mountPage(main, title, subtitle) {
    main.innerHTML = `${this._header(title, subtitle)}<div class="card-grid" id="pg"></div>`;
    return document.getElementById('pg');
  },

  _fetchInBackground(pageId, main, ipcFn, onData, onError) {
    const navGen = main.dataset.navGen;
    const cached = ItPageCache.get(pageId);
    if (cached?.payload != null) {
      ItPageLoader.log(pageId, 'cache affiché', 0);
      onData(cached.payload, true);
    }
    const t0 = performance.now();
    ItPageLoader.run(ipcFn(), ItPageLoader.READ_MS)
      .then((payload) => {
        if (main.dataset.navGen !== navGen) return;
        ItPageCache.set(pageId, payload);
        ItPageLoader.log(pageId, 'données reçues', performance.now() - t0);
        if (main.isConnected) onData(payload, false);
      })
      .catch((err) => {
        if (main.dataset.navGen !== navGen) return;
        ItPageLoader.log(pageId, err?.code === 'TIMEOUT' ? 'timeout UI' : 'erreur', performance.now() - t0);
        if (main.isConnected) onError(err);
      });
  },

  renderAccueil(main, cached) {
    const pageId = 'accueil';
    const t0 = performance.now();
    const r = cached || ItPageCache.get(pageId)?.payload || null;
    const s = this._normalizeAccueilStats(r || {});
    const applied = {
      cpu: r ? this._fmtPct(s.cpu) : '…',
      gpu: r ? this._fmtPct(s.gpu) : '…',
      ram: r ? this._fmtPct(s.ram) : '…'
    };
    if (r) this._logAccueilUi('render', s, applied);
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);
    main.innerHTML = `
      <div class="page-accueil">
        ${this._header('Accueil')}
        <section class="hero"><div class="hero__inner">
          <span class="hero__brand">Kojo Performance Suite</span>
          <div class="hero__logo-wrap"><img class="hero__logo" src="../../assets/logo.png" alt="Kojo" /></div>
          <p class="hero__slogan">Performance. Précision. Contrôle.</p>
        </div></section>
        <div class="accueil-meta">
          <p class="status-line" data-live="timestamp">${ItUi.escape(s.timestamp || '')}</p>
          <p class="status-line">${ItUi.escape(s.windows?.caption || '')} · Uptime ${ItUi.escape(s.uptime || '—')}</p>
        </div>
        <h2 class="section-title">COMPOSANTS SYSTÈME</h2>
        <div class="component-grid">
          ${this._hw('cpu', 'CPU', 'CHARGE', applied.cpu, s.cpuName)}
          ${this._hw('gpu', 'GPU', 'CHARGE', applied.gpu, s.gpuName)}
          ${this._hw('ram', 'RAM', 'USAGE', applied.ram, [s.ramMeta.modules, s.ramMeta.speed, `XMP: ${s.ramMeta.xmp || 'N/D'}`].filter(Boolean).join('\n'))}
        </div>
        <div class="card-grid page-actions">
          ${ItUi.actionCard({ title: 'Protection système', text: 'Crée un point de restauration Windows avant de modifier des réglages système.', cardId: 'restore-point-card', actions: [{ id: 'create-restore-point', label: 'Créer un point de restauration', primary: true }] })}
          ${ItUi.actionCard({ title: 'Restaurer défauts', text: 'Restaure les réglages système par défaut.', script: 'system/Restore-Defaults.ps1', actions: [{ id: 'restore-def', label: 'Exécuter', primary: true }] })}
          ${ItUi.actionCard({ title: 'Tout annuler', text: 'Annule les modifications Kojo en une passe.', script: 'system/Revert-All.ps1', actions: [{ id: 'revert-all', label: 'Exécuter', primary: true }] })}
        </div>
      </div>`;
    const grid = main.querySelector('.page-actions');
    ItApi.bindPage(grid, {
      'restore-def': () => ItPages._api().system.restoreDefaults(),
      'revert-all': () => ItPages._api().system.revertAll()
    });

    const restoreBtn = grid?.querySelector('[data-action="create-restore-point"]');
    if (restoreBtn) {
      restoreBtn.addEventListener('click', async () => {
        if (restoreBtn.disabled) return;
        const card = restoreBtn.closest('.action-card');
        const statusEl = card?.querySelector('.action-card__status');
        restoreBtn.disabled = true;
        if (statusEl) {
          statusEl.textContent = 'Création en cours…';
          statusEl.className = 'action-card__status status-pending';
        }
        ItUi.toast('Création du point de restauration…', false);
        try {
          const r = await ItPages._api().system.createRestorePoint();
          if (r?.status === 'rate_limited') {
            if (statusEl) {
              statusEl.textContent = 'Point récent existant';
              statusEl.className = 'action-card__status status-warn';
            }
            ItUi.toast('Un point de restauration récent existe déjà.', false);
            return;
          }
          if (r?.ok) {
            if (statusEl) {
              statusEl.textContent = 'Créé';
              statusEl.className = 'action-card__status status-ok';
            }
            ItUi.toast('Point de restauration créé.', false);
            return;
          }
          if (statusEl) {
            statusEl.textContent = 'Échec';
            statusEl.className = 'action-card__status status-err';
          }
          ItUi.toast('Impossible de créer le point de restauration.', true);
        } catch {
          if (statusEl) {
            statusEl.textContent = 'Échec';
            statusEl.className = 'action-card__status status-err';
          }
          ItUi.toast('Impossible de créer le point de restauration.', true);
        } finally {
          restoreBtn.disabled = false;
        }
      });
    }

    if (!r) {
      this._fetchInBackground(
        pageId,
        main,
        () => ItPages._api().system.getStats({ full: true }),
        (payload) => {
          ItPageCache.set(pageId, payload);
          this.updateAccueilStats(main, payload);
        },
        () => { /* stats refresh 8s réessaiera */ }
      );
    }
  },

  /** Mise à jour légère des % sans reconstruire le hero */
  updateAccueilStats(main, r) {
    if (!main?.querySelector?.('.page-accueil')) return;
    const s = this._normalizeAccueilStats(r);
    const applied = {
      cpu: this._fmtPct(s.cpu),
      gpu: this._fmtPct(s.gpu),
      ram: this._fmtPct(s.ram)
    };
    this._logAccueilUi('update', s, applied);
    const set = (sel, text) => {
      const el = main.querySelector(sel);
      if (el) el.textContent = text;
    };
    set('[data-live="cpu-usage"]', applied.cpu);
    set('[data-live="gpu-usage"]', applied.gpu);
    set('[data-live="ram-usage"]', applied.ram);
    const ts = main.querySelector('[data-live="timestamp"]');
    if (ts && s.timestamp) ts.textContent = s.timestamp;
  },

  _hw(type, label, badge, val, detail) {
    const det = String(detail || '').includes('\n')
      ? String(detail).split('\n').map((l) => `<div>${ItUi.escape(l)}</div>`).join('')
      : `<div>${ItUi.escape(detail)}</div>`;
    const live = type === 'cpu' ? 'cpu-usage' : type === 'gpu' ? 'gpu-usage' : 'ram-usage';
    return `<article class="component-card component-card--${type}"><div class="component-card__inner">
      <div class="component-card__top">
        <div class="component-card__head"><div class="component-card__label-row"><span class="component-card__diamond"></span>${label}</div><span class="badge">${badge}</span></div>
        <div class="component-card__value" data-live="${live}">${ItUi.escape(val)}</div>
      </div>
      <div class="component-card__detail">${det}</div></div></article>`;
  },

  _controllerTypeBadge(type) {
    const map = {
      PS5: 'PS5 DUALSENSE',
      PS4: 'PS4 DUALSHOCK',
      Xbox: 'XBOX CONTROLLER',
      Generic: 'HID CONTROLLER'
    };
    return map[type] || 'CONTROLLER';
  },

  _controllerDisplayTitle(c) {
    const name = (c.name || '').trim();
    if (name && !/^manette$/i.test(name)) return name;
    if (c.type === 'PS5') return 'PS5 DualSense';
    if ((c.parentInstanceId || '').match(/composite/i)) return 'Périphérique USB composite';
    return name || 'USB Controller';
  },

  _controllerIsBoosted(c) {
    if (c.hasFilter === true) return true;
    const cur = Number(c.currentPollingRate) || 0;
    const max = Number(c.maxPollingRate) || 1000;
    if (max >= 8000) return cur >= 8000;
    return cur >= 1000;
  },

  _controllerResponseTime(c) {
    const hz = Number(c.currentPollingRate) || 125;
    if (hz >= 8000) return '0.125ms';
    if (hz >= 1000) return '1ms';
    return '8ms';
  },

  _controllerPotential(c) {
    return this._controllerIsBoosted(c) ? 'Maxed' : 'Can improve';
  },

  _controllerBoostHz(c) {
    return c.type === 'PS5' ? 8000 : 1000;
  },

  _controllerCanBoost(c, hidusbf) {
    if (hidusbf?.available === false) return false;
    if (this._controllerIsBoosted(c)) return false;
    if (c.type === 'Generic' && c.hidusbfTargetReliable === false) return false;
    if (c.compatible === false) return false;
    return true;
  },

  _countBoostedControllers(list) {
    return list.filter((c) => this._controllerIsBoosted(c)).length;
  },

  _PERIPH_NOT_FOUND_MSG: 'Manette non détectée. Débranche/rebranche puis clique Refresh Devices.',
  _PERIPH_ADMIN_MSG: "Lance l'application en administrateur pour modifier HIDUSBF.",
  _PERIPH_STARTUP_DELAYS_MS: [0, 1000, 3000, 5000],
  _PERIPH_REMOVE_DELAYS_MS: [0, 2000, 5000, 8000],

  _periphSleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  },

  _cancelPeripheriquesScans(main) {
    if (!main._itPeriphScanGen) main._itPeriphScanGen = 0;
    main._itPeriphScanGen += 1;
    if (Array.isArray(main._itPeriphScanTimers)) {
      for (const id of main._itPeriphScanTimers) clearTimeout(id);
    }
    main._itPeriphScanTimers = [];
  },

  async _enumeratePeripheriquesFresh() {
    return ItPages._api().controllerOc.enumerate();
  },

  async _ensureControllerOcAdmin() {
    const elevated = await ItPages._api().controllerOc.isElevated();
    if (elevated) return null;
    return {
      ok: false,
      success: false,
      status: 'error',
      message: this._PERIPH_ADMIN_MSG,
      error: this._PERIPH_ADMIN_MSG
    };
  },

  async _runPeripheriquesScanWave(main, delaysMs, opts = {}) {
    const softStart = opts.softStart === true;
    this._cancelPeripheriquesScans(main);
    const gen = main._itPeriphScanGen;
    const navGen = main.dataset.navGen;
    const hidDefault = main._itHidusbf || { available: true };

    if (!main.querySelector('.page-peripheriques')) return null;

    if (!softStart) {
      main._itControllers = [];
      this._updatePeripheriquesView(main, {
        loading: false,
        list: [],
        hidusbf: hidDefault,
        searching: true,
        emptyNotFound: false
      });
    }

    let lastPayload = null;

    for (let i = 0; i < delaysMs.length; i++) {
      const waitMs = i === 0 ? 0 : delaysMs[i] - delaysMs[i - 1];
      if (waitMs > 0) await this._periphSleep(waitMs);
      if (main._itPeriphScanGen !== gen || main.dataset.navGen !== navGen) return null;
      if (!main.querySelector('.page-peripheriques')) return null;

      try {
        lastPayload = await ItPageLoader.run(this._enumeratePeripheriquesFresh(), 120000);
      } catch (err) {
        console.warn('[Périphériques] scan wave err', err?.message || err);
        continue;
      }

      if (main._itPeriphScanGen !== gen || main.dataset.navGen !== navGen) return null;

      const list = this._normalizeControllers(lastPayload);
      const hidusbf = this._hidusbfFromPayload(lastPayload);
      const isLast = i === delaysMs.length - 1;

      if (list.length > 0) {
        this._applyPeripheriquesData(main, lastPayload);
        console.log(`[Périphériques] scan wave ok count=${list.length} attempt=${i + 1}/${delaysMs.length}`);
        return lastPayload;
      }

      if (!isLast) {
        this._updatePeripheriquesView(main, {
          loading: false,
          list: [],
          hidusbf,
          searching: true,
          emptyNotFound: false
        });
      } else {
        this._updatePeripheriquesView(main, {
          loading: false,
          list: [],
          hidusbf,
          searching: false,
          emptyNotFound: true
        });
        console.log('[Périphériques] scan wave empty after all retries');
      }
    }

    return lastPayload;
  },

  _htmlPeripheriquesHeaderMeta(loading, list, hidusbf, searching = false) {
    const boosted = this._countBoostedControllers(list);
    if (searching) {
      return '<span class="ctrl-oc__meta ctrl-oc__meta--pending">Recherche en cours…</span>';
    }
    if (loading) {
      return '<span class="ctrl-oc__meta ctrl-oc__meta--pending">Checking devices…</span>';
    }
    if (hidusbf?.available === false) {
      return '<span class="ctrl-oc__meta ctrl-oc__meta--warn">HIDUSBF missing</span>';
    }
    if (boosted > 0) {
      return `<span class="ctrl-oc__meta ctrl-oc__meta--boosted">${boosted} Boosted</span>`;
    }
    return '<span class="ctrl-oc__meta ctrl-oc__meta--ready">Ready</span>';
  },

  _htmlPeripheriquesDeviceCard(c, index, hidusbf) {
    const boosted = this._controllerIsBoosted(c);
    const atMax = boosted;
    const cur = Number(c.currentPollingRate) || 125;
    const max = Number(c.maxPollingRate) || 1000;
    const canBoost = this._controllerCanBoost(c, hidusbf);
    const boostHz = this._controllerBoostHz(c);
    const stateBadge = boosted ? 'BOOSTED' : 'DEFAULT';
    const typeBadge = this._controllerTypeBadge(c.type);
    const incompatible = c.type === 'Generic' && !c.hidusbfTargetReliable && !boosted;

    let primaryAction = '';
    if (incompatible) {
      primaryAction = '<button type="button" class="ctrl-device__btn ctrl-device__btn--disabled" disabled>Unreliable target</button>';
    } else if (boosted) {
      primaryAction = `<button type="button" class="ctrl-device__btn ctrl-device__btn--remove" data-action="remove-${index}">Remove Boost</button>`;
    } else if (canBoost) {
      primaryAction = `<button type="button" class="ctrl-device__btn ctrl-device__btn--boost" data-action="boost-${index}">Boost to ${boostHz} Hz</button>`;
    } else if (hidusbf?.available === false) {
      primaryAction = '<button type="button" class="ctrl-device__btn ctrl-device__btn--disabled" disabled>HIDUSBF required</button>';
    } else {
      primaryAction = '<button type="button" class="ctrl-device__btn ctrl-device__btn--disabled" disabled>Unavailable</button>';
    }

    const mod = boosted ? 'ctrl-device--boosted' : (incompatible ? 'ctrl-device--warn' : 'ctrl-device--default');
    const maxTag = atMax ? '<span class="ctrl-device__max">MAXIMUM</span>' : '';

    return `
      <article class="ctrl-device ${mod}" data-ctrl-index="${index}">
        <div class="ctrl-device__head">
          <div>
            <h3 class="ctrl-device__title">${ItUi.escape(this._controllerDisplayTitle(c))}</h3>
            <div class="ctrl-device__badges">
              <span class="ctrl-device__chip ctrl-device__chip--type">${ItUi.escape(typeBadge)}</span>
              <span class="ctrl-device__chip ctrl-device__chip--${boosted ? 'boosted' : 'default'}">${stateBadge}</span>
            </div>
          </div>
        </div>
        <div class="ctrl-device__polling">
          <span class="ctrl-device__label">POLLING RATE</span>
          <div class="ctrl-device__rate-row">
            <span class="ctrl-device__rate">${ItUi.escape(`${cur} Hz`)}</span>
            ${maxTag}
          </div>
        </div>
        <div class="ctrl-device__stats">
          <div class="ctrl-device__stat">
            <span class="ctrl-device__label">RESPONSE TIME</span>
            <span class="ctrl-device__value">${ItUi.escape(this._controllerResponseTime(c))}</span>
          </div>
          <div class="ctrl-device__stat">
            <span class="ctrl-device__label">POTENTIAL</span>
            <span class="ctrl-device__value ctrl-device__value--${atMax ? 'maxed' : 'improve'}">${ItUi.escape(this._controllerPotential(c))}</span>
          </div>
        </div>
        ${primaryAction}
        <p class="ctrl-device__feedback" data-ctrl-feedback hidden></p>
        <details class="ctrl-device__how">
          <summary>How it works</summary>
          <p>HIDUSBF patches the USB composite parent (not MI interfaces). Boost via Apply-ControllerOC (${max >= 8000 ? '8000' : '1000'} Hz). Remove Boost via CONTROLLER_OC_UNINSTALL=1.</p>
        </details>
      </article>`;
  },

  _htmlPeripheriquesDevices(list, loading, hidusbf, opts = {}) {
    const searching = opts.searching === true;
    const emptyNotFound = opts.emptyNotFound === true;
    if (loading) {
      return `
        <div class="ctrl-device ctrl-device--scanning">
          <p class="ctrl-device__scan-label">Scanning…</p>
          <p class="ctrl-device__scan-hint">Detecting connected controllers (PnP PresentOnly)</p>
        </div>`;
    }
    if (searching) {
      return `
        <div class="ctrl-device ctrl-device--scanning">
          <p class="ctrl-device__scan-label">Recherche des périphériques...</p>
          <p class="ctrl-device__scan-hint">Détection USB en cours — la manette peut apparaître dans quelques secondes</p>
        </div>`;
    }
    if (!list.length) {
      if (emptyNotFound) {
        return `
        <div class="ctrl-device ctrl-device--empty">
          <p class="ctrl-device__empty-title">${ItUi.escape(this._PERIPH_NOT_FOUND_MSG)}</p>
        </div>`;
      }
      return `
        <div class="ctrl-device ctrl-device--empty">
          <p class="ctrl-device__empty-title">No compatible controller detected</p>
          <p class="ctrl-device__empty-hint">Connect a controller and tap Refresh Devices.</p>
        </div>`;
    }
    return `<div class="ctrl-oc__grid">${list.map((c, i) => this._htmlPeripheriquesDeviceCard(c, i, hidusbf)).join('')}</div>`;
  },

  _htmlPeripheriquesPage({ loading, list, hidusbf }) {
    const refreshDisabled = loading ? ' disabled' : '';
    return `
      <div class="page-peripheriques">
        <section class="ctrl-oc">
          <header class="ctrl-oc__hero">
            <div class="ctrl-oc__hero-left">
              <span class="ctrl-oc__icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" width="28" height="28"><path fill="currentColor" d="M13 2 4 14h7l-1 8 10-14h-7z"/></svg>
              </span>
              <div>
                <h2 class="ctrl-oc__title">Controller Overclocker</h2>
                <p class="ctrl-oc__subtitle">Reduce input lag by overclocking USB polling rate</p>
              </div>
            </div>
            <div class="ctrl-oc__hero-right">
              <span data-slot="ctrl-header-meta">${this._htmlPeripheriquesHeaderMeta(loading, list, hidusbf)}</span>
              <button type="button" class="ctrl-oc__refresh btn btn--ghost" data-action="refresh-devices"${refreshDisabled}>Refresh Devices</button>
            </div>
          </header>
          <div class="ctrl-oc__devices" data-slot="ctrl-dynamic">
            ${this._htmlPeripheriquesDevices(list, loading, hidusbf)}
          </div>
        </section>
      </div>`;
  },

  _bindPeripheriques(main, list, hidusbf) {
    if (!main.querySelector('.page-peripheriques')) return;
    main._itControllers = list;
    main._itHidusbf = hidusbf || { available: true };

    const handlers = {
      'refresh-devices': (btn) => this._refreshPeripheriques(main, btn)
    };

    list.forEach((c, i) => {
      handlers[`boost-${i}`] = (btn) => {
        const label = btn.textContent;
        btn.disabled = true;
        btn.textContent = 'Applying…';
        const hz = this._controllerBoostHz(c);
        const parentId = c.hidusbfTargetId || c.parentInstanceId || c.id;
        return ItApi.run(async () => {
          const denied = await this._ensureControllerOcAdmin();
          if (denied) return denied;
          const result = await ItPages._api().controllerOc.applyOverclock(c.instanceId, parentId, hz);
          const scan = await this._enumeratePeripheriquesFresh();
          this._applyPeripheriquesData(main, scan);
          return result;
        }, btn)
          .finally(() => {
            btn.disabled = false;
            btn.textContent = label;
          });
      };
      handlers[`remove-${i}`] = (btn) => {
        const label = btn.textContent;
        btn.disabled = true;
        btn.textContent = 'Removing…';
        const parentId = c.hidusbfTargetId || c.parentInstanceId || c.id;
        return ItApi.run(async () => {
          const denied = await this._ensureControllerOcAdmin();
          if (denied) return denied;
          const result = await ItPages._api().controllerOc.removeOverclock(c.instanceId, parentId);
          if (result?.controllers?.length || result?.devices?.length) {
            this._applyPeripheriquesData(main, result);
          }
          await this._runPeripheriquesScanWave(main, this._PERIPH_REMOVE_DELAYS_MS, { softStart: true });
          return result;
        }, btn)
          .finally(() => {
            btn.disabled = false;
            btn.textContent = label;
          });
      };
    });

    main._itPeriphHandlers = handlers;
    if (!main._itPeriphDelegate) {
      main._itPeriphDelegate = true;
      main.addEventListener('click', (ev) => {
        const btn = ev.target.closest('.page-peripheriques [data-action]');
        if (!btn || !main.contains(btn)) return;
        const fn = main._itPeriphHandlers?.[btn.dataset.action];
        if (fn) fn(btn);
      });
    }
  },

  _updatePeripheriquesView(main, { loading, list, hidusbf, searching = false, emptyNotFound = false }) {
    const meta = main.querySelector('[data-slot="ctrl-header-meta"]');
    const slot = main.querySelector('[data-slot="ctrl-dynamic"]');
    const refreshBtn = main.querySelector('[data-action="refresh-devices"]');
    const busy = loading || searching;
    if (meta) meta.innerHTML = this._htmlPeripheriquesHeaderMeta(loading, list, hidusbf, searching);
    if (slot) {
      slot.innerHTML = this._htmlPeripheriquesDevices(list, loading, hidusbf, { searching, emptyNotFound });
    }
    if (refreshBtn) refreshBtn.disabled = !!busy;
    const bindList = busy ? [] : list;
    this._bindPeripheriques(main, bindList, hidusbf);
  },

  _renderPeripheriquesShell(main, loading, list, hidusbf) {
    main.innerHTML = this._htmlPeripheriquesPage({ loading, list, hidusbf });
    this._bindPeripheriques(main, list, hidusbf);
  },

  _applyPeripheriquesData(main, payload) {
    const list = this._normalizeControllers(payload);
    const hidusbf = this._hidusbfFromPayload(payload);
    this._updatePeripheriquesView(main, { loading: false, list, hidusbf });
    console.log(`[Périphériques] scan ok count=${list.length} ms=${payload?.data?.scanMs ?? '?'}`);
  },

  _refreshPeripheriques(main, refreshBtn) {
    const pageId = 'peripheriques';
    const t0 = performance.now();
    if (!main.querySelector('.page-peripheriques')) {
      this._renderPeripheriquesShell(main, false, [], { available: true });
    }
    if (refreshBtn) refreshBtn.disabled = true;
    main._itControllers = [];
    void this._runPeripheriquesScanWave(main, this._PERIPH_STARTUP_DELAYS_MS)
      .then(() => ItPageLoader.log(pageId, 'refresh wave done', performance.now() - t0))
      .finally(() => {
        const btn = main.querySelector('[data-action="refresh-devices"]');
        if (btn) btn.disabled = false;
      });
  },

  renderPeripheriques(main) {
    const pageId = 'peripheriques';
    const t0 = performance.now();
    this._cancelPeripheriquesScans(main);
    main._itControllers = [];
    this._renderPeripheriquesShell(main, false, [], { available: true });
    this._updatePeripheriquesView(main, {
      loading: false,
      list: [],
      hidusbf: { available: true },
      searching: true,
      emptyNotFound: false
    });
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);
    void this._runPeripheriquesScanWave(main, this._PERIPH_STARTUP_DELAYS_MS);
  },

  renderDrivers(main) {
    const pageId = 'drivers';
    const t0 = performance.now();
    const grid = this._mountPage(main, 'Drivers', 'scripts/drivers/');
    grid.classList.add('card-grid--drivers');
    grid.innerHTML = [
      ItUi.actionCard({
        title: 'Désinstaller pilote graphique',
        text: 'Lance l\'outil de désinstallation propre du pilote graphique pour repartir sur une base saine.',
        status: 'PRÊT',
        script: 'drivers/Run-DDU.ps1',
        actions: [{ id: 'ddu', label: 'Lancer', primary: true }]
      }),
      ItUi.actionCard({
        title: 'Installation pilote graphique',
        text: 'Installe ou prépare l\'installation du pilote graphique NVIDIA dans un flux propre.',
        status: 'PRÊT',
        script: 'drivers/Run-NVCleanInstall.ps1',
        actions: [{ id: 'nvc', label: 'Lancer', primary: true }]
      }),
      ItUi.actionCard({
        title: 'Mode graphique performance',
        text: 'Applique les réglages NVIDIA orientés performance pour le gaming compétitif.',
        status: 'PRÊT',
        script: 'drivers/Apply-NvidiaOptimization.ps1',
        actions: [{ id: 'opt', label: 'Appliquer', primary: true }]
      })
    ].join('');
    ItApi.bindPage(grid, {
      ddu: () => ItPages._api().drivers.runDdu(),
      nvc: () => ItPages._api().drivers.runNvclean(),
      opt: () => ItPages._api().drivers.applyOptimization()
    });
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);
  },

  _bindApplicationAction(main, actionId, handler) {
    const btn = main.querySelector(`[data-action="${actionId}"]`);
    if (!btn) return;
    btn.addEventListener('click', async () => {
      if (btn.disabled) return;
      const card = btn.closest('.action-card');
      const statusEl = card?.querySelector('.action-card__status');
      btn.disabled = true;
      if (statusEl) {
        statusEl.textContent = 'En cours…';
        statusEl.className = 'action-card__status status-pending';
      }
      try {
        const r = await handler();
        if (statusEl) {
          if (r?.ok) {
            statusEl.textContent = 'PRÊT';
            statusEl.className = 'action-card__status status-ok';
          } else {
            statusEl.textContent = 'Erreur';
            statusEl.className = 'action-card__status status-err';
          }
        }
        if (r?.message) {
          ItUi.toast(r.message, !r.ok);
        }
      } catch {
        if (statusEl) {
          statusEl.textContent = 'Erreur';
          statusEl.className = 'action-card__status status-err';
        }
        ItUi.toast('Une erreur est survenue.', true);
      } finally {
        btn.disabled = false;
      }
    });
  },

  renderApplications(main) {
    const pageId = 'applications';
    const t0 = performance.now();
    const grid = this._mountPage(main, 'Applications');
    grid.classList.add('card-grid--applications');
    grid.innerHTML = [
      ItUi.actionCard({
        title: 'Discord',
        text: 'Ouvre ou installe Discord, puis applique des réglages légers pour limiter les tâches en arrière-plan.',
        status: 'PRÊT',
        actions: [
          { id: 'open-discord', label: 'Ouvrir / Installer', primary: true },
          { id: 'optimize-discord', label: 'Optimiser' }
        ]
      }),
      ItUi.actionCard({
        title: 'Battle.net',
        text: 'Ouvre ou installe Battle.net, puis limite certains éléments de lancement et d\'arrière-plan.',
        status: 'PRÊT',
        actions: [
          { id: 'open-battlenet', label: 'Ouvrir / Installer', primary: true },
          { id: 'optimize-battlenet', label: 'Optimiser' }
        ]
      }),
      ItUi.actionCard({
        title: 'OBS',
        text: 'Ouvre ou installe OBS, puis prépare une configuration plus légère sans écraser tes scènes.',
        status: 'PRÊT',
        actions: [
          { id: 'open-obs', label: 'Ouvrir / Installer', primary: true },
          { id: 'optimize-obs', label: 'Optimiser' }
        ]
      })
    ].join('');

    const api = ItPages._api().applications;
    this._bindApplicationAction(main, 'open-discord', () => api.open('discord'));
    this._bindApplicationAction(main, 'open-battlenet', () => api.open('battlenet'));
    this._bindApplicationAction(main, 'open-obs', () => api.open('obs'));
    this._bindApplicationAction(main, 'optimize-discord', () => api.optimize('discord'));
    this._bindApplicationAction(main, 'optimize-battlenet', () => api.optimize('battlenet'));
    this._bindApplicationAction(main, 'optimize-obs', () => api.optimize('obs'));

    ItPageLoader.log(pageId, 'shell', performance.now() - t0);
  },

  _applyConnProfileActive(main, profile) {
    const active = profile === 'gaming' || profile === 'download' ? profile : null;
    main.querySelectorAll('[data-profile]').forEach((card) => {
      const isActive = active && card.dataset.profile === active;
      card.classList.toggle('conn-profile-card--active', !!isActive);
      const badge = card.querySelector('.conn-profile-active-badge');
      const activeText = card.querySelector('.conn-profile-active-text');
      const hint = card.querySelector('.conn-profile-hint');
      if (badge) badge.hidden = !isActive;
      if (activeText) activeText.hidden = !isActive;
      if (hint) hint.hidden = !!isActive;
    });
  },

  _applyConnexionStatus(main, data) {
    const d = data || {};
    const pingEl = main.querySelector('#conn-ping');
    if (pingEl) pingEl.textContent = `Ping : ${d.pingMs ?? 'N/D'} ms`;
    this._applyConnProfileActive(main, d.activeProfile);
    const badge = main.querySelector('#connOptimizeStatus');
    if (badge) {
      const optimized = !!d.optimized;
      badge.className = optimized ? 'conn-tcp-badge conn-tcp-badge--ok' : 'conn-tcp-badge';
      badge.textContent = d.optimizedLabel || (optimized ? 'Connexion optimisée' : 'Non optimisé');
    }
    const meta = main.querySelector('#connOptimizeLast');
    if (meta) {
      meta.textContent = d.tcpOptimizerLastApplied
        ? `Dernière optimisation : ${d.tcpOptimizerLastApplied}`
        : 'Dernière optimisation : -';
    }
  },

  _refreshConnexionStatus(main) {
    return ItPages._api().network.status().then((payload) => {
      this._applyConnexionStatus(main, payload?.data || {});
      return payload;
    }).catch(() => null);
  },

  _netTestGradeClass(grade, partial) {
    const g = String(grade || '').replace(/\s+partiel$/i, '').toUpperCase();
    const base = g === 'A+' || g === 'A' ? 'conn-nettest-grade--good'
      : g === 'B' || g === 'C' ? 'conn-nettest-grade--mid'
        : 'conn-nettest-grade--bad';
    return partial ? `${base} conn-nettest-grade--partial` : base;
  },

  _fmtNetTestMs(val, asDelta = false) {
    if (val == null || Number.isNaN(Number(val))) return 'N/D';
    const n = Number(val);
    return asDelta ? `+${Math.round(n * 10) / 10} ms` : `${Math.round(n * 10) / 10} ms`;
  },

  _fmtNetTestMbps(val) {
    if (val == null || Number.isNaN(Number(val)) || Number(val) <= 0) return 'N/D';
    return `${Number(val)} Mbps`;
  },

  _netTestPhaseStep(phase) {
    const map = { preparing: 0, idle: 1, download: 2, upload: 3, complete: 4 };
    return map[phase] ?? 1;
  },

  _netTestPhaseLabel(phase) {
    const map = {
      preparing: 'Préparation…',
      idle: 'Mesure latence au repos…',
      download: 'Download actif…',
      upload: 'Upload actif…',
      complete: 'Terminé'
    };
    return map[phase] || 'Test en cours…';
  },

  _setNetTestProgress(main, step, label) {
    const panel = main.querySelector('#connNetTestPanel');
    const progress = main.querySelector('#connNetTestProgress');
    if (!panel || !progress) return;
    panel.hidden = false;
    const steps = [
      '1. Latence au repos',
      '2. Download actif',
      '3. Upload actif',
      '4. Résultat'
    ];
    progress.innerHTML = `
      <p class="conn-nettest-running">${ItUi.escape(label || 'Test en cours…')}</p>
      <ul class="conn-nettest-steps">
        ${steps.map((s, i) => `<li class="${i + 1 <= step ? 'conn-nettest-steps__item--active' : ''}">${ItUi.escape(s)}</li>`).join('')}
      </ul>`;
    const results = main.querySelector('#connNetTestResults');
    if (results) results.innerHTML = '';
  },

  _renderNetTestInterrupted(main, message) {
    const panel = main.querySelector('#connNetTestPanel');
    const progress = main.querySelector('#connNetTestProgress');
    const results = main.querySelector('#connNetTestResults');
    if (!panel || !results) return;
    panel.hidden = false;
    if (progress) progress.innerHTML = '';
    results.innerHTML = `
      <div class="conn-nettest-result-head">
        <div class="conn-nettest-grade conn-nettest-grade--bad conn-nettest-grade--partial">—</div>
        <div class="conn-nettest-status">Test interrompu</div>
      </div>
      <p class="conn-nettest-partial">${ItUi.escape(message || 'Test interrompu — relance le test.')}</p>`;
  },

  _renderNetTestResults(main, data) {
    const panel = main.querySelector('#connNetTestPanel');
    const progress = main.querySelector('#connNetTestProgress');
    const results = main.querySelector('#connNetTestResults');
    if (!panel || !results) return;
    panel.hidden = false;
    if (progress) progress.innerHTML = '';
    const d = data || {};
    const partial = !!d.partial;
    const grade = d.gradeDisplay || d.grade || '—';
    const gradeClass = this._netTestGradeClass(d.grade || grade, partial);
    const unloaded = d.unloadedMs ?? d.baselineLatencyMs;
    const dlMbps = this._fmtNetTestMbps(d.downloadMbps);
    const upMbps = this._fmtNetTestMbps(d.uploadMbps);
    results.innerHTML = `
      <div class="conn-nettest-result-head">
        <div class="conn-nettest-grade ${gradeClass}">${ItUi.escape(grade)}</div>
        <div class="conn-nettest-status">${ItUi.escape(d.statusLabel || '')}</div>
      </div>
      <div class="conn-nettest-metrics conn-nettest-metrics--primary">
        <div><span>Ping au repos</span><strong>${ItUi.escape(this._fmtNetTestMs(unloaded))}</strong></div>
        <div class="conn-nettest-metric">
          <span>Download</span><strong>${ItUi.escape(dlMbps)}</strong>
          ${d.downloadNote ? `<p class="conn-nettest-metric-note">${ItUi.escape(d.downloadNote)}</p>` : ''}
        </div>
        <div class="conn-nettest-metric">
          <span>Upload</span><strong>${ItUi.escape(upMbps)}</strong>
          ${d.uploadNote ? `<p class="conn-nettest-metric-note">${ItUi.escape(d.uploadNote)}</p>` : ''}
        </div>
      </div>
      <div class="conn-nettest-metrics conn-nettest-metrics--secondary">
        <div><span>Loaded Download</span><strong>${ItUi.escape(d.downloadDeltaMs != null ? this._fmtNetTestMs(d.downloadDeltaMs, true) : 'N/D')}</strong></div>
        <div><span>Loaded Upload</span><strong>${ItUi.escape(d.uploadDeltaMs != null ? this._fmtNetTestMs(d.uploadDeltaMs, true) : 'N/D')}</strong></div>
      </div>
      ${d.partialMessage ? `<p class="conn-nettest-partial">${ItUi.escape(d.partialMessage)}</p>` : ''}`;
  },

  _bindConnexion(main) {
    const root = main.querySelector('.connexion-page');
    if (!root) return;
    const refresh = () => this._refreshConnexionStatus(main);
    const confirmRestore = () => window.confirm(
      'Kojo va restaurer les réglages réseau (Winsock, pile TCP/IP, netsh, registre TCP / multimédia). Un redémarrage peut être nécessaire. Continuer ?'
    );
    const confirmTcpGaming = () => window.confirm(
      'Kojo va appliquer le profil gaming (registre Windows + netsh, comme TCP Optimizer en mode Custom). Continuer ?'
    );
    ItUi.bindActions(root, {
      game: async (btn) => {
        const r = await ItApi.run(() => ItPages._api().network.gaming(), btn);
        if (r?.ok) {
          this._applyConnProfileActive(main, r.data?.activeProfile || 'gaming');
          refresh();
        }
      },
      dl: async (btn) => {
        const r = await ItApi.run(() => ItPages._api().network.download(), btn);
        if (r?.ok) {
          this._applyConnProfileActive(main, r.data?.activeProfile || 'download');
          refresh();
        }
      },
      tcp: (btn) => ItApi.run(() => ItPages._api().network.tcp(), btn),
      rst: async (btn) => {
        if (!confirmRestore()) {
          ItUi.toast('Annulé', false);
          return;
        }
        const r = await ItApi.run(() => ItPages._api().network.restore(), btn);
        if (r?.ok) refresh();
      },
      'tcp-gaming': async (btn) => {
        if (!confirmTcpGaming()) {
          ItUi.toast('Annulé', false);
          return;
        }
        const r = await ItApi.run(() => ItPages._api().network.applyTcpGaming(), btn);
        if (r?.ok) refresh();
      },
      'net-test': async (btn) => {
        if (btn.disabled) return;
        btn.disabled = true;
        let unsubProgress = null;
        const UI_MAX_MS = 95000;
        this._setNetTestProgress(main, 1, 'Préparation…');
        if (ItPages._api().network.onNetworkTestProgress) {
          unsubProgress = ItPages._api().network.onNetworkTestProgress((p) => {
            if (!p || p.phase === 'error') return;
            const step = this._netTestPhaseStep(p.phase);
            const label = this._netTestPhaseLabel(p.phase);
            const speedHint = p.currentSpeed != null ? ` — ${p.currentSpeed} Mbps` : '';
            const latHint = p.currentLatency != null ? ` — ${p.currentLatency} ms` : '';
            this._setNetTestProgress(main, step, `${label}${speedHint || latHint}`);
          });
        }
        const runTest = ItPages._api().network.runNetworkTest();
        const uiTimeout = new Promise((resolve) => {
          setTimeout(() => resolve({
            ok: false,
            status: 'timeout',
            message: 'Test interrompu — relance le test.',
            data: {
              partial: true,
              aborted: true,
              partialMessage: 'Test interrompu — relance le test.',
              statusLabel: 'Test interrompu'
            }
          }), UI_MAX_MS);
        });
        try {
          const r = await Promise.race([runTest, uiTimeout]);
          if (r?.ok && r.data && !r.data.aborted) {
            ItPageCache.set('connexion-nettest', r);
            this._renderNetTestResults(main, r.data);
            ItUi.toast(r.message || 'Test réseau terminé', false);
          } else if (r?.data && (r.data.aborted || r.data.partial || r.data.baselineLatencyMs != null)) {
            if (r.data.aborted || r.status === 'timeout') {
              this._renderNetTestInterrupted(main, r.message || r.data.partialMessage);
            } else {
              ItPageCache.set('connexion-nettest', r);
              this._renderNetTestResults(main, r.data);
            }
            ItUi.toast(r.message || r.data.partialMessage || 'Test réseau partiel', r?.ok === false);
          } else {
            const msg = r?.message || 'Test interrompu — relance le test.';
            this._renderNetTestInterrupted(main, msg);
            ItUi.toast(msg, true);
          }
        } catch (e) {
          const msg = String(e.message || e) || 'Test interrompu — relance le test.';
          this._renderNetTestInterrupted(main, msg);
          ItUi.toast(msg, true);
        } finally {
          if (unsubProgress) unsubProgress();
          btn.disabled = false;
        }
      }
    });
  },

  renderConnexion(main) {
    const pageId = 'connexion';
    const t0 = performance.now();
    const cached = ItPageCache.get(pageId);
    const d = cached?.payload?.data || {};
    const optimized = !!d.optimized;
    const badgeClass = optimized ? 'conn-tcp-badge conn-tcp-badge--ok' : 'conn-tcp-badge';
    const badgeText = d.optimizedLabel || (optimized ? 'Connexion optimisée' : 'Non optimisé');
    const lastOpt = d.tcpOptimizerLastApplied
      ? `Dernière optimisation : ${d.tcpOptimizerLastApplied}`
      : 'Dernière optimisation : -';
    const pingLine = cached ? `Ping : ${d.pingMs ?? 'N/D'} ms` : 'Analyse de la latence réseau…';
    const netTestCached = ItPageCache.get('connexion-nettest')?.payload?.data;
    const activeProfile = d.activeProfile || null;
    const gamingActive = activeProfile === 'gaming';
    const downloadActive = activeProfile === 'download';

    main.innerHTML = `
      ${this._header('Connexion', 'Optimisez votre connexion pour le jeu : profil gaming, restauration et TCP Optimizer.')}
      <div class="connexion-page">
        <p class="connexion-page__ping" id="conn-ping">${ItUi.escape(pingLine)}</p>
        <section class="conn-panel">
          <div class="conn-panel__inner">
            <div class="conn-kicker">Profils réseau rapides</div>
            <p class="conn-lead">Cliquez sur une carte pour appliquer le profil immédiatement.</p>
            <div class="conn-profiles">
              <button type="button" class="conn-profile-card conn-profile-card--action${gamingActive ? ' conn-profile-card--active' : ''}" data-action="game" data-profile="gaming">
                <span class="conn-profile-active-badge"${gamingActive ? '' : ' hidden'}>ACTIF</span>
                <strong class="conn-profile-title">Profil Gaming</strong>
                <p class="conn-desc">Applique le profil réseau gaming en un clic.</p>
                <p class="conn-profile-active-text"${gamingActive ? '' : ' hidden'}>Profil réseau gaming appliqué</p>
                <span class="conn-profile-hint"${gamingActive ? ' hidden' : ''}>Appliquer maintenant</span>
              </button>
              <button type="button" class="conn-profile-card conn-profile-card--action${downloadActive ? ' conn-profile-card--active' : ''}" data-action="dl" data-profile="download">
                <span class="conn-profile-active-badge"${downloadActive ? '' : ' hidden'}>ACTIF</span>
                <strong class="conn-profile-title">Profil Download</strong>
                <p class="conn-desc">Applique le profil réseau download en un clic.</p>
                <p class="conn-profile-active-text"${downloadActive ? '' : ' hidden'}>Profil réseau download appliqué</p>
                <span class="conn-profile-hint"${downloadActive ? ' hidden' : ''}>Appliquer maintenant</span>
              </button>
              <button type="button" class="conn-profile-card conn-profile-card--action conn-profile-card--test" data-action="net-test">
                <strong class="conn-profile-title">Network Test</strong>
                <p class="conn-desc">Test latence, débit et bufferbloat.</p>
                <span class="conn-profile-hint">Lancer le test</span>
              </button>
            </div>
            <section class="conn-panel conn-panel--nettest" id="connNetTestPanel" hidden>
              <div class="conn-panel__inner">
                <div class="conn-kicker">Bufferbloat Test</div>
                <div id="connNetTestProgress"></div>
                <div id="connNetTestResults"></div>
              </div>
            </section>
          </div>
        </section>
        <section class="conn-panel conn-panel--tcp">
          <div class="conn-panel__inner">
            <div class="conn-kicker">TCP / Réseau</div>
            <div class="conn-tcp-title">TCP Optimizer 4</div>
            <div class="conn-tcp-sub">Optimisation du réseau</div>
            <div class="${badgeClass}" id="connOptimizeStatus">${ItUi.escape(badgeText)}</div>
            <p class="conn-desc" id="connOptimizeLast">${ItUi.escape(lastOpt)}</p>
            <div class="conn-toolbar">
              <button type="button" class="btn" data-action="tcp">Lancer TCP Optimizer</button>
              <button type="button" class="btn" data-action="rst">Restaurer réglage réseau</button>
              <button type="button" class="btn btn--primary" data-action="tcp-gaming">Appliquer profil gaming TCP</button>
            </div>
          </div>
        </section>
      </div>`;
    this._bindConnexion(main);
    if (netTestCached) {
      const panel = main.querySelector('#connNetTestPanel');
      if (panel) panel.hidden = false;
      this._renderNetTestResults(main, netTestCached);
    }
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);

    this._fetchInBackground(
      pageId,
      main,
      () => ItPages._api().network.status(),
      (payload) => this._applyConnexionStatus(main, payload?.data || {}),
      () => {}
    );
  },

  _bindJeu(main, gameLabels) {
    const grid = main.querySelector('#pg');
    const handlers = {
      'wz-detect': () => ItPages._api().games.warzoneDetect(),
      'wz-apply': () => ItPages._api().games.warzoneApply(),
      'wz-restore': () => ItPages._api().games.warzoneRestore()
    };
    Object.keys(gameLabels).forEach((id) => { handlers[`g-${id}`] = () => ItPages._api().games.apply(id); });
    ItApi.bindPage(grid, handlers);
  },

  renderJeu(main) {
    const pageId = 'jeu';
    const t0 = performance.now();
    const cached = ItPageCache.get(pageId);
    const wd = cached?.payload?.data || {};
    const gameLabels = {
      blackops7: 'Black Ops 7', fortnite: 'Fortnite', valorant: 'Valorant', cs2: 'CS2', arcraiders: 'Arc Raiders',
      apex: 'Apex Legends', tarkov: 'Tarkov', rust: 'Rust', r6: 'Rainbow Six', battlefield6: 'Battlefield 6',
      marvelrivals: 'Marvel Rivals', lol: 'League of Legends', dota2: 'Dota 2', fivem: 'FiveM', eafc26: 'EA FC 26',
      overwatch2: 'Overwatch 2', marathon: 'Marathon', rocketleague: 'Rocket League'
    };
    const grid = this._mountPage(main, 'Jeu', 'scripts/games/');
    let html = ItUi.actionCard({
      title: 'Warzone / COD',
      text: cached ? (wd.playersDir || 'Non détecté') : 'Détection du dossier Warzone…',
      status: cached ? (wd.installed ? 'Détecté' : 'Absent') : 'Chargement…',
      statusType: cached ? (wd.installed ? 'ok' : 'warn') : 'pending',
      cardId: 'warzone-status',
      script: 'games/Apply-WarzoneProfile.ps1',
      actions: [
        { id: 'wz-detect', label: 'Détecter' },
        { id: 'wz-apply', label: 'Appliquer', primary: true },
        { id: 'wz-restore', label: 'Restaurer (stub)' }
      ]
    });
    Object.entries(gameLabels).forEach(([id, label]) => {
      html += ItUi.actionCard({
        title: label,
        text: `Profil ${label}`,
        script: `games/Apply-${label.replace(/\s/g, '')}Settings.ps1`,
        actions: [{ id: `g-${id}`, label: 'Appliquer profil (stub)' }]
      });
    });
    grid.innerHTML = html;
    this._bindJeu(main, gameLabels);
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);

    this._fetchInBackground(
      pageId,
      main,
      () => ItPages._api().games.warzoneDetect(),
      (payload) => {
        const w = payload?.data || {};
        ItPageLoader.setCardText(main, 'warzone-status', w.playersDir || 'Non détecté');
        ItPageLoader.setCardStatus(main, 'warzone-status', w.installed ? 'Détecté' : 'Absent', w.installed ? 'ok' : 'warn');
      },
      () => {
        ItPageLoader.setCardStatus(main, 'warzone-status', 'Vérification en arrière-plan', 'warn');
        ItPageLoader.setCardText(main, 'warzone-status', 'Données indisponibles pour le moment.');
      }
    );
  },

  _optimModuleDefs() {
    return [
      {
        id: 'debloat',
        title: 'Debloat',
        section: 'modules',
        description: 'Allège Windows en désactivant les éléments inutiles pour le gaming haute performance.'
      },
      {
        id: 'gameMode',
        title: 'Mode Jeu',
        section: 'modules',
        description: 'Active les réglages système orientés jeu, y compris les optimisations graphiques et de latence.'
      },
      {
        id: 'power',
        title: 'Gestion de l\'alimentation',
        section: 'modules',
        description: 'Applique un plan d\'alimentation orienté performance maximale pour limiter les baisses de fréquence.'
      },
      {
        id: 'regXboxMonitoring',
        title: 'Xbox Game Monitoring',
        section: 'registry',
        description: 'Désactive Xbox Game Monitoring, un service Xbox/GameDVR inutile pour la plupart des configs gaming compétitives.'
      },
      {
        id: 'regGameBarDvr',
        title: 'Game Bar / GameDVR',
        section: 'registry',
        description: 'Limite les overlays, raccourcis Xbox et interruptions en jeu.'
      },
      {
        id: 'regGamesMmcss',
        title: 'Priorité Jeux MMCSS',
        section: 'registry',
        description: 'Favorise les tâches de jeu dans le planificateur multimédia Windows.'
      },
      {
        id: 'regMouseRaw',
        title: 'Souris précision brute',
        section: 'registry',
        description: 'Désactive l\'accélération souris Windows pour une visée plus constante.'
      },
      {
        id: 'regMultimediaProfile',
        title: 'Profil Multimédia Gaming',
        section: 'registry',
        description: 'Réduit la réserve système et priorise audio, affichage et jeu.'
      },
      {
        id: 'regTcpipLowLatency',
        title: 'TCP/IP faible latence',
        section: 'registry',
        description: 'Applique des tweaks réseau génériques sans importer de valeurs propres au PC.'
      },
      {
        id: 'regVisualEffects',
        title: 'Effets visuels performance',
        section: 'registry',
        description: 'Réduit les animations Windows pour garder une interface plus légère.'
      }
    ];
  },

  _optimDefaultState() {
    const state = {};
    for (const mod of this._optimModuleDefs()) state[mod.id] = false;
    return state;
  },

  _optimModuleCard(id, title, description) {
    const descHtml = description
      ? `<p class="optim-card__desc">${ItUi.escape(description)}</p>`
      : '';
    return `
      <article class="optim-card" data-optim-module="${ItUi.escape(id)}" id="optim-card-${ItUi.escape(id)}">
        <div class="optim-card__head">
          <div class="optim-card__title">${ItUi.escape(title)}</div>
          <button type="button" class="optim-toggle" id="optim-toggle-${ItUi.escape(id)}" aria-label="${ItUi.escape(title)}">
            <span class="optim-toggle__thumb"></span>
          </button>
        </div>
        ${descHtml}
      </article>`;
  },

  _setOptimToggle(main, id, on) {
    const card = main.querySelector(`#optim-card-${id}`);
    const toggle = main.querySelector(`#optim-toggle-${id}`);
    if (card) card.classList.toggle('optim-card--on', !!on);
    if (toggle) toggle.classList.toggle('optim-toggle--on', !!on);
  },

  _bindOptimisationModules(main) {
    const STORAGE_KEY = 'kojo-optim-saved';
    const loadSaved = () => {
      try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (raw) return JSON.parse(raw);
      } catch {
        /* ignore */
      }
      return this._optimDefaultState();
    };

    const ui = this._optimDefaultState();
    const saved = loadSaved();
    Object.assign(ui, saved);
    for (const id of Object.keys(ui)) this._setOptimToggle(main, id, ui[id]);

    const statusEl = main.querySelector('#optimModulesStatus');
    const setStatus = (text, kind) => {
      if (!statusEl) return;
      statusEl.textContent = text || '';
      statusEl.className = kind
        ? `optim-panel__status optim-panel__status--${kind}`
        : 'optim-panel__status';
    };

    for (const id of Object.keys(ui)) {
      const btn = main.querySelector(`#optim-toggle-${id}`);
      if (!btn) continue;
      btn.addEventListener('click', () => {
        ui[id] = !ui[id];
        this._setOptimToggle(main, id, ui[id]);
      });
    }

    const applyBtn = main.querySelector('#optimApplyBtn');
    if (!applyBtn) return;

    applyBtn.addEventListener('click', async () => {
      if (applyBtn.disabled) return;
      applyBtn.disabled = true;
      setStatus('Application en cours…', 'pending');
      try {
        const r = await ItPages._api().optimModules.apply({ ui, saved });
        if (r?.status === 'cancelled') {
          setStatus('', 'muted');
          ItUi.toast('Annulé', false);
          return;
        }
        if (r?.data?.saved) {
          Object.assign(saved, r.data.saved);
          Object.assign(ui, r.data.saved);
          localStorage.setItem(STORAGE_KEY, JSON.stringify(saved));
          for (const id of Object.keys(ui)) this._setOptimToggle(main, id, ui[id]);
        }
        if (r?.ok) {
          setStatus(r.message || 'Terminé', r.status === 'noop' ? 'muted' : 'ok');
          ItUi.toast(r.message || 'Terminé', false);
        } else {
          setStatus(r?.message || 'Erreur', 'err');
          ItUi.toast(r?.message || 'Erreur lors de l\'application.', true);
        }
      } catch {
        setStatus('Erreur', 'err');
        ItUi.toast('Erreur lors de l\'application.', true);
      } finally {
        applyBtn.disabled = false;
      }
    });
  },

  renderOptimisation(main) {
    const pageId = 'optimisation';
    const t0 = performance.now();
    const moduleCards = this._optimModuleDefs()
      .filter((mod) => mod.section === 'modules')
      .map((mod) => this._optimModuleCard(mod.id, mod.title, mod.description))
      .join('');
    const registryCards = this._optimModuleDefs()
      .filter((mod) => mod.section === 'registry')
      .map((mod) => this._optimModuleCard(mod.id, mod.title, mod.description))
      .join('');
    main.innerHTML = `
      ${this._header('Optimisation', 'Sélectionnez les modules souhaités, puis cliquez sur Appliquer.')}
      <section class="optim-page">
        <div class="optim-panel">
          <div class="optim-panel__kicker">MODULES</div>
          <p class="optim-panel__status" id="optimModulesStatus" aria-live="polite"></p>
          <div class="optim-grid" id="optimModulesGrid">
            ${moduleCards}
          </div>
        </div>
        <div class="optim-panel optim-panel--registry">
          <div class="optim-panel__kicker">RÉGLAGES REGISTRE GAMING</div>
          <div class="optim-grid" id="optimRegistryGrid">
            ${registryCards}
          </div>
          <p class="optim-panel__hint">Conseillé : crée un point de restauration depuis l'accueil avant d'appliquer des optimisations système.</p>
          <div class="optim-actions">
            <button type="button" class="btn btn--primary optim-apply-btn" id="optimApplyBtn">APPLIQUER</button>
          </div>
        </div>
      </section>`;
    this._bindOptimisationModules(main);
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);
  },

  renderSon(main) {
    const pageId = 'son';
    const t0 = performance.now();
    const grid = this._mountPage(main, 'Son', 'scripts/audio/');
    grid.innerHTML = [
      ItUi.actionCard({
        title: 'État audio',
        text: 'Cliquez sur Lire pour analyser (non bloquant).',
        status: 'Prêt',
        cardId: 'audio-status',
        script: 'audio/Get-AudioStatus.ps1',
        actions: [{ id: 'st', label: 'Lire', primary: true }]
      }),
      ItUi.actionCard({ title: 'Profil audio', script: 'audio/Apply-AudioProfile.ps1', actions: [{ id: 'ap', label: 'Appliquer (stub)' }] }),
      ItUi.actionCard({ title: 'Restaurer', script: 'audio/Restore-AudioDefaults.ps1', actions: [{ id: 'rs', label: 'Restaurer (stub)' }] }),
      ItUi.actionCard({ title: 'Paramètres Windows', actions: [{ id: 'open', label: 'Ouvrir Son', primary: true }] })
    ].join('');
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);
    ItApi.bindPage(grid, {
      st: (btn) => ItApi.run(async () => {
        ItPageLoader.setCardStatus(main, 'audio-status', 'Analyse en cours…', 'pending');
        return ItPageLoader.run(ItPages._api().audio.status(), ItPageLoader.READ_MS);
      }, btn),
      ap: () => ItPages._api().audio.apply(),
      rs: () => ItPages._api().audio.restore(),
      open: () => ItPages._api().audio.openSettings()
    });
  },

  renderCompte(main) {
    main.innerHTML = `${this._header('Compte / Abonnement', 'Licence locale Kojo')}<div class="card-grid">${ItUi.actionCard({ title: 'Kojo', text: 'Abonnement à brancher.', status: 'Local', actions: [{ id: 'x', label: '—', disabled: true }] })}</div>`;
  },

  _updateStatusLabel(status) {
    const map = {
      idle: 'Prêt',
      checking: 'Vérification…',
      available: 'Update disponible',
      not_available: 'À jour',
      downloading: 'Téléchargement',
      downloaded: 'Prêt à installer',
      local_build: 'Build local',
      error: 'Erreur'
    };
    return map[status] || status || 'Prêt';
  },

  _updateStatusType(status) {
    if (status === 'available' || status === 'downloaded') return 'ok';
    if (status === 'error') return 'err';
    if (status === 'checking' || status === 'downloading') return 'pending';
    return 'neutral';
  },

  _formatLastCheck(iso) {
    if (!iso) return 'Jamais';
    try {
      const d = new Date(iso);
      return d.toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' });
    } catch {
      return iso;
    }
  },

  async runGlobalUpdateCheck(triggerBtn) {
    const btn = triggerBtn || document.getElementById('sidebar-check-update');
    const label = btn?.textContent;
    if (btn) {
      btn.disabled = true;
      btn.textContent = 'Vérification…';
    }
    try {
      const result = await ItApi.updates.check();
      const msg = result?.message || this._updateStatusLabel(result?.status);
      ItUi.toast(msg, result?.status === 'error');
      if (mainContent.querySelector('[data-slot="settings-update"]')) {
        mainContent._itUpdate = mainContent._itUpdate || {};
        mainContent._itUpdate.lastCheckAt = new Date().toISOString();
        this._applyUpdatePayload(mainContent, result);
      }
      return result;
    } catch (e) {
      ItUi.toast(String(e.message || e), true);
      return { ok: false, status: 'error', message: String(e.message || e) };
    } finally {
      if (btn) {
        btn.disabled = false;
        if (label) btn.textContent = label;
      }
    }
  },

  _syncSettingsUpdateUi(main) {
    const u = main._itUpdate || { status: 'idle', message: 'Prêt', percent: 0, version: '—', remoteVersion: '', lastCheckAt: null };
    const statusEl = main.querySelector('[data-upd-status-text]');
    const versionEl = main.querySelector('[data-upd-version]');
    const remoteEl = main.querySelector('[data-upd-remote]');
    const progressWrap = main.querySelector('[data-upd-progress]');
    const progressBar = main.querySelector('[data-upd-progress-bar]');
    const badge = main.querySelector('[data-card-id="settings-update"] .action-card__status');

    if (versionEl) versionEl.textContent = u.version || '—';
    const lastCheckEl = main.querySelector('[data-upd-last-check]');
    if (lastCheckEl) lastCheckEl.textContent = this._formatLastCheck(u.lastCheckAt);
    const devBanner = main.querySelector('[data-upd-dev-banner]');
    if (devBanner) {
      if (u.devMode) {
        devBanner.hidden = false;
        devBanner.textContent = 'Mode dev — update réel indisponible';
      } else if (u.localBuild) {
        devBanner.hidden = false;
        devBanner.textContent =
          'Mode test local — installe la version Setup pour tester les mises à jour réelles';
      } else {
        devBanner.hidden = true;
      }
    }
    if (remoteEl) {
      const gh = u.githubRelease || u.remoteVersion;
      remoteEl.textContent = gh ? `Dernière release GitHub : ${gh}` : '';
      remoteEl.hidden = !gh;
    }
    if (statusEl) statusEl.textContent = u.message || this._updateStatusLabel(u.status);
    if (badge) {
      badge.textContent = this._updateStatusLabel(u.status);
      badge.className = `action-card__status ${this._updateStatusType(u.status) === 'ok' ? 'status-ok' : this._updateStatusType(u.status) === 'err' ? 'status-err' : this._updateStatusType(u.status) === 'pending' ? 'status-pending' : ''}`;
    }
    if (progressWrap && progressBar) {
      const show = u.status === 'downloading';
      progressWrap.hidden = !show;
      progressBar.style.width = `${Math.min(100, Math.max(0, u.percent || 0))}%`;
    }

    const btnCheck = main.querySelector('[data-action="upd-check"]');
    const btnDl = main.querySelector('[data-action="upd-dl"]');
    const btnInstall = main.querySelector('[data-action="upd-install"]');
    const busy = u.status === 'checking' || u.status === 'downloading';

    const noRealUpdate = u.devMode || u.localBuild;
    if (btnCheck) btnCheck.disabled = busy;
    if (btnDl) btnDl.disabled = busy || noRealUpdate || u.status !== 'available';
    if (btnInstall) btnInstall.disabled = busy || noRealUpdate || u.status !== 'downloaded';
  },

  _applyUpdatePayload(main, payload) {
    const p = payload || {};
    const data = p.data || {};
    main._itUpdate = {
      status: p.status || 'idle',
      message: p.message || '',
      percent: data.percent ?? (p.status === 'downloaded' ? 100 : 0),
      version: data.currentVersion || main._itUpdate?.version || '—',
      remoteVersion: data.version || data.remoteVersion || '',
      githubRelease: data.githubRelease || data.remoteVersion || '',
      lastCheckAt: main._itUpdate?.lastCheckAt || null,
      devMode: data.devMode ?? main._itUpdate?.devMode ?? false,
      localBuild: data.localBuild ?? main._itUpdate?.localBuild ?? p.status === 'local_build',
      updateMode: data.updateMode || main._itUpdate?.updateMode
    };
    this._syncSettingsUpdateUi(main);
  },

  _ensureReglagesUpdateListener(main) {
    if (main._itUpdateUnsub) return;
    main._itUpdateUnsub = ItPages._api().updates.onStatus((payload) => {
      if (!main.querySelector('[data-card-id="settings-update"]')) return;
      this._applyUpdatePayload(main, payload);
    });
  },

  _runUpdateAction(main, btn, fn) {
    return (async () => {
      if (btn) btn.disabled = true;
      try {
        const result = await fn();
        this._applyUpdatePayload(main, result);
        if (result?.message && result.status !== 'checking') {
          ItUi.toast(result.message, result.status === 'error');
        }
      } catch (e) {
        this._applyUpdatePayload(main, { ok: false, status: 'error', message: String(e.message || e) });
        ItUi.toast(String(e.message || e), true);
      } finally {
        this._syncSettingsUpdateUi(main);
      }
    })();
  },

  async _loadReglagesUpdateMeta(main) {
    const build = window.__itBuildInfo || (await ItApi.app.getBuildInfo().catch(() => ({})));
    try {
      const verRes = await ItApi.updates.getVersion();
      const statusRes = await ItApi.updates.getStatus();
      const updateMode = verRes?.data?.updateMode || statusRes?.data?.updateMode || (build.devMode ? 'dev' : 'installed');
      main._itUpdate = {
        status: statusRes?.status || 'idle',
        message: statusRes?.message || 'Prêt',
        percent: statusRes?.data?.percent || 0,
        version: verRes?.data?.version || build.version || statusRes?.data?.currentVersion || '—',
        remoteVersion: statusRes?.data?.githubRelease || statusRes?.data?.version || '',
        githubRelease: statusRes?.data?.githubRelease || '',
        lastCheckAt: main._itUpdate?.lastCheckAt || null,
        devMode: updateMode === 'dev',
        localBuild: updateMode === 'local_build',
        updateMode
      };
    } catch {
      main._itUpdate = {
        status: 'idle',
        message: 'Prêt',
        percent: 0,
        version: build.version || '—',
        remoteVersion: '',
        githubRelease: '',
        lastCheckAt: null,
        devMode: !!build.devMode,
        localBuild: false,
        updateMode: build.devMode ? 'dev' : 'installed'
      };
    }
    this._syncSettingsUpdateUi(main);
  },

  _htmlReglagesUpdateCard(u) {
    const state = u || { status: 'idle', message: 'Prêt', version: '—', devMode: true };
    return `
      <article class="action-card action-card--updates" data-card-id="settings-update">
        <div class="action-card__head">
          <h3 class="action-card__title">Mises à jour</h3>
          <span class="action-card__status">${ItUi.escape(this._updateStatusLabel(state.status))}</span>
        </div>
        <p class="action-card__text">Vérifie et installe la dernière version de Kojo depuis GitHub.</p>
        <p class="settings-update__dev-banner" data-upd-dev-banner${state.devMode ? '' : ' hidden'}>Mode dev — update réel indisponible (build packagé requis).</p>
        <div class="settings-update__meta">
          <p>Version actuelle : <strong data-upd-version>${ItUi.escape(state.version)}</strong></p>
          <p>Dernière vérification : <span data-upd-last-check>${ItUi.escape(this._formatLastCheck(state.lastCheckAt))}</span></p>
          <p class="settings-update__remote" data-upd-remote hidden></p>
          <p class="settings-update__status-line" data-upd-status-text>${ItUi.escape(state.message || 'Prêt')}</p>
          <div class="settings-update__progress" data-upd-progress hidden>
            <div class="settings-update__progress-bar" data-upd-progress-bar></div>
          </div>
        </div>
        <div class="action-card__actions settings-update__actions">
          <button type="button" class="btn btn--primary" data-action="upd-check">Check update</button>
          <button type="button" class="btn btn--ghost" data-action="upd-dl">Télécharger</button>
          <button type="button" class="btn btn--ghost" data-action="upd-install">Installer et redémarrer</button>
        </div>
        <p class="ctrl-device__feedback" data-ctrl-feedback hidden></p>
      </article>`;
  },

  _renderReglagesUpdateSlot(main) {
    const slot = main.querySelector('[data-slot="settings-update"]');
    if (!slot) return;
    const u = main._itUpdate || { status: 'idle', message: 'Prêt', version: '—', devMode: true };
    slot.innerHTML = this._htmlReglagesUpdateCard(u);
    this._syncSettingsUpdateUi(main);
  },

  _applyReglagesOther(main, s) {
    const slot = main.querySelector('[data-slot="settings-other"]');
    if (!slot) return;
    slot.innerHTML = [
      ItUi.actionCard({
        title: 'Confirmations',
        text: 'Avant actions système dangereuses',
        status: s.confirmDangerousActions ? 'ON' : 'OFF',
        statusType: 'ok',
        cardId: 'settings-confirm',
        actions: [{ id: 'tog', label: 'Inverser', primary: true }]
      }),
      ItUi.actionCard({ title: 'Reset', actions: [{ id: 'rst', label: 'Réinitialiser', primary: true }] })
    ].join('');
  },

  _applyReglages(main, s) {
    const grid = main.querySelector('#pg');
    if (!grid) return;
    if (!main._itUpdate) {
      main._itUpdate = { status: 'idle', message: 'Prêt', percent: 0, version: '—', remoteVersion: '', devMode: true };
    }
    grid.innerHTML = `
      <div data-slot="settings-update"></div>
      <div data-slot="settings-other"></div>`;
    this._renderReglagesUpdateSlot(main);
    this._applyReglagesOther(main, s);
    this._ensureReglagesUpdateListener(main);

    main._itReglagesHandlers = {
      'upd-check': (btn) => this._runUpdateAction(main, btn, async () => {
        main._itUpdate.lastCheckAt = new Date().toISOString();
        return ItApi.updates.check();
      }),
      'upd-dl': (btn) => this._runUpdateAction(main, btn, () => ItApi.updates.download()),
      'upd-install': (btn) => this._runUpdateAction(main, btn, () => ItApi.updates.install()),
      tog: async () => {
        await ItPages._api().settings.save({ confirmDangerousActions: !s.confirmDangerousActions });
        this.renderReglages(main);
      },
      rst: async () => {
        await ItPages._api().settings.reset();
        this.renderReglages(main);
      }
    };
  },

  _ensureReglagesClickDelegate(main) {
    if (main._itReglagesDelegate) return;
    main._itReglagesDelegate = true;
    main.addEventListener('click', (ev) => {
      const btn = ev.target.closest('#pg [data-action]');
      if (!btn || !main.contains(btn)) return;
      const fn = main._itReglagesHandlers?.[btn.dataset.action];
      if (fn) fn(btn);
    });
  },

  renderReglages(main) {
    const pageId = 'reglages';
    const t0 = performance.now();
    this._mountPage(main, 'Réglages');
    this._ensureReglagesClickDelegate(main);
    const cached = ItPageCache.get(pageId);
    const s = cached?.payload || { confirmDangerousActions: true };
    main._itUpdate = main._itUpdate || { status: 'idle', message: 'Prêt', percent: 0, version: '—', remoteVersion: '' };
    this._applyReglages(main, s);
    this._loadReglagesUpdateMeta(main);
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);

    this._fetchInBackground(
      pageId,
      main,
      () => ItPages._api().settings.get(),
      (payload) => this._applyReglagesOther(main, payload),
      () => {
        ItPageLoader.setCardStatus(main, 'settings-confirm', 'Données indisponibles', 'warn');
      }
    );
  }
};
