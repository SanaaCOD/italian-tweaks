# Checkpoint — Rollback Diagnostic NVIDIA V3

Date : 2026-05-22

## État après rollback

- **Diagnostic V3 supprimé** : section HTA, boutons de test, fonctions JavaScript (`runNvidiaV3Direct`, etc.).
- **Profile Inspector ne s’ouvre plus depuis le diagnostic** : outil `tools/nvidia-v3-diagnostics/` retiré (y compris `PerformanceForensicService` qui lançait un export NPI).
- **PowerShell V3 supprimé** : plus de wrapper `nv-v3-*.ps1` ni lecture stdout V3 depuis l’HTA.
- **Onglet Drivers revenu à l’état stable** : DDU, NVCleanInstall, optimisation Nvidia complète (NIP silencieux), éclat 80 %, résolution/fréquence max, reset 3D, tests unitaires existants (G-Sync, téléciné registre via V2).

## Résumé bouton principal (inchangé)

Après « Appliquer optimisation Nvidia complète », le panneau affiche :

- Profil NVIDIA
- Éclat numérique
- Résolution max
- Fréquence max

## Conservé (non touché)

- DDU / NVCleanInstall
- Import `.nip` (Nvidia Profile Inspector **silencieux** dans le flux gaming)
- `NvidiaAutomationV2.exe`
- Logs utiles existants (`nvidia-gaming.log`, `nvidia-profile.log`, etc.)

## Fichiers / dossiers retirés

- `tools/nvidia-v3-diagnostics/` (projet `NvidiaV3Diagnostics.exe`)
- `tools/nvidia-v3-diagnostics-native/`

Les logs V3 déjà présents sous `logs/` (ex. `nvidia-v3-result.json`) ne sont pas effacés automatiquement ; ils ne sont plus produits ni lus par l’interface.

## Suite (2026-05-22)

- Section **Réglages NVIDIA supplémentaires** ajoutée (3 boutons, mécanique V2 + DisplayHelper).
- Rapport patterns : `logs/working-button-patterns.txt`.

## Prochaine étape

Quand les 3 boutons séparés sont validés, les intégrer au bouton « Appliquer optimisation Nvidia complète ».

Implémenter les **3 réglages restants un par un**, sans diagnostic global :

1. Téléciné inversée OFF (registre, preuve relecture)
2. Pas de mise à l’échelle (méthode fiable, une preuve à la fois)
3. Mode performance (sans usine à gaz ni ouverture NPI pour « diagnostic »)

Ne pas réintroduire : panneau UIA, diagnostic V3 global, faux « appliqué » sans relecture.
