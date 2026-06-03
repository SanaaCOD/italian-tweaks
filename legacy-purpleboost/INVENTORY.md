# PurpleBoost → ITALIAN TWEAKS — inventaire récupération

**Source :** `C:\Users\Sanaa\Desktop\PurpleBoost_FULL_BACKUP_20260603_200134`  
**Ne pas réutiliser :** `Unreal.hta`, CSS HTA, ancien shell Electron cassé.

## Copié dans italian-tweaks

| Fichier source | Destination | Rôle | État |
|----------------|-------------|------|------|
| `Scripts/Devices/*.ps1` | `scripts/lib/devices/` | Manettes PnP, HIDUSBF, polling | stable |
| `Scripts/Get-NvidiaDriverStatus.ps1` | `scripts/lib/nvidia/` | GPU / pilote / version | stable |
| `Scripts/Optimisation/Debloat/*.ps1` | `scripts/lib/optimisation/Debloat/` | Debloat Windows | stable (UAC admin) |
| `Scripts/Optimisation/ModeJeu/*.ps1` | `scripts/lib/optimisation/ModeJeu/` | Mode jeu | stable |
| `Scripts/Optimisation/GestionAlimentation/*.ps1` | `scripts/lib/optimisation/GestionAlimentation/` | Plan alimentation | stable |
| `assets/Warzone/s.1.0.cod25.*` | `assets/game/warzone/` | Profil COD/Warzone | stable |

## Référencé / à éviter

| Fichier | Raison |
|---------|--------|
| `Scripts/nvcleaninstall-auto-uia.ps1` | UI automation fragile — lancer manuellement avec confirmation |
| `ddu-auto-clean.ahk` | Auto DDU risqué — ouvrir DDU manuellement |
| `Unreal.hta` | Monolithe HTA — logique réimplémentée en services Node |

## TUNEDPC (.ps1.enc) — à recréer (non déchiffré)

Voir `docs/TUNEDPC-FEATURE-MATRIX.md`.
