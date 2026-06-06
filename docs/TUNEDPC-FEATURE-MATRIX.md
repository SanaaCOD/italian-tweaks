# Matrice fonctionnelle — legacy → Kojo

**Source historique :** analyse noms + assets d’un bundle `.ps1.enc` (sans déchiffrement).

| Page | Fonction visible | Source legacy | État Kojo |
|------|----------------|---------------|-----------|
| **Accueil** | CPU/RAM/GPU %, modèles, horodatage | stats WMI | **Recréé** — `Get-SystemStats.ps1` |
| **Périphériques** | Manettes PS4/PS5/Xbox, polling HIDUSBF | Controller OC | **Intégré** — `controller-oc.js` + HIDUSBF |
| **Drivers** | GPU NVIDIA, version pilote, DDU, NVCleanInstall | scripts NVIDIA | **Intégré** — `Get-NvidiaDriverStatus` + lanceurs |
| **Connexion** | Profil gaming/download, TCP Optimizer, restore | profils netsh | **Recréé** — scripts réseau Kojo |
| **Jeu** | Profils par jeu (COD, Fortnite, …) | configs chiffrées | **Warzone** actif ; autres stubs |
| **Optimisation** | Debloat, Mode Jeu, alimentation | scripts Optimisation | **Intégré** — toggles + `optimizations/*` |
| **Son** | Audio / latence | — | **Recréé** — `Get-AudioStatus.ps1` |
| **Compte** | Abonnement Pro | auth cloud | **UI locale** |
| **Réglages** | Préférences app, mises à jour | app settings | **Recréé** — `settings.json` local |

## Stubs à compléter

Scripts `.ps1.enc` historiques (`00_MASTER_RUN_ALL`, profils jeux individuels, etc.) — contenu inaccessible ; remplacer progressivement les stubs dans `scripts/`.

## Déjà dans Kojo

Voir `legacy-purpleboost/INVENTORY.md` et services `src/services/*`.
