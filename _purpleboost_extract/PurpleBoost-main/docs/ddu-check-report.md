# Rapport de vérification — flux DDU (onglet Drivers)

**Date :** 2026-05-20  
**Périmètre :** uniquement DDU dans l’onglet Drivers (lecture seule, aucune modification du code métier).  
**Sauvegarde de référence :** `backup-safe-no-gps-clicks-before-ddu-check`

---

## Fichiers DDU vérifiés

| Fichier | Rôle |
|---------|------|
| `Unreal.hta` | UI onglet Drivers : détection, téléchargement, ouverture admin, bouton « Nettoyage GPU automatique », polling statut, messages finaux |
| `Scripts/ddu-auto-clean.ahk` | Orchestration : attente fenêtre DDU, lancement `ddu-auto-clean-uia.ps1` |
| `Scripts/ddu-auto-clean-uia.ps1` | UIA : combos GPU/fabricant, bouton « Nettoyer et NE PAS redémarrer », pop-ups, garde anti-reboot |
| `Scripts/Safe-UiaClick.ps1` | Helpers sécurisés (dot-source DDU) ; blocage `Invoke-DduScreenClick` |
| `Scripts/ddu-final-quit-watcher.ahk` | Watcher optionnel fin de flux (non lancé par le chemin principal actuel) |
| `Scripts/ddu-final-quit-popup.ahk` | **DEPRECATED** — non inclus |
| `logs/ddu-open-download.log` | Télécharger / Ouvrir DDU |
| `logs/ddu-auto-clean.log` | Nettoyage automatique |
| `logs/ddu-auto-clean-live.txt` | Statut live (`STATUS=…`) pour l’UI |

---

## Ce qui fonctionne (vérifié dans le code)

### Télécharger / Ouvrir DDU
- Détection au chargement onglet : cache `config/tools-paths.json`, puis scan (`tools\DDU`, Bureau, Documents, Téléchargements, Program Files).
- Bouton adaptatif : « Télécharger / Ouvrir DDU » ou « Ouvrir DDU » selon détection.
- Téléchargement ZIP direct vers `tools\DDU`, extraction, recherche de l’exe.
- Ouverture **admin** via `launchDduLikeHidusbf` → `launchFileAsAdmin`.

### Nettoyage GPU automatique
1. Détection GPU (`detectGpuVendor`) ; choix manuel fabricant si ambigu.
2. Résolution exe DDU (`resolveDduExeForAutoClean`) avec téléchargement si besoin.
3. Lancement DDU admin avec `-NoSafeModeMsg`.
4. Après 500 ms : `ddu-auto-clean.ahk` (admin) → PowerShell `ddu-auto-clean-uia.ps1`.
5. UIA : sélection **GPU** + fabricant (NVIDIA/AMD/INTEL) via `SelectionItemPattern` / combos.
6. Clic **uniquement** sur bouton dont le libellé correspond à « Nettoyer et NE PAS redémarrer » (`Test-AllowedCleanNoRestart`) via **`InvokePattern`** (`Click-CleanNoRestartButton`).
7. Boutons « Nettoyer et redémarrer » / restart exclus (`Test-RestartOnlyButton`, `Test-ForbiddenCleanText`).
8. Pop-ups workflow (mode sans échec, programmes interférents) : **OK** via UIA `Click-ButtonInWindow` + `InvokePattern`, ou `ControlClick("OK")` dans l’AHK de secours avant PS1.
9. Surveillance nettoyage (~120 s) puis statut live « Nettoyage GPU terminé — redémarrage conseillé ».
10. UI HTA : `finishDduAutoCleanSuccess()` → **« Nettoyage GPU terminé — redémarrage conseillé »** à 100 %.

### Logs et messages utilisateur
- Chemins logs ci-dessus ; live `STATUS=` lu par `beginDduAutoCleanStatusPoll`.
- Messages clairs en cas d’échec : fenêtre DDU absente, bouton introuvable, timeout, action manuelle redémarrage.

---

## Anti-clics GPS (DDU)

| Élément | État |
|---------|------|
| `Invoke-DduScreenClick` | **Bloqué** — `[BLOCKED-UNSAFE-CLICK] Invoke-DduScreenClick($x,$y)` ; **aucun appel** dans le projet |
| Fallback `Left+135` / `Top+154` | **Supprimé** — log `[SAFECLICK] Fallback coordonnées bloqué…` + message manuel |
| `ddu-auto-clean.ahk` | **ControlClick** sur `"OK"` / `"&OK"` uniquement (pop-up mode sans échec), pas de `Click(x,y)` |
| Clic nettoyage | **InvokePattern** sur bouton UIA nommé ; pas de coordonnées écran |

**Confirmation :** aucun clic GPS n’a été réintroduit dans le flux DDU actif.

---

## Redémarrage non forcé

| Contrôle | Détail |
|----------|--------|
| Choix du bouton clean | Seuls libellés « clean and do **not** restart » / équivalents FR |
| Pop-ups finales | `Wait-AndHandleFinalDduPopups` : si texte restart → `restart_manual`, **pas** de clic Yes/Oui sur reboot |
| `Click-ButtonInWindow` (pop-ups) | `forbidden` inclut RESTART, REDEMARR, SHUTDOWN, etc. |
| Watcher final | `FINAL_QUIT_WATCHER=disabled` dans `ddu-auto-clean.ahk` ; HTA logue `FINAL_QUIT_AUTO=disabled` |
| Code système | **Aucun** `Restart-Computer`, `shutdown /r` dans les scripts `ddu*` actifs |
| Message final | **Conseille** le redémarrage ; **ne l’exécute pas** |

**Confirmation :** le redémarrage n’est pas forcé par l’automatisation DDU.

---

## Écart mineur (non corrigé — hors bug bloquant)

| Point | Constat |
|-------|---------|
| `[UIA-DUMP]` si bouton clean introuvable | En échec UIA, message manuel + `[SAFECLICK]` offset bloqué, mais **pas** d’appel `Write-UiaDumpForElement` dans `ddu-auto-clean-uia.ps1` (contrairement à la spec globale NVC). Recommandation future : ajouter un dump UIA sur `exit 4` sans changer la logique métier. |
| Libellé message final | Texte actuel : « Nettoyage GPU terminé — redémarrage conseillé » (proche de la spec ; pas la phrase exacte « …avant de réinstaller un pilote propre »). |

---

## Corrections effectuées lors de cette vérification

**Aucune.** Revue lecture seule uniquement, conformément à la consigne.

---

## Confirmations finales

1. **Aucun clic GPS réintroduit** dans le flux DDU actif.  
2. **Le redémarrage n’est pas forcé** ; seul le bouton « sans redémarrer » est ciblé automatiquement.  
3. Le nettoyage GPU automatique **désinstalle via DDU** (bouton UIA correct) et termine par un **message conseillant** un reboot, sans l’imposer.
