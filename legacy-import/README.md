# legacy-import — scripts historiques

**Source :** backup PurpleBoost (2026-06)  
**Ne pas modifier** l’ancienne app. Importer uniquement des scripts **déjà testés** dans `scripts/lib/` ou remplacer les stubs dans `scripts/<domain>/`.

## Déjà intégré (via `scripts/lib/` ou `scripts/optimizations/`)

| Source | Destination Kojo | État |
|--------|------------------|------|
| Devices / HIDUSBF | `controller-oc.js` + `resources/hidusbf` | actif |
| `Get-NvidiaDriverStatus.ps1` | `drivers/Get-NvidiaStatus.ps1` | actif |
| Debloat / Mode Jeu / Alimentation | `optimizations/debloat`, `mode-jeu`, `gestion-alimentation` | actif |
| Warzone assets | `assets/game/warzone/` | actif |

## À importer plus tard (fragile ou UI auto)

| Source | Cible Kojo |
|--------|------------|
| nvcleaninstall automation | `drivers/Run-NVCleanInstall.ps1` |
| NVIDIA panel scripts | `drivers/Apply-NvidiaOptimization.ps1` |
| DDU automation | `drivers/Run-DDU.ps1` |

## Stubs

Les fichiers `scripts/games/Apply-*Settings.ps1` et une partie de `optimizations/*` / `drivers/*` sont des placeholders.  
**Remplacez le corps du .ps1** — l’UI et l’IPC ne changent pas.
