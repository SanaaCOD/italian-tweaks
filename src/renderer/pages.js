/* Pages ITALIAN TWEAKS — chaque bouton → IPC → script .ps1 */
window.ItPages = {
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
    const typeRaw = c.type || c.Type || 'Generic';
    const type = typeRaw === 'DualSense' ? 'PS5' : typeRaw;
    const maxHz = Number(c.maxPollingRate ?? c.MaxRateHz ?? (type === 'PS5' ? 8000 : 1000));
    const curHz = Number(c.currentPollingRate ?? c.currentHz ?? 0);
    return {
      id: c.id || c.CardId || c.instanceId || c.InstanceId || c.deviceInstanceId || '',
      name: c.name || c.DisplayName || 'Manette',
      type,
      vendorId: c.vendorId || c.Vid || '',
      productId: c.productId || c.Pid || '',
      instanceId: c.instanceId || c.InstanceId || c.deviceInstanceId || '',
      parentInstanceId: c.parentInstanceId || c.UsbParentDeviceId || '',
      devicePath: c.devicePath || c.instanceId || '',
      present: c.present !== false,
      currentPollingRate: curHz,
      targetPollingRate: Number(c.targetPollingRate ?? (type === 'PS5' ? 8000 : 1000)),
      maxPollingRate: maxHz,
      canBoost: c.canBoost === true,
      boostButton: c.boostButton || (c.type === 'PS5' && c.canBoost ? '8000' : c.canBoost ? '1000' : 'none'),
      hidusbfTargetReliable: c.hidusbfTargetReliable !== false,
      compatible: c.compatible === true || (c.hidusbfTargetReliable !== false && c.present !== false),
      recommendedAction: c.recommendedAction || '',
      pollingLabel: c.pollingLabel || (curHz ? `${curHz} Hz` : 'Inconnu'),
      statusBadge: c.statusBadge || '—',
      statusBadgeType: c.statusBadgeType || 'neutral',
      hidusbfTargetId: c.hidusbfTargetId || c.parentInstanceId || ''
    };
  },

  _normalizeControllers(payload) {
    const data = payload?.data ?? payload ?? {};
    let c = data.controllers;
    if (Array.isArray(c)) return c.map((x) => this._mapController(x)).filter(Boolean);
    if (c?.value && Array.isArray(c.value)) return c.value.map((x) => this._mapController(x)).filter(Boolean);
    return [];
  },

  _hidusbfFromPayload(payload) {
    const data = payload?.data ?? payload ?? {};
    const h = data.hidusbf;
    if (h && typeof h === 'object') return h;
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
          <span class="hero__brand">ITALIAN TWEAKS</span>
          <div class="hero__logo-wrap"><img class="hero__logo" src="../../assets/logo.png" alt="" /></div>
          <p class="hero__slogan">AU SERVICE DE VOS PERFORMANCES</p>
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
          ${ItUi.actionCard({ title: 'Restaurer défauts', text: 'Équivalent RESTORE_DEFAULTS.ps1.enc', script: 'system/Restore-Defaults.ps1', actions: [{ id: 'restore-def', label: 'Exécuter', primary: true }] })}
          ${ItUi.actionCard({ title: 'Tout annuler', text: 'Équivalent REVERT_ALL.ps1.enc', script: 'system/Revert-All.ps1', actions: [{ id: 'revert-all', label: 'Exécuter', primary: true }] })}
        </div>
      </div>`;
    const grid = main.querySelector('.page-actions');
    ItApi.bindPage(grid, {
      'restore-def': () => window.italianTweaks.system.restoreDefaults(),
      'revert-all': () => window.italianTweaks.system.revertAll()
    });

    if (!r) {
      this._fetchInBackground(
        pageId,
        main,
        () => window.italianTweaks.system.getStats({ full: true }),
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
      <div class="component-card__head"><div class="component-card__label-row"><span class="component-card__diamond"></span>${label}</div><span class="badge">${badge}</span></div>
      <div class="component-card__value" data-live="${live}">${ItUi.escape(val)}</div>
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

  _htmlPeripheriquesHeaderMeta(loading, list, hidusbf) {
    const boosted = this._countBoostedControllers(list);
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
          <p>HIDUSBF patches the USB composite parent (not MI interfaces). Boost copies the ${max >= 8000 ? '4khz-8khz' : '1khz'} driver variant; Remove Boost restores NoPatch + default 125 Hz polling.</p>
        </details>
      </article>`;
  },

  _htmlPeripheriquesDevices(list, loading, hidusbf) {
    if (loading) {
      return `
        <div class="ctrl-device ctrl-device--scanning">
          <p class="ctrl-device__scan-label">Scanning…</p>
          <p class="ctrl-device__scan-hint">Detecting connected controllers (PnP PresentOnly)</p>
        </div>`;
    }
    if (!list.length) {
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
        return ItApi.run(() => window.italianTweaks.controllers.applyPolling(c, hz), btn)
          .finally(() => {
            btn.disabled = false;
            btn.textContent = label;
          })
          .then(() => this._refreshPeripheriques(main));
      };
      handlers[`remove-${i}`] = (btn) => {
        const label = btn.textContent;
        btn.disabled = true;
        btn.textContent = 'Removing…';
        return ItApi.run(() => window.italianTweaks.controllers.restorePolling(c), btn)
          .finally(() => {
            btn.disabled = false;
            btn.textContent = label;
          })
          .then(() => this._refreshPeripheriques(main));
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

  _updatePeripheriquesView(main, { loading, list, hidusbf }) {
    const meta = main.querySelector('[data-slot="ctrl-header-meta"]');
    const slot = main.querySelector('[data-slot="ctrl-dynamic"]');
    const refreshBtn = main.querySelector('[data-action="refresh-devices"]');
    if (meta) meta.innerHTML = this._htmlPeripheriquesHeaderMeta(loading, list, hidusbf);
    if (slot) slot.innerHTML = this._htmlPeripheriquesDevices(list, loading, hidusbf);
    if (refreshBtn) refreshBtn.disabled = !!loading;
    this._bindPeripheriques(main, loading ? (main._itControllers || []) : list, hidusbf);
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
    const prevList = main._itControllers || [];
    const prevHid = main._itHidusbf || { available: true };
    if (!main.querySelector('.page-peripheriques')) {
      this._renderPeripheriquesShell(main, true, [], prevHid);
    } else {
      this._updatePeripheriquesView(main, { loading: true, list: prevList, hidusbf: prevHid });
    }
    if (refreshBtn) refreshBtn.disabled = true;

    const navGen = main.dataset.navGen;
    const t0 = performance.now();
    ItPageLoader.run(window.italianTweaks.controllers.list(), 5000)
      .then((payload) => {
        if (main.dataset.navGen !== navGen) return;
        ItPageLoader.log(pageId, 'scan done', performance.now() - t0);
        this._applyPeripheriquesData(main, payload);
      })
      .catch(() => {
        if (main.dataset.navGen !== navGen) return;
        ItPageLoader.log(pageId, 'scan timeout/err', performance.now() - t0);
        this._updatePeripheriquesView(main, { loading: false, list: prevList, hidusbf: prevHid });
        const fb = main.querySelector('[data-ctrl-feedback]');
        if (fb) {
          fb.hidden = false;
          fb.textContent = 'Scan interrupted — try Refresh Devices again.';
        }
        ItUi.toast('Device scan failed or timed out', true);
      })
      .finally(() => {
        const btn = main.querySelector('[data-action="refresh-devices"]');
        if (btn) btn.disabled = false;
      });
  },

  renderPeripheriques(main) {
    const pageId = 'peripheriques';
    const t0 = performance.now();
    this._renderPeripheriquesShell(main, true, [], { available: true });
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);
    this._refreshPeripheriques(main);
  },

  _nvidiaCardHtml(d, loading) {
    const text = loading
      ? 'Analyse du pilote NVIDIA…'
      : `Installé: ${d.installedVersion || '—'}\nDernière: ${d.latestVersion || '—'}`;
    const status = loading ? 'Chargement…' : (d.updateAvailable ? 'MAJ dispo' : 'OK');
    const statusType = loading ? 'pending' : (d.updateAvailable ? 'warn' : 'ok');
    return ItUi.actionCard({
      title: 'GPU NVIDIA',
      text,
      status,
      statusType,
      cardId: 'nvidia-status',
      script: 'drivers/Get-NvidiaStatus.ps1',
      actions: [{ id: 'refresh', label: 'Actualiser' }]
    });
  },

  _bindDrivers(main) {
    const grid = main.querySelector('#pg');
    if (!grid) return;
    ItApi.bindPage(grid, {
      refresh: () => this.renderDrivers(main),
      ddu: () => window.italianTweaks.drivers.runDdu(),
      nvc: () => window.italianTweaks.drivers.runNvclean(),
      inst: () => window.italianTweaks.drivers.installLatest(),
      opt: () => window.italianTweaks.drivers.applyOptimization(),
      sq: () => window.italianTweaks.drivers.applySqEngine(),
      guide: () => window.italianTweaks.drivers.nvidiaGuide(),
      oc: () => window.italianTweaks.drivers.gpuOverclock(),
      nip: () => window.italianTweaks.drivers.openNip()
    });
  },

  _applyDriversNvidia(main, payload) {
    const d = payload?.data || {};
    const card = main.querySelector('[data-card-id="nvidia-status"]');
    if (!card) return;
    const text = `Installé: ${d.installedVersion || '—'}\nDernière: ${d.latestVersion || '—'}`;
    card.querySelector('.action-card__text').textContent = text;
    const st = card.querySelector('.action-card__status');
    st.textContent = d.updateAvailable ? 'MAJ dispo' : 'OK';
    st.className = `action-card__status ${d.updateAvailable ? 'status-warn' : 'status-ok'}`;
  },

  renderDrivers(main) {
    const pageId = 'drivers';
    const t0 = performance.now();
    const cached = ItPageCache.get(pageId);
    const d = cached?.payload?.data || {};
    const grid = this._mountPage(main, 'Drivers', 'scripts/drivers/');
    grid.innerHTML = [
      this._nvidiaCardHtml(d, !cached),
      ItUi.actionCard({ title: 'DDU', script: 'drivers/Run-DDU.ps1', actions: [{ id: 'ddu', label: 'Lancer DDU', primary: true }] }),
      ItUi.actionCard({ title: 'NVCleanInstall', script: 'drivers/Run-NVCleanInstall.ps1', actions: [{ id: 'nvc', label: 'Lancer', primary: true }] }),
      ItUi.actionCard({ title: 'Installer dernier pilote', script: 'drivers/Install-LatestNvidiaDriver.ps1', actions: [{ id: 'inst', label: 'Installer (stub)', primary: true }] }),
      ItUi.actionCard({ title: 'Optimisation NVIDIA', script: 'drivers/Apply-NvidiaOptimization.ps1', actions: [{ id: 'opt', label: 'Appliquer (stub)' }] }),
      ItUi.actionCard({ title: 'SQ Engine', script: 'drivers/Apply-SQEngine.ps1', actions: [{ id: 'sq', label: 'SQ (stub)' }] }),
      ItUi.actionCard({ title: 'Guide panneau NVIDIA', script: 'drivers/NVIDIA-ControlPanel-Guide.ps1', actions: [{ id: 'guide', label: 'Guide (stub)' }] }),
      ItUi.actionCard({ title: 'GPU Overclock', script: 'drivers/GPU-Overclock.ps1', actions: [{ id: 'oc', label: 'OC (stub)' }] }),
      ItUi.actionCard({ title: 'Profil .nip', text: 'tools/nvidia/sq_competitive.nip', actions: [{ id: 'nip', label: 'Ouvrir profil', primary: true }] })
    ].join('');
    this._bindDrivers(main);
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);

    this._fetchInBackground(
      pageId,
      main,
      () => window.italianTweaks.drivers.getNvidiaStatus(),
      (payload) => this._applyDriversNvidia(main, payload),
      () => {
        ItPageLoader.setCardStatus(main, 'nvidia-status', 'Vérification en arrière-plan', 'warn');
        ItPageLoader.setCardText(main, 'nvidia-status', 'Données indisponibles pour le moment.');
      }
    );
  },

  _bindConnexion(main) {
    const grid = main.querySelector('#pg');
    ItApi.bindPage(grid, {
      refresh: () => this.renderConnexion(main),
      game: () => window.italianTweaks.network.gaming(),
      dl: () => window.italianTweaks.network.download(),
      opt: () => window.italianTweaks.network.optimization(),
      lat: () => window.italianTweaks.network.latency(),
      tcp: () => window.italianTweaks.network.tcp(),
      rst: () => window.italianTweaks.network.restore()
    });
  },

  renderConnexion(main) {
    const pageId = 'connexion';
    const t0 = performance.now();
    const cached = ItPageCache.get(pageId);
    const d = cached?.payload?.data || {};
    const pingText = cached ? `Ping: ${d.pingMs ?? 'N/D'} ms` : 'Analyse de la latence réseau…';
    const grid = this._mountPage(main, 'Connexion', 'scripts/network/');
    grid.innerHTML = [
      ItUi.actionCard({
        title: 'État réseau',
        text: pingText,
        status: cached ? 'OK' : 'Chargement…',
        statusType: cached ? 'ok' : 'pending',
        cardId: 'network-status',
        script: 'network/Get-NetworkStatus.ps1',
        actions: [{ id: 'refresh', label: 'Actualiser' }]
      }),
      ItUi.actionCard({ title: 'Profil Gaming', script: 'network/Apply-GamingNetworkProfile.ps1', actions: [{ id: 'game', label: 'Appliquer', primary: true }] }),
      ItUi.actionCard({ title: 'Profil Download', script: 'network/Apply-DownloadNetworkProfile.ps1', actions: [{ id: 'dl', label: 'Appliquer' }] }),
      ItUi.actionCard({ title: 'Optimisation réseau', script: 'network/Apply-NetworkOptimization.ps1', actions: [{ id: 'opt', label: '21_Network (stub)' }] }),
      ItUi.actionCard({ title: 'Réduction latence', script: 'network/Apply-LatencyReduction.ps1', actions: [{ id: 'lat', label: '23_Latency (stub)' }] }),
      ItUi.actionCard({ title: 'TCP Optimizer', script: 'network/Launch-TcpOptimizer.ps1', actions: [{ id: 'tcp', label: 'Lancer', primary: true }] }),
      ItUi.actionCard({ title: 'Restaurer défauts', script: 'network/Restore-NetworkDefaults.ps1', actions: [{ id: 'rst', label: 'Restaurer', primary: true }] })
    ].join('');
    this._bindConnexion(main);
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);

    this._fetchInBackground(
      pageId,
      main,
      () => window.italianTweaks.network.status(),
      (payload) => {
        const nd = payload?.data || {};
        ItPageLoader.setCardText(main, 'network-status', `Ping: ${nd.pingMs ?? 'N/D'} ms`);
        ItPageLoader.setCardStatus(main, 'network-status', 'OK', 'ok');
      },
      () => {
        ItPageLoader.setCardStatus(main, 'network-status', 'Vérification en arrière-plan', 'warn');
        ItPageLoader.setCardText(main, 'network-status', 'Données indisponibles pour le moment.');
      }
    );
  },

  _bindJeu(main, gameLabels) {
    const grid = main.querySelector('#pg');
    const handlers = {
      'wz-detect': () => window.italianTweaks.games.warzoneDetect(),
      'wz-apply': () => window.italianTweaks.games.warzoneApply(),
      'wz-restore': () => window.italianTweaks.games.warzoneRestore()
    };
    Object.keys(gameLabels).forEach((id) => { handlers[`g-${id}`] = () => window.italianTweaks.games.apply(id); });
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
        text: `Équivalent TUNEDPC ${id}`,
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
      () => window.italianTweaks.games.warzoneDetect(),
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

  renderOptimisation(main) {
    const pageId = 'optimisation';
    const t0 = performance.now();
    const grid = this._mountPage(main, 'Optimisation', 'scripts/optimizations/');
    grid.innerHTML = [
      ItUi.actionCard({
        title: 'État',
        text: 'Cliquez sur Lire pour analyser (non bloquant).',
        status: 'Prêt',
        cardId: 'optim-status',
        script: 'optimizations/Get-OptimizationStatus.ps1',
        actions: [{ id: 'st', label: 'Lire', primary: true }]
      }),
      ItUi.actionCard({ title: 'Debloat', script: 'optimizations/Apply-Debloat.ps1', actions: [{ id: 'deb', label: 'Appliquer', primary: true }, { id: 'deb-r', label: 'Restaurer' }] }),
      ItUi.actionCard({ title: 'Mode Jeu', script: 'optimizations/Apply-GameMode.ps1', actions: [{ id: 'gm', label: 'Activer', primary: true }, { id: 'gm-r', label: 'Désactiver' }] }),
      ItUi.actionCard({ title: 'Plan alimentation', script: 'optimizations/Apply-PowerPlan.ps1', actions: [{ id: 'pwr', label: 'Performances', primary: true }, { id: 'pwr-r', label: 'Restaurer' }] }),
      ItUi.actionCard({ title: 'Jeux fenêtrés', script: 'optimizations/Apply-WindowedGameOptimizations.ps1', actions: [{ id: 'win', label: 'Appliquer (stub)' }] }),
      ItUi.actionCard({ title: 'Windows Optimization', script: 'optimizations/Apply-WindowsOptimization.ps1', actions: [{ id: 'wo', label: '01_Windows (stub)' }] }),
      ItUi.actionCard({ title: 'Deep Debloat', script: 'optimizations/Apply-DeepDebloat.ps1', actions: [{ id: 'deep', label: '30_Deep (stub)' }, { id: 'undo', label: '31_Undo (stub)' }] }),
      ItUi.actionCard({ title: 'Copilot / WU', script: 'optimizations/', actions: [{ id: 'cop', label: 'Copilot off' }, { id: 'wuoff', label: 'WU off' }, { id: 'wuon', label: 'WU on' }] })
    ].join('');
    ItPageLoader.log(pageId, 'shell', performance.now() - t0);
    ItApi.bindPage(grid, {
      st: (btn) => ItApi.run(async () => {
        ItPageLoader.setCardStatus(main, 'optim-status', 'Analyse en cours…', 'pending');
        return ItPageLoader.run(window.italianTweaks.optim.status(), ItPageLoader.READ_MS);
      }, btn),
      deb: () => window.italianTweaks.optim.debloat(),
      'deb-r': () => window.italianTweaks.optim.debloatRestore(),
      gm: () => window.italianTweaks.optim.gameMode(),
      'gm-r': () => window.italianTweaks.optim.gameModeRestore(),
      pwr: () => window.italianTweaks.optim.power(),
      'pwr-r': () => window.italianTweaks.optim.powerRestore(),
      win: () => window.italianTweaks.optim.windowed(),
      wo: () => window.italianTweaks.optim.windows(),
      deep: () => window.italianTweaks.optim.deepDebloat(),
      undo: () => window.italianTweaks.optim.undoDeepDebloat(),
      cop: () => window.italianTweaks.optim.copilot(),
      wuoff: () => window.italianTweaks.optim.wuOff(),
      wuon: () => window.italianTweaks.optim.wuOn()
    });
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
        return ItPageLoader.run(window.italianTweaks.audio.status(), ItPageLoader.READ_MS);
      }, btn),
      ap: () => window.italianTweaks.audio.apply(),
      rs: () => window.italianTweaks.audio.restore(),
      open: () => window.italianTweaks.audio.openSettings()
    });
  },

  renderCompte(main) {
    main.innerHTML = `${this._header('Compte / Abonnement', 'Licence locale — hors TUNEDPC cloud')}<div class="card-grid">${ItUi.actionCard({ title: 'Performance Suite', text: 'Abonnement à brancher (pas de .ps1.enc Auth).', status: 'Local', actions: [{ id: 'x', label: '—', disabled: true }] })}</div>`;
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
    main._itUpdateUnsub = window.italianTweaks.updates.onStatus((payload) => {
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
        <p class="action-card__text">Vérifie et installe la dernière version depuis GitHub (SanaaCOD/italian-tweaks).</p>
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
        await window.italianTweaks.settings.save({ confirmDangerousActions: !s.confirmDangerousActions });
        this.renderReglages(main);
      },
      rst: async () => {
        await window.italianTweaks.settings.reset();
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
      () => window.italianTweaks.settings.get(),
      (payload) => this._applyReglagesOther(main, payload),
      () => {
        ItPageLoader.setCardStatus(main, 'settings-confirm', 'Données indisponibles', 'warn');
      }
    );
  }
};
