# Audit lancement Unreal / PurpleBoost

Date : 2026-05-25

## Entrypoint utilisé au clic sur « Unreal »

| Fichier | Rôle | Statut |
|---------|------|--------|
| **Unreal.hta** | Application principale (UI sombre, Controller Overclocker, Drivers, etc.) | **Entrypoint officiel** |
| PurpleBoost.hta | Ancien UI « PB » / logo violet — **redirige** vers Unreal.hta (sans UI) | Wrapper transparent |
| UnrealLauncher.exe | Lance `mshta.exe Unreal.hta` (mutex single instance) | Optionnel, pas de fenêtre propre |
| PurpleBoost.exe (WPF) | `App.xaml` → `ShellWindow.xaml` (ancien shell WPF) | **Non utilisé** pour le clic HTA habituel |
| package.json / Electron | Absent | — |

Quand l’utilisateur double-clique **Unreal.hta** (ou un raccourci vers ce fichier), MSHTA ouvre directement l’HTA principale.

## Cause de l’écran blanc / double fenêtre

1. **Relance administrateur au démarrage** (`ensureAppRunsAsAdminOnStartup`)  
   - Sans droits admin : MSHTA affichait d’abord une fenêtre (fond blanc natif IE), puis lançait une **deuxième** instance `mshta` en UAC, puis fermait la première — flash blanc + impression de double app.

2. **PurpleBoost.hta legacy**  
   - Ancienne interface avec logo « PB », barre Windows visible, `WINDOWSTATE="normal"` — si ouvert par erreur, l’utilisateur voyait l’ancien branding avant ou à la place d’Unreal.

3. **Peinture tardive**  
   - ~17 000 lignes de CSS/JS dans le `<head>` avant le `<body>` : la fenêtre MSHTA apparaît avant le fond `#05060a` / `#07070A`.

4. **Chrome natif MSHTA**  
   - `forceBorderlessHtaNativeChrome()` s’exécute après `onload` (délais 120 ms / 450 ms) : bordure blanche Windows visible brièvement.

## Fichiers legacy / suspects

| Fichier | Action |
|---------|--------|
| `_cleanup_quarantine/PurpleBoost.hta.legacy-ui` | Ancien PurpleBoost.hta complet (UI « PB ») — en quarantaine |
| `PurpleBoost.hta` (racine) | Remplacé par redirect invisible → Unreal.hta |
| `App.xaml` + `Views/ShellWindow.xaml` | WPF legacy — **non modifié** (hors flux HTA) |
| `UnrealLauncher/` | Conservé ; lancement mshta en fenêtre masquée |

## Corrections appliquées

### Unreal.hta
- CSS critique **immédiat** (`#07070A`, pas de blanc).
- **Gate de lancement** en tête de `<head>` : si non admin → fenêtre déplacée hors écran + relance UAC `mshta` en `-WindowStyle Hidden` + fermeture immédiate de l’instance non admin.
- **Boot screen** sombre minimal (logo Unreal + « UNREAL »), masqué dès que l’UI est prête (`html.unreal-ready`).
- `.app-shell` invisible jusqu’à `unreal-ready`.
- `ensureAppRunsAsAdminOnStartup` : ne relance plus si le gate a déjà traité l’élévation.
- Titre fenêtre / barre : **Unreal** (plus « UNREAL Gaming Optimizer » sur la titlebar).

### PurpleBoost.hta
- Redirect HTA minimisé (`SHOWINTASKBAR=no`, `WINDOWSTATE=minimize`) → ouvre Unreal.hta puis se ferme.

### UnrealLauncher/Program.cs
- Relance UAC : PowerShell en fenêtre masquée ; **mshta reste visible** une fois élevé (pas de `-WindowStyle Hidden` sur mshta, sinon l’UI ne s’affiche pas).

## Fichier responsable du lancement final

**Unreal.hta** — seule interface fonctionnelle complète.

## Tests à faire (manuel)

1. Fermer toutes les instances (Gestionnaire des tâches : `mshta.exe` liés à Unreal).
2. Double-clic **Unreal.hta** × 3.
3. Vérifier :
   - une seule fenêtre visible après acceptation UAC (si demandé) ;
   - fond sombre dès l’ouverture (pas d’écran blanc plein) ;
   - pas d’UI « PurpleBoost / PB » ;
   - pas d’ancien logo « U » seul ;
   - interface Unreal actuelle (sidebar néon, Controller Overclocker, etc.).

4. Test **PurpleBoost.hta** : doit ouvrir Unreal sans afficher l’ancienne UI.

5. Test **UnrealLauncher.exe** (si présent dans le dossier de build) : une seule fenêtre Unreal.

## Résultat attendu

| Critère | Attendu |
|---------|---------|
| Fenêtres visibles | 1 |
| Premier pixel | Sombre `#07070A` |
| Ancien launcher PB | Non visible |
| Fonctions métier | Inchangées (scripts PS, Hz, détection, etc.) |

## Restauration legacy (si besoin)

```powershell
Copy-Item -LiteralPath "_cleanup_quarantine\PurpleBoost.hta.legacy-ui" -Destination "PurpleBoost.hta" -Force
```
