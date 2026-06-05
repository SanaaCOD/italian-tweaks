# Archive — automatisation panneau NVIDIA (retirée)

Ces éléments ont été retirés de l’interface Unreal car ils ne produisaient pas de résultat fiable ou affichaient un succès non vérifié.

## Fichiers archivés

- `nvidia-preview-performance-uia.ps1` — UI Automation panneau NVIDIA (curseur « Ajuster les paramètres d'image avec aperçu »)

## Fonctions retirées de Unreal.hta

- `applyNvidiaPreviewPerformanceMode`
- `applyNvidiaFullProfileFromUi` / `applyNvidiaFullProfileImpl`
- Cartes « Panneau NVIDIA » (doublon) et « Profil NVIDIA complet » (liste de statuts)
- Statuts : mode performance aperçu, scaling, éclat numérique, G-Sync via helper (hors scope base)

## Conservé (base Nvidia Gaming)

- Import `.nip` via NVIDIA Profile Inspector
- Résolution / fréquence max via `UnrealNvidiaDisplayHelper.exe` ou `apply-nvidia-display-profile.ps1`
- Détection GPU / pilote (page Drivers)
- Logs : `logs/nvidia-gaming.log`, `logs/nvidia-profile.log`, `logs/nvidia-display-helper.log`

## V2 prévue (stubs dans Unreal.hta)

- `ApplyDigitalVibrance`, `ApplyGsyncOff`, `ApplyNoScaling`, `VerifyNvidiaSettings`
