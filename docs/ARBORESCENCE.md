# Arborescence Kojo

```
kojo-dev-rebuild/
├── assets/                    # logo, background, game/warzone/
├── docs/                      # matrices legacy, arborescence
├── legacy-import/             # guide import scripts historiques
├── legacy-purpleboost/        # inventaire copie lib
├── logs/                      # JSON cache, logs scripts
├── scripts/
│   ├── _common/               # Kojo.Json.ps1 (contrat JSON scripts)
│   ├── system/                # Get-SystemStats, Restore, Revert, Master
│   ├── drivers/               # NVIDIA, DDU, NVClean
│   ├── network/               # profils, TCP, restore
│   ├── games/                 # Warzone + profils par jeu
│   ├── optimizations/         # Debloat, Mode Jeu, alimentation
│   ├── audio/                 # Get + profils
│   └── lib/                   # scripts internes (exécution directe)
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

`Bouton UI` → `preload (window.kojo)` → `ipc/handlers` → `services/*.js` → `script-runner` → `scripts/<domain>/*.ps1` → **JSON** → UI (statut + log)
