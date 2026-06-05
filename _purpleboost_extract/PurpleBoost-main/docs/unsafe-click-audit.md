# Audit sécurité — clics souris / coordonnées (Unreal / PurpleBoost)

**Date :** 2026-05-20  
**Objectif :** supprimer tout clic « GPS écran » (coordonnées fixes, pourcentage écran, taille écran, fallback aveugle) tout en conservant la logique métier DDU / NVCleanstall / panneau NVIDIA.

---

## Fichiers scannés

| Zone | Fichiers |
|------|----------|
| Scripts PowerShell | `Scripts/*.ps1` (dont `ddu-auto-clean-uia.ps1`, `nvcleaninstall-auto-uia.ps1`, `Safe-UiaClick.ps1`, `apply-nvidia-display-profile.ps1`, …) |
| Scripts AutoHotkey | `Scripts/*.ahk` (dont `nvcleaninstall-auto.ahk`, `nvcleaninstall-tweaks-only.ahk`, `ddu-auto-clean.ahk`, `ddu-final-quit-watcher.ahk`) |
| UI principale | `Unreal.hta` |
| Panneau NVIDIA | `tools/nvidia-panel-clicker/NvidiaPanelClicker/**/*.cs` |
| Outils affichage / automation v2 | `tools/nvidia-display-helper/**`, `tools/nvidia-automation-v2/**` (aucun clic souris HID détecté) |
| Archives / sauvegardes | `backup-*`, `*.bak*` — **non modifiés** (hors périmètre actif) |

**Motifs recherchés :** `SetCursorPos`, `mouse_event`, `SendInput` souris, `Click(x,y)`, `%` client/fenêtre, `Screen.PrimaryScreen`, `WorkingArea`, `GetSystemMetrics`, offsets `Left+N` / `Top+N`, `ClickFromEdges`, `Invoke-ClickClientRelative`.

---

## Occurrences dangereuses trouvées (avant correction)

| ID | Fichier | Description | Classification initiale |
|----|---------|-------------|-------------------------|
| D1 | `ddu-auto-clean-uia.ps1` | `Invoke-DduScreenClick` + fallback `Left+135` / `Top+154` | DANGEREUX |
| D2 | `nvcleaninstall-auto-uia.ps1` | `Invoke-ClickClientRelative` (ex. EAC `0.09/0.76`) | DANGEREUX |
| D3 | `nvcleaninstall-auto-uia.ps1` | `ClickFromEdges(85,28)` | DANGEREUX |
| D4 | `nvcleaninstall-auto-uia.ps1` | Focus Finished `%` client / écran | DANGEREUX |
| D5 | `nvcleaninstall-auto.ahk` | `Click(x-18)`, scroll `%`, EAC `%`, install `%`, focus écran | DANGEREUX |
| D6 | `nvcleaninstall-tweaks-only.ahk` | `Click(x-18)`, scroll `%` client | DANGEREUX |
| D7 | `tools/.../PreviewPerformanceUia.cs` | Clic slider à `Width * 0.06` | DANGEREUX (offset relatif au rect, pas centre UIA) |
| D8 | `tools/.../PanelClickerService.cs` | Clic radio à `Width * 0.05` | DANGEREUX (idem) |

---

## Neutralisation effectuée

### Module commun `Scripts/Safe-UiaClick.ps1` (nouveau)

- `SafeInvokeElement`, `SafeSelectRadio`, `SafeToggleCheckbox`, `SafeClickElementCenter`
- `Write-BlockedUnsafeClick` → log `[BLOCKED-UNSAFE-CLICK]`
- `Write-UiaDumpForElement` → log `[UIA-DUMP]`
- Seul chemin souris autorisé côté PS1 : centre du `BoundingRectangle` d’un élément UIA identifié (`[SAFE-UIA-RECT]`)

### DDU — `ddu-auto-clean-uia.ps1`

- Dot-source `Safe-UiaClick.ps1`
- `Invoke-DduScreenClick` : **toujours bloqué** (`[BLOCKED-UNSAFE-CLICK]`, retour `$false`)
- Fallback offset fixe Nettoyer : **supprimé** → message manuel + log si UIA échoue

### NVCleanstall — `nvcleaninstall-auto-uia.ps1`

- Dot-source `Safe-UiaClick.ps1` ; clics délégués aux helpers Safe
- `Invoke-ClickClientRelative` : stub bloquant uniquement
- `ClickFromEdges` / install-only `%` : stubs bloquants
- EAC : ordre des toggles UIA ; si échec → `[UIA-DUMP]` + `manual_required` (plus de fallback `%`)

### NVCleanstall — `nvcleaninstall-auto.ahk` / `nvcleaninstall-tweaks-only.ahk`

- `SafeClickBlockCoordinateFallbacks := true` (global)
- Tous les `Click()` coordonnées supprimés ; **ControlClick** / **ControlFocus** / molette conservés
- Chemins EAC / install / focus `%` : retour anticipé + log sécurité

### Panneau NVIDIA — `tools/nvidia-panel-clicker/`

- `AutomationHelper`, `TelecineCheckboxUia`, `PanelClickerService`, `PreviewPerformanceUia` : clics souris uniquement au **centre** du `BoundingRectangle` UIA ; logs `[SAFE-UIA]` / `[SAFE-UIA-RECT]`
- `Win32Helper.ClickScreenPoint` : infrastructure bas niveau (appelée uniquement après identification UIA)

---

## Ce qui reste acceptable (actif)

| Zone | Mécanisme | Raison |
|------|-----------|--------|
| `Safe-UiaClick.ps1` | `InvokePattern` / `SelectionItemPattern` / `TogglePattern` puis centre rect | Règle obligatoire du projet |
| `nvcleaninstall-auto-uia.ps1` | Toggles / Invoke / radios par UIA | Logique métier inchangée, sans coords écran |
| `nvcleaninstall-auto.ahk` | `ControlClick`, `ControlFocus`, `{WheelDown}` | Pas de coordonnées écran |
| `ddu-auto-clean.ahk`, `ddu-final-quit-watcher.ahk` | `ControlClick` sur boutons nommés | OK |
| `PanelClickerService.FindNoScalingRadioByAliases` | `wr.Width * 0.22` pour **filtrer** les radios (pas pour cliquer) | Disambiguation UIA |
| `nvcleaninstall-auto-uia.ps1` | `lr.Height * 0.75` tolérance alignement texte/radio | Géométrie UIA, pas clic |
| Installateur NVIDIA (boucle HTA) | Tick UIA `Invoke-NvidiaInstallerWizardTick` | Déjà migré (session précédente) |

---

## Logs de sécurité

| Préfixe | Signification |
|---------|----------------|
| `[SAFE-UIA]` | Action via Invoke / SelectionItem / Toggle |
| `[SAFE-UIA-RECT]` | Clic centre d’un élément UIA identifié (Name, AutomationId, ControlType, rect, enabled) |
| `[BLOCKED-UNSAFE-CLICK]` | Tentative de clic coordonnées / pourcentage / offset bloquée |
| `[UIA-DUMP]` | Élément introuvable — énumération contrôles pour action manuelle |

---

## Vérification finale (grep actif, hors backups)

- Aucun `Click(` dans `Scripts/*.ahk`
- `Invoke-DduScreenClick` : définition seule, **aucun appel actif**
- `Invoke-ClickClientRelative` : retourne toujours `$false` ; appel EAC remplacé par dump + manuel
- `SetCursorPos` / `mouse_event` actifs uniquement dans `Safe-UiaClick.ps1` et `Win32Helper.cs` (après identification UIA)

---

## Confirmation finale

**Aucun clic souris basé sur coordonnées fixes, taille écran ou pourcentage écran ne reste actif.**

Les seuls clics souris restants déplacent le curseur vers le **centre du `BoundingRectangle`** d’un contrôle UIA préalablement trouvé (Name / alias / ControlType), ou utilisent les patterns UIA (`Invoke`, `SelectionItem`, `Toggle`). En cas d’échec UIA, l’application journalise et demande une action manuelle — **sans fallback coordonnées**.
