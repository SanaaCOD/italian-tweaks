# Correctifs UIA — onglet Drivers (DDU + installateur NVIDIA)

**Date :** 2026-05-23  
**Objectif :** débloquer deux points UIA sans réintroduire de clics coordonnées (GPS).

---

## Helper NVIDIA Installer élevé (admin) — 2026-05-24

### Cause confirmée
Le relais non élevé ne peut pas déplacer la souris vers l’installateur NVIDIA (UIPI / niveau d’intégrité) :
- `SetCursorPos result=False` depuis PowerShell / HTA non admin
- `SetCursorPos result=True` + clic réel fonctionnel depuis PowerShell **administrateur**

Les messages Win32 logiques (`BM_CLICK`, `WM_COMMAND`, `WM_LBUTTONDOWN/UP` sur HWND) ne suffisent pas sur les contrôles ATL NVIDIA.

### Solution
Helper dédié **administrateur** lancé automatiquement après que NVCleanstall ouvre « Programme d'installation NVIDIA » :

| Fichier | Rôle |
|---------|------|
| `Scripts/start-nvidia-installer-elevated-helper.ps1` | Lanceur HTA — `Start-Process -Verb RunAs` si non admin |
| `Scripts/nvidia-installer-elevated-helper.ps1` | Boucle wizard NVIDIA (admin requis) |
| `logs/nvidia-installer-elevated-helper.log` | Journal dédié helper |

### Méthode (pas de GPS)
- `EnumWindows` → fenêtre « Programme d'installation NVIDIA » uniquement (NVCleanstall exclu)
- `EnumChildWindows` → contrôle par `GetWindowText`
- `GetWindowRect` → centre réel du bouton
- `SetForegroundWindow` + vérif premier plan
- `SetCursorPos` + `SendInput` clic souris (repli SendInput absolu si besoin)
- **Aucune** coordonnée fixe, pourcentage écran, ou position inventée

### Intégration bouton unique
Flux inchangé pour l’utilisateur : **« Installer automatiquement le dernier pilote »**
1. NVCleanstall (inchangé)
2. Prep pilote (inchangé)
3. Ouverture Programme d'installation NVIDIA (inchangé)
4. HTA `RunNvidiaInstallerWizardLoopAsync` → `start-nvidia-installer-elevated-helper.ps1` (UAC une fois)
5. Helper élevé : Licence → Options (Personnalisée + Suivant) → Options personnalisées → Installation → 100 %

### Logs attendus
```
[NVIDIA-ELEVATED] Helper requested elevation
[NVIDIA-ELEVATED] Helper started
[NVIDIA-ELEVATED] Running as admin=True
[NVIDIA-ELEVATED] NVIDIA installer window found
[NVIDIA-ELEVATED] State detected = License
[NVIDIA-ELEVATED] License page detected
[NVIDIA-ELEVATED] License accept clicked
[NVIDIA-ELEVATED] State detected = InstallOptions
[NVIDIA-ELEVATED] Custom option clicked
[NVIDIA-ELEVATED] Options next clicked
[NVIDIA-ELEVATED] State detected = CustomOptions
[NVIDIA-ELEVATED] Custom options next clicked
[NVIDIA-ELEVATED] State detected = Installing
[NVIDIA-ELEVATED] Installation running
[NVIDIA-ELEVATED] State detected = Final
[NVIDIA-ELEVATED] Installation final state detected
```

### Bug corrigé — faux « état final » sur page Licence (2026-05-24)
- **Cause :** le libellé « Terminer » dans la **barre latérale gauche** du wizard (classe `ATL:6E016A48`, étape future) était pris pour une fin d’installation.
- **Correctif :** ordre strict Licence → Options → Options personnalisées → Installation → **Fin réelle** ; `Test-RealFinalPage` ignore les labels sidebar et exige un bouton d’action `&Terminer` / `&Finish` (classe bouton) ou un message de fin dans la zone principale.
- **Garde :** impossible de déclarer « Installation final state detected » si « ACCEPTER ET CONTINUER », « Options d’installation » ou « SUIVANT » actif est visible.
- **Page Options d’installation personnalisée (2026-05-24) :** détection via titre « Options d’installation personnalisée », « Pilote graphique », « Effectuer une nouvelle installation » + bouton `&SUIVANT` ; clic Suivant uniquement (checkbox déjà cochée, non modifiée). `Test-OptionsPage` exige désormais les radios `&Expresse` + `&Personnalisée` pour ne pas confondre avec la page personnalisée.
- **Bug corrigé — Express cliqué au lieu de Personnalisée (2026-05-24) :** sélection radio vérifiée via `BM_GETCHECK` / UIA `IsSelected` ; `BM_CLICK` + `SetFocus` sur le **HWND radio** (pas le label) ; recherche radio voisin si label ATL ; **Suivant interdit** tant que Personnalisée non cochée ; dump `logs/nvidia-installer-installoptions-radio-dump.txt` si échec.
- **Logs :** `[NVIDIA-ELEVATED] State detected = License|InstallOptions|CustomOptions|Installing|Final` ; dump ambiguïté : `logs/nvidia-installer-elevated-state-dump.txt`
- **NVCleanstall non modifié.** Aucun clic GPS ajouté.

### NVCleanstall
**Non modifié** — pages, Next/Install, téléchargement, prep.

---

## Flux intégré — bouton unique → NVCleanstall → installateur NVIDIA

Un seul bouton HTA : **« Installer automatiquement le dernier pilote »** (`launchNvcleaninstallAutoExperimental`). Aucun flux séparé pour l’installateur NVIDIA.

### Séquence complète

1. **HTA** — l’utilisateur clique « Installer automatiquement le dernier pilote ».
2. **AutoHotkey** (`nvcleaninstall-auto.ahk`) — wizard NVCleanstall inchangé (pages, Next, Install, téléchargement, prep pilote).
3. **Handoff AHK** — après lancement du setup NVIDIA, `WaitForNvidiaInstallerWindow` attend la fenêtre « Programme d'installation NVIDIA », puis journalise `NVIDIA_INSTALLER_WINDOW_READY=oui`.
4. **HTA** — `shouldStartNvidiaInstallerWizardLoop` détecte ce signal et démarre `RunNvidiaInstallerWizardLoopAsync`, qui lance **`start-nvidia-installer-elevated-helper.ps1`** (UAC) et interroge le journal pour `NVIDIA_ELEVATED_RESULT` / `NVIDIA_TICK_RESULT`.
5. **Helper élevé** — relais **uniquement** sur « Programme d'installation NVIDIA » (HWND + GetWindowRect + clic réel admin).

### NVCleanstall

**Non modifié** — pages, boutons Next/Install, logique de téléchargement et `Run-NVCleanstallWizardSimple` restent intacts.

### Logs attendus (extrait)

```
[NVCLEANSTALL] Select driver version page detected
[SAFE-UIA] Invoked button Next
...
Lancement du programme d'installation NVIDIA...
NVIDIA_INSTALLER_WINDOW_READY=oui
[NVIDIA-INSTALLER] Wizard relay active — Programme d'installation NVIDIA detected after NVCleanstall
[NVIDIA-INSTALLER] Tick running, window found: title=Programme d'installation NVIDIA
[NVIDIA-INSTALLER] License page detected
[SAFE-WIN32] Accept hwnd found: text='ACCEPTER ET CONTINUER' id=...
[SAFE-WIN32] BM_CLICK accept invoked
[SAFE-WIN32] WM_COMMAND BN_CLICKED accept sent
[NVIDIA-INSTALLER] License accepted, waiting for Options page
[NVIDIA-INSTALLER] Options page detected
[SAFE-WIN32] BM_CLICK custom invoked
[SAFE-WIN32] BM_CLICK next invoked
NVIDIA_OPTIONS_NEXT=win32_bm_click
Installation NVIDIA en cours...
[NVIDIA-INSTALLER] Progress forced to 100
```

---

## Régression NVCleanstall page 1 (corrigée)

### Cause
Lors de l’ajout MSAA/Win32 pour la page NVIDIA « Options d’installation », **erreurs de syntaxe PowerShell** dans `nvcleaninstall-auto-uia.ps1` (parenthèses manquantes sur `Test-NvidiaInstallerProgrammeWindowTitle`). Le script **ne se chargeait plus du tout** → NVCleanstall bloqué dès la page « Select Driver Version To Install ».

### Correctif
- Parenthèses corrigées sur les gardes fenêtre NVIDIA.
- **Chargement paresseux** de `NvidiaWin32Msaa-helper.cs` : uniquement via `Ensure-NvidiaWin32MsaaType` quand la page Options NVIDIA est autorisée (`Test-NvidiaInstallerOptionsAutomationAllowed`).
- MSAA/Win32 **jamais** exécutés pendant NVCleanstall (gardes titre « Programme d'installation NVIDIA » + page Options exacte + Express + Personnalisée).
- Page NVCleanstall 1 : logs `[NVCLEANSTALL] Select driver version page detected`, `[NVCLEANSTALL] Best driver already selected`, `[SAFE-UIA] Invoked button Next` ; `Invoke-NvcClickNextSafe` + repli `Click-NextButtonVisible`.
- Suppression du `else { $step1Done = $true }` qui **sautait** l’étape 1 si la page n’était pas encore détectée au premier poll.

### Confirmation
- Aucun clic GPS réintroduit.
- NVCleanstall page 1 doit à nouveau cliquer **Next** via UIA.

---

## Fichiers modifiés

| Fichier | Changement |
|---------|------------|
| `Scripts/ddu-auto-clean-uia.ps1` | `Invoke-DduKnownOkDialog`, énumération fenêtres DDU, boucles de surveillance |
| `Scripts/start-nvidia-installer-elevated-helper.ps1` | Lanceur UAC helper NVIDIA |
| `Scripts/nvidia-installer-elevated-helper.ps1` | Wizard NVIDIA admin (HWND + clic réel) |
| `Scripts/nvcleaninstall-auto-uia.ps1` | NVCleanstall + relais legacy non élevé (conservé, non utilisé par HTA pour wizard) |
| `Scripts/NvidiaWin32Msaa-helper.cs` | Types `NvidiaWin32Msaa` / `IAccessible` (compilés au runtime par le script PS1) |
| `Unreal.hta` | Mapping progression 100 % quand l’installateur NVIDIA signale l’état final |

**Non modifiés :** design/UI global, logique NVCleanstall globale (hors progression NVIDIA), autres onglets.

---

## Correction 1 — DDU : pop-ups information (bouton OK)

### Problème
Pop-ups DDU (ex. Afterburner / programmes fermés) bloquaient le flux tant qu’OK n’était pas cliqué manuellement. L’ancien handler ignorait certaines pop-ups après un premier traitement (`hasHandledDduInterferingProgramsPopup`) et utilisait parfois `SendKeys` Entrée.

### Solution
- `Invoke-DduKnownOkDialog` : parcourt `Get-DduRelatedUiWindows` (fenêtres titre DDU, fenêtre principale, panneaux enfants avec OK).
- Détecte une boîte « information » via texte (Afterburner, mode sans échec, programmes interférents, etc.) **sans** confondre avec redémarrage / quitter.
- Cherche un bouton **ControlType.Button** nommé exactement `OK`, `&OK` ou `Ok` avec **InvokePattern**.
- Valide via **`SafeInvokeElement`** uniquement.
- Log succès : `[SAFE-UIA] DDU popup OK invoked: title=... text=...`
- Si pop-up détectée sans OK cliquable : **`[UIA-DUMP]`** + `DDU popup detected but OK button not found` + message manuel.

### Interdit (respecté)
- Pas de coordonnées, pas de `SendKeys` Entrée aveugle, pas de clic centre fenêtre.

---

## Correction 2a — Installateur NVIDIA : page Licence (Win32 HWND)

### Problème
Le wizard NVIDIA bloquait sur « Contrat de licence du logiciel NVIDIA » — le correctif Options ne s’appliquait pas à cette page.

### Solution
- **`Invoke-NvidiaInstallerLicenseViaWin32Handles`** — **Win32 HWND uniquement** (pas de GPS, pas de clavier, pas de MSAA) :
  1. `EnumWindows` → « Programme d'installation NVIDIA » / « NVIDIA Installer » (`TitleIsNvcleanstall` exclut NVCleanstall)
  2. `EnumChildWindows` sur cette racine uniquement
  3. Garde page : UIA « Contrat de licence » / « License Agreement » / « NVIDIA Driver License Agreement »
  4. Bouton visible+activé : `FindLicenseAcceptButton` — « ACCEPTER ET CONTINUER », « Accepter et continuer », « Accept and Continue », « ACCEPTER », « Accept » (texte normalisé, pas de HWND hardcodé)
  5. `BM_CLICK` + `WM_COMMAND BN_CLICKED` parent (`GetDlgCtrlID`, lParam = HWND bouton)
  6. Attente 500 ms + vérif licence disparue ou page Options
- Appelée **en premier** dans `Invoke-NvidiaInstallerWizardTick` (avant Options / personnalisées / installation).
- Tick HTA dès fenêtre NVIDIA détectée — **sans** attendre fermeture NVCleanstall.
- Échec : `[NVIDIA-INSTALLER] License accept hwnd not found, manual required` + `logs/nvidia-installer-license-win32-dump.txt` (enfants Win32 + section HIGHLIGHT)

### Logs attendus
```
[NVIDIA-INSTALLER] Tick running, window found: title=Programme d'installation NVIDIA
[NVIDIA-INSTALLER] License page detected
[SAFE-WIN32] Accept hwnd found: text='ACCEPTER ET CONTINUER' id=...
[SAFE-WIN32] BM_CLICK accept invoked
[SAFE-WIN32] WM_COMMAND BN_CLICKED accept sent
[NVIDIA-INSTALLER] License accepted, waiting for Options page
```

### Flux wizard NVIDIA (ordre strict, une étape par tick)
1. Licence → `Invoke-NvidiaInstallerLicenseViaWin32Handles`
2. Options d'installation → `Invoke-NvidiaInstallerOptionsViaWin32Handles`
3. Options personnalisées → `SafeInvokeElement` Suivant, repli Win32 HWND
4. Installation → attente
5. Fin → barre 100 % + « Installation NVIDIA terminée — validation finale manuelle si demandée. »

### NVCleanstall
**Non modifié.**

---

## Correction 2 — Installateur NVIDIA : Personnalisée (avancée) + Suivant

### Problème
Blocage sur la page « Options d’installation » : Express restait sélectionné. Les dumps montrent :
- UIA : « Personnalisée (avancée) » exposé en **ControlType.Pane**, sans InvokePattern, SelectionItemPattern, TogglePattern, LegacyIAccessiblePattern.
- MSAA : `AccessibleObjectFromWindow failed` sur cette fenêtre.
- Win32 : enfants valides avec texte `&Expresse (recommandée)`, `&Personnalisée (avancée)`, `&SUIVANT`.

### Solution retenue (Win32 HWND uniquement)
- **`Invoke-NvidiaInstallerOptionsViaWin32Handles`** — action **uniquement** via Win32 sur la fenêtre « Programme d'installation NVIDIA » :
  1. `EnumWindows` → HWND racine NVIDIA (jamais NVCleanstall)
  2. Garde page : UIA « Options d'installation » + enfants Win32 `&Expresse` / `&Personnalisée` / `&SUIVANT`
  3. `EnumChildWindows` → `customHwnd` / `nextHwnd` par `GetWindowText` (pas de HWND hardcodés)
  4. `BM_CLICK` sur `customHwnd` + `WM_COMMAND BN_CLICKED` parent (`GetDlgCtrlID`)
  5. Attente 400 ms
  6. `BM_CLICK` sur `nextHwnd` + `WM_COMMAND BN_CLICKED` parent
- **`Invoke-NvidiaInstallerSelectCustomAndNext`** délègue uniquement à cette fonction (plus de UIA SelectionItem, MSAA, clavier pour cette page).
- Helper : **`Scripts/NvidiaWin32Msaa-helper.cs`** (`FindNvidiaInstallerRootHwnd`, `FindChildByTextContains`, `InvokeControlClick`).

### Abandonné pour cette page
- UIA `SafeSelectRadio` / SelectionItem obligatoire
- MSAA / LegacyIAccessible
- Clavier : `PostMessage VK_DOWN`, `SendInput`, `SendKeys`

### Logs attendus (succès Win32)
```
[NVIDIA-INSTALLER] Options page detected
[SAFE-WIN32] NVIDIA options root hwnd found: ...
[SAFE-WIN32] Express hwnd found: text='&Expresse (recommandée)' id=...
[SAFE-WIN32] Custom hwnd found: text='&Personnalisée (avancée)' id=...
[SAFE-WIN32] Next hwnd found: text='&SUIVANT' id=...
[SAFE-WIN32] BM_CLICK custom invoked
[SAFE-WIN32] WM_COMMAND BN_CLICKED custom sent
[SAFE-WIN32] BM_CLICK next invoked
[SAFE-WIN32] WM_COMMAND BN_CLICKED next sent
```

### Échec
- `[NVIDIA-INSTALLER] Win32 custom/next hwnd not found, manual required`
- Dump : `logs/nvidia-installer-options-win32-dump.txt`

### NVCleanstall
**Non modifié** — logique page 1 / Next / install NVCleanstall inchangée.

### Confirmation anti-GPS
- Aucun clic coordonnées écran, pourcentage, ou souris aveugle.
- Déclenchement des contrôles Windows réels par **HWND** (`BM_CLICK` / `WM_COMMAND`).

### Progression barre 100 % (installateur NVIDIA)
Quand détecté : page « Terminer », popup finale Oui/Yes (sans auto-clic), fin du processus installateur, ou état final NVCleanstall :
- `NV_PROGRESS_PCT=100`
- Message : « Installation NVIDIA terminée — validation finale manuelle si demandée. »
- Logs : `[NVIDIA-INSTALLER] Installation final state detected`, `[NVIDIA-INSTALLER] Progress forced to 100`, `[NVIDIA-INSTALLER] Manual final confirmation may be required`

### Confirmation anti-GPS
- Aucun clic coordonnées GPS, pourcentage écran, clavier (`SendKeys` / `SendInput` / `PostMessage VK_DOWN`), MSAA, ou souris aveugle sur les pages Licence et Options NVIDIA.
- Licence et Options : Win32 par HWND enfant uniquement (`BM_CLICK` + `WM_COMMAND BN_CLICKED`).

### Flux attendu
1. Licence → Accepter (inchangé)
2. Options d’installation → Personnalisée (avancée) → Suivant
3. Options personnalisées → Suivant (`SafeInvokeElement`)
4. Installation en cours → Terminer (validation manuelle Oui/Yes si demandée)

---

## Confirmation anti-GPS

- Aucun `SetCursorPos`, pourcentage écran, `Left+N` / `Top+N`, ou `Width*` / `Height*` ajouté pour cliquer.
- DDU : uniquement `SafeInvokeElement` sur bouton OK identifié.
- NVIDIA Options : `Invoke-NvidiaInstallerOptionsViaWin32Handles` (EnumWindows + BM_CLICK/WM_COMMAND par HWND) ; dump échec `logs/nvidia-installer-options-win32-dump.txt`.

---

## Tests manuels suggérés

### Installateur NVIDIA
1. Après NVCleanstall, laisser l’installateur s’ouvrir.
2. Sur « Options d’installation », vérifier live / logs :
   - `[NVIDIA-INSTALLER] Options page detected`
   - `[NVIDIA-INSTALLER] Custom radio confirmed selected` ou `Custom selected via MSAA` / `Custom selected via Win32`
   - `[SAFE-UIA] Invoked button Suivant`
3. Page suivante « Options personnalisées » → Suivant automatique.
4. À la fin : barre à **100 %**, message validation finale manuelle.

### Échec (dump)
- Live NVIDIA : `[UIA-DUMP]` lignes descendants boutons/radios si Personnalisée ou Suivant introuvable.
- Fichier : `logs/nvidia-installer-options-page-uia-dump.txt`
