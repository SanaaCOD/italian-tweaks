/**
 * Labels UI principaux (PurpleBoost / Unreal.hta).
 */
(function (root) {
  var LABELS = {
    nav: { home: "Accueil", devices: "Périphériques", drivers: "Drivers", connection: "Connexion", game: "Jeu", optimization: "Optimisation", sound: "Son", network: "Réseau", system: "Système" },
    hardware: { processor: "Processeur", gpu: "Carte graphique", memory: "Mémoire" },
    status: { optimized: "Optimisé", notOptimized: "Non optimisé", detected: "Détecté", notDetected: "Non détecté", verification: "Vérification" },
    actions: { restore: "Restaurer", boost: "Booster", removeBoost: "Retirer le boost" }
  };
  if (typeof module !== "undefined" && module.exports) { module.exports = LABELS; }
  else { root.UNREAL_LABELS = LABELS; }
})(typeof window !== "undefined" ? window : this);
