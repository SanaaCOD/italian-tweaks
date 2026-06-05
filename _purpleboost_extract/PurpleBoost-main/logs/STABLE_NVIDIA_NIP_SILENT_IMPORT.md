# Point de sauvegarde : stable-nvidia-nip-silent-import

**Date :** 2026-05-19  
**Statut :** verrouillé — ne pas réécrire le flux d’application du `.nip`

## Comportement validé

- Profil `.nip` appliqué correctement
- Nvidia Profile Inspector **ne s’ouvre plus** visuellement
- Import silencieux `-silentImport` opérationnel
- Paramètres 3D Nvidia appliqués
- DDU inchangé et fonctionnel
- NVCleanInstall inchangé et fonctionnel

## Fichiers concernés (ne pas refactoriser)

| Fichier | Rôle |
|---------|------|
| `Unreal.hta` | `ApplyNipProfile`, `runNvidiaAutomationV2ApplyNipOnly` |
| `tools/nvidia-automation-v2/.../NipSilentImportService.cs` | Process C# masqué |
| `tools/nvidia-automation-v2/.../NipProfileService.cs` | Orchestration `--apply-nip` |

## Log de validation

Au démarrage (health check) : `NPI silent import validated`  
Fichiers : `logs/nvidia-profile.log`, `logs/nvidia-gaming.log`, `logs/automation-health.log`

## Git (si disponible)

```bash
git tag -a stable-nvidia-nip-silent-import -m "NPI silent import validated and locked"
```
