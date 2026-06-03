/**
 * ITALIAN TWEAKS — shell navigation + pages fonctionnelles
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

function initLowPolyCanvas() {
  const canvas = document.getElementById('lowpoly-canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  let triangles = [];
  const SHADES = ['#0b0b0d', '#0c0c0f', '#0d0d11', '#0e0e12', '#101014', '#111116', '#121218'];
  const hash = (i, j) => ((i * 92837111) ^ (j * 689287499)) >>> 0;
  const shadeAt = (i, j) => SHADES[hash(i, j) % SHADES.length];

  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = window.innerWidth;
    const h = window.innerHeight;
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const cellW = 118;
    const cellH = cellW * 0.866;
    const jitter = cellW * 0.06;
    triangles = [];
    const pointAt = (col, row) => {
      const offsetX = row % 2 ? cellW * 0.5 : 0;
      const hx = hash(col, row);
      return {
        x: col * cellW + offsetX + ((hx % 1000) / 1000 - 0.5) * jitter - cellW,
        y: row * cellH + (((hx >> 10) % 1000) / 1000 - 0.5) * jitter - cellH
      };
    };
    for (let row = 0; row < Math.ceil(h / cellH) + 3; row++) {
      for (let col = 0; col < Math.ceil(w / cellW) + 3; col++) {
        const a = pointAt(col, row);
        const b = pointAt(col + 1, row);
        const c = pointAt(col, row + 1);
        const d = pointAt(col + 1, row + 1);
        if (hash(col, row) % 2 === 0) {
          triangles.push({ pts: [a, b, c], fill: shadeAt(col, row) });
          triangles.push({ pts: [b, d, c], fill: shadeAt(col + 1, row) });
        } else {
          triangles.push({ pts: [a, b, d], fill: shadeAt(col, row) });
          triangles.push({ pts: [a, d, c], fill: shadeAt(col, row + 1) });
        }
      }
    }
    ctx.clearRect(0, 0, w, h);
    triangles.forEach((t) => {
      ctx.beginPath();
      ctx.moveTo(t.pts[0].x, t.pts[0].y);
      ctx.lineTo(t.pts[1].x, t.pts[1].y);
      ctx.lineTo(t.pts[2].x, t.pts[2].y);
      ctx.closePath();
      ctx.fillStyle = t.fill;
      ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.025)';
      ctx.stroke();
    });
  }
  let t;
  window.addEventListener('resize', () => {
    clearTimeout(t);
    t = setTimeout(resize, 150);
  });
  resize();
}

navGeneration = 1;
mainContent.dataset.navGen = '1';
renderSidebar();
renderPage();
startStatsRefresh();
initLowPolyCanvas();
