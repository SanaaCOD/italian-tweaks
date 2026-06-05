# Audit non-régression — Nvidia Automation V2

Date : 2026-05-19

## Fichiers modifiés ou ajoutés par V2 uniquement

| Fichier | Impact |
|---------|--------|
| `Unreal.hta` | Bloc **Nvidia Gaming** + intégration V2 ; **pas** de modification du code DDU ni NVCleanInstall |
| `tools/nvidia-automation-v2/**` | Nouveau module isolé (exe + sources) |
| `tools/ColorControl/README.txt` | Placeholder outil optionnel |
| `tools/gsync-toggle/README.txt` | Placeholder outil optionnel |

## Fichiers non touchés (préservés)

- `tools/DDU/**`
- `tools/NVCleanstall/**`
- Scripts DDU / NVCleanstall existants
- Onglets HIDUSBF, Connexion, Jeu, etc.

## Fonctions vérifiées (doivent rester appelables)

### DDUAutomation
- `downloadOrOpenDdu` — téléchargement / ouverture
- `dduAutoCleanExperimental` — nettoyage GPU auto
- `launchDduAutoCleanAutomation` — automation nettoyage

### NVCleanInstallAutomation
- `openNvcleanstall` / `openNvcleanstallWithPresetGuidance`
- `openNvcleanstallOfficialDownloadPage` — téléchargement
- `launchNvcleaninstallAutoExperimental` — installation pilote auto

### Nvidia (existant + V2)
- `ApplyNipProfile` / `importNvidiaProfileNipElevated`
- `ApplyMaxResolution` / `ApplyMaxRefreshRate` / `runNvGamingDisplayApply`
- `getNvidiaAutomationV2ExePath` / `runNvidiaAutomationV2`

## Diagnostic

Au démarrage : `RunAutomationHealthCheck()` → `logs/automation-health.log`

Logs par module :
- DDU : `logs/ddu-open-download.log`
- NVCleanInstall : journal preset / `nv-media`
- NIP : `logs/nvidia-profile.log`
- Gaming / V2 : `logs/nvidia-gaming.log`, `logs/nvidia-automation-v2.log`

## Séparation

Aucune référence DDU/NVCleanInstall dans `tools/nvidia-automation-v2/`.
