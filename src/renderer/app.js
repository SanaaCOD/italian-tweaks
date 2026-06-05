/**
 * Kojo — shell navigation + pages fonctionnelles
 */

const NAV = [
  { label: 'PRINCIPAL', items: [{ id: 'accueil', title: 'Accueil', icon: 'home' }] },
  {
    label: 'MATÉRIEL & RÉSEAU',
    items: [
      { id: 'peripheriques', title: 'Périphériques', icon: 'usb' },
      { id: 'drivers', title: 'Drivers', icon: 'chip' },
      { id: 'connexion', title: 'Connexion', icon: 'network' }
    ]
  },
  {
    label: 'JEU & OPTIMISATION',
    items: [
      { id: 'jeu', title: 'Jeu', icon: 'gamepad' },
      { id: 'optimisation', title: 'Optimisation', icon: 'bolt' },
      { id: 'son', title: 'Son', icon: 'volume' }
    ]
  },
  {
    label: 'COMPTE',
    items: [
      { id: 'compte', title: 'Compte / Abonnement', icon: 'user' },
      { id: 'reglages', title: 'Réglages', icon: 'settings' }
    ]
  }
];

const ICONS = {
  home: '<svg viewBox="0 0 24 24"><path d="M3 10.5 12 3l9 7.5V21a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1z"/></svg>',
  usb: '<svg viewBox="0 0 24 24"><rect x="7" y="2" width="10" height="6" rx="1"/><path d="M12 8v6M9 14h6M10 20h4"/></svg>',
  chip: '<svg viewBox="0 0 24 24"><rect x="5" y="5" width="14" height="14" rx="2"/><path d="M9 5V3M15 5V3M9 21v-2M15 21v-2M5 9H3M5 15H3M21 9h-2M21 15h-2"/></svg>',
  network: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="2"/><path d="M5 12a7 7 0 0 1 14 0M2 12a10 10 0 0 1 20 0"/></svg>',
  gamepad: '<svg viewBox="0 0 24 24"><path d="M6 12h4v4H6zM14 10h4v4h-4zM4 8h16a4 4 0 0 1 4 4v0a6 6 0 0 1-6 6H6a6 6 0 0 1-6-6v0a4 4 0 0 1 4-4z"/></svg>',
  bolt: '<svg viewBox="0 0 24 24"><path d="M13 2 4 14h7l-1 8 10-14h-7z"/></svg>',
  volume: '<svg viewBox="0 0 24 24"><path d="M11 5 6 9H3v6h3l5 4V5z"/><path d="M15 9a4 4 0 0 1 0 6M17 7a7 7 0 0 1 0 10"/></svg>',
  user: '<svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 20a8 8 0 0 1 16 0"/></svg>',
  settings: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>'
};

const PAGE_RENDERERS = {
  accueil: (main) => ItPages.renderAccueil(main),
  peripheriques: (main) => ItPages.renderPeripheriques(main),
  drivers: (main) => ItPages.renderDrivers(main),
  connexion: (main) => ItPages.renderConnexion(main),
  jeu: (main) => ItPages.renderJeu(main),
  optimisation: (main) => ItPages.renderOptimisation(main),
  son: (main) => ItPages.renderSon(main),
  compte: (main) => ItPages.renderCompte(main),
  reglages: (main) => ItPages.renderReglages(main)
};

let currentPage = 'accueil';
let navGeneration = 0;
let statsRefreshTimer = null;
const sidebarNav = document.getElementById('sidebar-nav');
const mainContent = document.getElementById('main-content');

function renderSidebar() {
  sidebarNav.innerHTML = NAV.map(
    (g) => `
    <div class="nav-group">
      <span class="nav-group__label">${g.label}</span>
      ${g.items
        .map(
          (item) => `
        <button type="button" class="nav-item${item.id === currentPage ? ' nav-item--active' : ''}" data-page="${item.id}">
          <span class="nav-item__icon">${ICONS[item.icon]}</span>
          <span>${item.title}</span>
        </button>`
        )
        .join('')}
    </div>`
  ).join('');
  sidebarNav.querySelectorAll('.nav-item').forEach((btn) => {
    btn.addEventListener('click', () => navigate(btn.dataset.page));
  });
}

function renderPage() {
  const t0 = performance.now();
  mainContent.classList.toggle('main--accueil', currentPage === 'accueil');
  const fn = PAGE_RENDERERS[currentPage];
  if (fn) fn(mainContent);
  ItPageLoader.log(currentPage, 'shell painted', performance.now() - t0);
}

function navigate(pageId) {
  if (!PAGE_RENDERERS[pageId]) return;
  const t0 = performance.now();
  currentPage = pageId;
  navGeneration += 1;
  mainContent.dataset.navGen = String(navGeneration);
  renderSidebar();
  renderPage();
  ItPageLoader.log(pageId, 'navigate click→shell', performance.now() - t0);
  if (pageId === 'accueil') startStatsRefresh();
  else stopStatsRefresh();
}

function startStatsRefresh() {
  stopStatsRefresh();
  const tick = async () => {
    if (currentPage !== 'accueil') return;
    try {
      const stats = await window.italianTweaks.system.getStats({ full: false });
      if (mainContent.querySelector('.page-accueil')) {
        ItPages.updateAccueilStats(mainContent, stats);
      }
    } catch (e) {
      console.warn('[Accueil stats] refresh failed', e);
    }
  };
  statsRefreshTimer = setInterval(tick, 8000);
  tick();
}

function stopStatsRefresh() {
  if (statsRefreshTimer) {
    clearInterval(statsRefreshTimer);
    statsRefreshTimer = null;
  }
}

async function initSidebarBuildInfo() {
  const el = document.getElementById('sidebar-build-id');
  const devHint = document.getElementById('sidebar-dev-hint');
  const updBtn = document.getElementById('sidebar-check-update');
  try {
    const info = await ItApi.app.getBuildInfo();
    if (el) {
      el.textContent = info.displayLine || `v${info.version} · build ${info.builtAt} · ${info.commit}`;
      el.title = `Build ID: ${info.buildId || ''}${info.packaged ? ' (installateur)' : ' (dev)'}`;
    }
    if (devHint) {
      let updateMode = 'dev';
      if (!info.devMode) {
        try {
          const verRes = await ItApi.updates.getVersion();
          updateMode = verRes?.data?.updateMode || 'installed';
        } catch {
          updateMode = 'installed';
        }
      }
      if (info.devMode) {
        devHint.hidden = false;
        devHint.textContent = 'Mode dev — update réel indisponible';
      } else if (updateMode === 'local_build') {
        devHint.hidden = false;
        devHint.textContent =
          'Mode test local — installe la version Setup pour tester les mises à jour réelles';
      } else {
        devHint.hidden = true;
      }
    }
    window.__itBuildInfo = info;
  } catch (e) {
    if (el) el.textContent = 'Build info indisponible';
    console.warn('[build-info]', e);
  }

  if (updBtn && !updBtn._itBound) {
    updBtn._itBound = true;
    updBtn.addEventListener('click', () => {
      if (typeof ItPages.runGlobalUpdateCheck === 'function') {
        ItPages.runGlobalUpdateCheck(updBtn);
      }
    });
  }
}

navGeneration = 1;
mainContent.dataset.navGen = '1';
renderSidebar();
renderPage();
startStatsRefresh();
initSidebarBuildInfo();
