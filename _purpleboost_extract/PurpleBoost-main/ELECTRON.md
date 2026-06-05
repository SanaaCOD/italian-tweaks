# Unreal / PurpleBoost — build Electron (.exe)

## Point d’entrée réel

L’application fonctionnelle est **`Unreal.hta`** (HTML + JScript + **ActiveX** : FSO, Shell, WMI, MSXML).  
Il n’existe pas de `unreal.html` autonome dans ce dépôt : le fichier `unreal.html` est un rappel uniquement.

**Electron ne peut pas exécuter ActiveX.** Le `.exe` généré :

1. Démarre un processus Electron minimal (sans fenêtre navigateur).
2. Lance **`mshta.exe Unreal.hta --base-dir <dossier app>`** avec `UNREAL_APP_BASE` défini.
3. Se ferme quand vous fermez l’application HTA.

L’UI (sidebar, Drivers, login, etc.) reste celle d’**Unreal.hta**, inchangée.

## Commandes

```bash
npm install
npm start          # dev : lance mshta depuis le dossier du projet
npm run build      # portable + installateur NSIS dans dist/
```

## Sorties build (`dist/`)

| Artefact | Description |
|----------|-------------|
| `Unreal Gaming Optimizer-*-Portable.exe` | Exécutable portable |
| `Unreal Gaming Optimizer-*-Setup.exe` | Installateur NSIS |

## Contenu embarqué

- `Unreal.hta`, `PurpleBoost.hta`
- `Scripts/` (PowerShell)
- `assets/`, `config/`, `tools/`
- `asar: false` pour que les scripts PS1 restent accessibles sur disque

Exclus : `logs/`, `_cleanup_quarantine/`, `node_modules/`, `dist/`

## Droits administrateur

- Le manifeste Electron est **`asInvoker`** (pas d’UAC au simple double-clic sur le .exe).
- **Unreal.hta** demande déjà l’élévation admin au démarrage (comme en développement).

Pour forcer l’admin sur le .exe plus tard : `build.requestedExecutionLevel` → `requireAdministrator` dans `package.json`.

## Mise à jour automatique

Non incluse à cette étape (pas de `electron-updater`).
