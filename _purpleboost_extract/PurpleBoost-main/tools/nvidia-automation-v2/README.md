# Nvidia Automation V2

Service modulaire pour automatiser les réglages Nvidia gaming (NIP, affichage, G-Sync, éclat numérique, téléciné registre). Aucune automatisation du panneau de contrôle NVIDIA.

## Exécutable

`NvidiaAutomationV2.exe` — build :

```powershell
.\build.ps1
```

## Outils externes (optionnels)

| Réglage | Outil | Emplacement suggéré |
|--------|--------|----------------------|
| Éclat numérique | API NVAPI / ColorControl | intégré V2 |
| G-Sync off | `gsynctoggle.exe` | `tools/gsync-toggle/` |
| Profil 3D | `.nip` + NPI | `tools/profiles/` |

## CLI

```
NvidiaAutomationV2.exe --apply-all --json --purpleboost-root "C:\...\PurpleBoost"
NvidiaAutomationV2.exe --apply-nip --json --purpleboost-root "..."
NvidiaAutomationV2.exe --apply-digital-vibrance-80 --json --purpleboost-root "..."
NvidiaAutomationV2.exe --disable-gsync-only --json --purpleboost-root "..."
NvidiaAutomationV2.exe --disable-inverse-telecine-registry-only --json --purpleboost-root "..."
```

## Méthodes (`NvidiaAutomationV2Service`)

- `ApplyAllNvidiaGamingSkipNipIfNeeded()`
- `ApplyNipProfile()`
- `ApplyMaxResolutionAndRefreshRate()`
- `ApplyDigitalVibrance80()`
- `DisableGsyncIfToolAvailable()`
- `DisableInverseTelecine()` (registre)
- `VerifyAll()`

## Logs

`logs/nvidia-automation-v2.log`
