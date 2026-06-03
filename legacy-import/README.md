# legacy-import — PurpleBoost / Unreal

**Source :** `C:\Users\Sanaa\Desktop\PurpleBoost_FULL_BACKUP_20260603_200134`  
**Ne pas modifier** l’ancienne app. Importer uniquement des scripts **déjà testés** dans `scripts/lib/` ou remplacer les stubs dans `scripts/<domain>/`.

## Déjà intégré (via `scripts/lib/`)

| PurpleBoost | ITALIAN TWEAKS | Remplacer stub ? |
|-------------|----------------|------------------|
| `Scripts/Devices/*.ps1` | `controllers/Get-Controllers.ps1` appelle lib | Non — logique active |
| `Get-NvidiaDriverStatus.ps1` | `drivers/Get-NvidiaStatus.ps1` | Non |
| `Optimisation/Debloat/*.ps1` | `optimizations/Apply-Debloat.ps1` | Non |
| `Optimisation/ModeJeu/*.ps1` | `optimizations/Apply-GameMode.ps1` | Non |
| `Optimisation/GestionAlimentation/*.ps1` | `optimizations/Apply-PowerPlan.ps1` | Non |
| `assets/Warzone/*` | `games/Apply-WarzoneProfile.ps1` | Non |

## À importer plus tard (fragile ou UI auto)

| PurpleBoost | Cible ITALIAN TWEAKS |
|-------------|---------------------|
| `nvcleaninstall-auto-uia.ps1` | `drivers/Run-NVCleanInstall.ps1` (remplacer stub par votre automation) |
| `NVIDIA-PS1/*.ps1` | `drivers/Apply-NvidiaOptimization.ps1` |
| `ddu-auto-clean.ahk` | `drivers/Run-DDU.ps1` |
| `Unreal.hta` (logique réseau/jeu) | Déjà recréé en scripts clairs |

## Stubs = équivalent TUNEDPC `.ps1.enc`

Tous les fichiers `scripts/games/Apply-*Settings.ps1` et la majorité des `optimizations/*` / `drivers/*` stubs correspondent aux noms TUNEDPC listés dans `docs/TUNEDPC-FEATURE-MATRIX.md`.  
**Remplacez le corps du .ps1** — l’UI et l’IPC ne changent pas.
