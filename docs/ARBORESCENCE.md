# Arborescence ITALIAN TWEAKS

```
italian-tweaks/
├── assets/                    # logo, background, game/warzone/
├── docs/                      # matrices TUNEDPC, arborescence
├── legacy-import/             # guide import PurpleBoost
├── legacy-purpleboost/        # inventaire copie lib
├── logs/                      # JSON cache, logs scripts
├── scripts/
│   ├── _common/               # ItalianTweaks.Json.ps1 (contrat)
│   ├── system/                # Get-SystemStats, Restore, Revert, Master
│   ├── controllers/           # Get-Controllers, Apply/Restore polling, OC
│   ├── drivers/               # NVIDIA, DDU, NVClean, stubs TUNEDPC GPU
│   ├── network/               # profils, TCP, restore
│   ├── games/                 # Warzone + stubs par jeu TUNEDPC
│   ├── optimizations/       # Debloat, GameMode, Power, stubs
│   ├── audio/                 # Get + stubs
│   └── lib/                   # scripts PurpleBoost (exécution interne)
├── tools/
│   ├── ddu/ hidusbf/ nvcleanstall/ tcpoptimizer/ nvidia/
├── src/
│   ├── main.js
│   ├── preload.js
│   ├── ipc/handlers.js
│   ├── services/              # 1 service = 1 domaine scripts/
│   └── renderer/
│       ├── app.js pages.js ui.js api.js styles.css index.html
└── package.json
```

## Flux

`Bouton UI` → `preload` → `ipc/handlers` → `services/*.js` → `script-runner` → `scripts/<domain>/*.ps1` → **JSON** → UI (statut + log JSON)
