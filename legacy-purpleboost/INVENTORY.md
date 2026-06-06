# Inventaire récupération — legacy → Kojo

**Source :** backup PurpleBoost (2026-06)  
**Ne pas réutiliser :** HTA monolithique, ancien shell Electron.

## Copié dans Kojo

| Fichier source | Destination | Rôle | État |
|----------------|-------------|------|------|
| Devices / HIDUSBF | `controller-oc.js`, `resources/hidusbf` | Manettes, polling | stable |
| `Get-NvidiaDriverStatus.ps1` | `scripts/lib/nvidia/` | GPU / pilote | stable |
| Debloat / Mode Jeu / Alimentation | `scripts/optimizations/*` | Optimisation Windows | stable |
| Warzone config | `assets/game/warzone/` | Profil COD | stable |

## Référencé / à éviter

| Fichier | Raison |
|---------|--------|
| nvcleaninstall-auto-uia | UI automation fragile |
| ddu-auto-clean | Auto DDU risqué |
| HTA monolithique | logique réimplémentée en services Node |

## Scripts chiffrés legacy — à recréer

Voir `docs/TUNEDPC-FEATURE-MATRIX.md` (renommé : matrice legacy → Kojo).
