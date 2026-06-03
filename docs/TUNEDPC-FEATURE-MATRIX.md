# Matrice fonctionnelle TUNEDPC → ITALIAN TWEAKS

**Source :** `TUNEDPC-Optimizer-FULL.zip` (analyse noms + assets, **sans déchiffrement** `.ps1.enc`)

| Page | Fonction visible | Fichier / source TUNEDPC | État |
|------|----------------|--------------------------|------|
| **Accueil** | CPU/RAM/GPU %, modèles, horodatage | `Detect-USBDevices` (enc), stats WMI (enc) | **Recréé** — `Get-SystemStats.ps1` |
| **Périphériques** | Manettes PS4/PS5/Xbox, polling, boost 1000Hz, restore 125Hz | `Apply-ControllerOC.ps1.enc`, `Detect-USBDevices.ps1.enc`, `hidusbf/` | **PurpleBoost** `scripts/lib/devices/*` |
| **Drivers** | GPU NVIDIA, version pilote, DDU, NVCleanInstall, profil SQ | `13_GPU_Optimization.ps1.enc`, `07_NVIDIA_*.enc`, `sq_competitive.nip` | **PurpleBoost** `Get-NvidiaDriverStatus` + lanceurs + `.nip` |
| **Connexion** | Profil gaming/download, TCP Optimizer, restore | `21_Network_Optimization.ps1.enc`, `28_Network_Restore_Defaults.ps1.enc` | **Recréé** — profils netsh (PurpleBoost HTA) |
| **Jeu** | Profils par jeu (COD, Fortnite, …) | `02_BlackOps7_Settings.ps1.enc`, etc. | **Warzone** assets copiés ; autres **à recréer** |
| **Optimisation** | Debloat, Game Mode, HAGS, alimentation | `01_Windows_Optimization.ps1.enc`, `30_Deep_Debloat.ps1.enc`, playbook YAML | **PurpleBoost** Debloat/ModeJeu/GestionAlimentation |
| **Son** | Audio / latence | (souvent vide dans clones) | **Recréé** — `Get-AudioStatus.ps1` (détection) |
| **Compte** | Abonnement Pro | Auth (enc) | **UI locale** — pas de licence TUNEDPC |
| **Réglages** | Préférences app, logs | `app.asar` | **Recréé** — `settings.json` local |

## Scripts `.ps1.enc` (liste complète — fonction à recréer)

`00_MASTER_RUN_ALL` … `31_Undo_Deep_Debloat`, `Apply-ControllerOC`, `Detect-BiosState`, `Detect-USBDevices`, `RESTORE_DEFAULTS`, `REVERT_ALL`, `SQEngine` — **contenu inaccessible**, équivalents via PurpleBoost ou nouveaux scripts clairs.

## Utilisable légalement

- Structure navigation, UX, cartes (référence visuelle)
- `BO7BACKUP/*`, `sq_competitive.nip` (fichiers fournis dans le zip — usage selon votre licence)
- Playbook YAML (modèle de debloat externe AME)
- HIDUSBF INF (driver tiers)

## Déjà dans ITALIAN TWEAKS

Voir `legacy-purpleboost/INVENTORY.md` et services `src/services/*`.
