import fs from "fs";
import path from "path";

const projectRoot = process.argv[2] || path.resolve(path.dirname(import.meta.url), "../..");
const quarantineRoot = path.join(projectRoot, "_cleanup_quarantine");
const auditPath = path.join(projectRoot, "CLEANUP_AUDIT.md");
const labelsPath = path.join(projectRoot, "src", "constants", "labels.js");

function fixMojibake(s) {
  if (!s) return s;
  const buf = Buffer.from(s, "latin1");
  return buf.toString("utf8");
}

function repairText(text) {
  let t = text;
  if (/Ã|â€|Â«|Â»|Â°/.test(t)) t = fixMojibake(t);
  if (/Ã|â€|Â«|Â»|Â°/.test(t)) t = fixMojibake(t);
  t = t.replace(/\uFFFD\u2019/g, "\u2192");
  t = t.replace(/\uFFFD'/g, "\u2192");
  return t;
}

function needsRepair(t) {
  return /Ã|â€|Â«|Â»|Â°|\uFFFD/.test(t);
}

function walk(dir, out = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (/node_modules|_cleanup_quarantine|\.git$/.test(ent.name)) continue;
      walk(p, out);
    } else out.push(p);
  }
  return out;
}

function ensureDir(d) {
  fs.mkdirSync(d, { recursive: true });
}

function moveToQuarantine(src, reason, risk, moved) {
  if (!fs.existsSync(src)) return;
  const rel = path.relative(projectRoot, src);
  const dest = path.join(quarantineRoot, rel);
  ensureDir(path.dirname(dest));
  let finalDest = dest;
  if (fs.existsSync(finalDest)) {
    finalDest = path.join(
      path.dirname(dest),
      `dup_${Date.now()}_${path.basename(dest)}`
    );
  }
  fs.renameSync(src, finalDest);
  moved.push({
    original: rel.replace(/\\/g, "/"),
    destination: `_cleanup_quarantine/${path.relative(quarantineRoot, finalDest).replace(/\\/g, "/")}`,
    reason,
    risk,
  });
}

const allFiles = walk(projectRoot);
const moved = [];
const kept = [];
const suspects = [];
const encodingFixes = [];

ensureDir(quarantineRoot);

const runtimeJsonKeep = new Set([
  "controller-devices-final.json",
  "controller-devices-present.json",
  "controller-device-signature.json",
  "controller-devices-cache.json",
  "controller-hidusbf-status-all.json",
  "controller-overclocker-status.json",
  "controller-overclocker-detect.json",
  "controller-overclocker-params.json",
  "controller-overclocker-apply-result.json",
  "controller-oc-result.json",
  "controller-overclocker-exitcode.txt",
]);

const logsDir = path.join(projectRoot, "logs");
const qRe =
  /(dump|before|after|diff|uia|debug|trace|test|radio-dump|live\.txt|\.reg$|_diag|_fixline|_fetch|_composite|_resolve|_usb-parent|oc-backups|hidusbf-probe|hidusbf-registry-diff|hidusbf-setup-.*-dump|nvcleaninstall-auto-live|ddu-auto-clean-live|safepoint-coordinate)/i;

if (fs.existsSync(logsDir)) {
  for (const f of walk(logsDir)) {
    const name = path.basename(f);
    const rel = path.relative(projectRoot, f).replace(/\\/g, "/");
    const parent = path.dirname(f);
    if (runtimeJsonKeep.has(name) && parent === logsDir) {
      kept.push({ file: rel, reason: "JSON etat runtime" });
      continue;
    }
    if (name === "controller-overclocker.log" && parent === logsDir) {
      kept.push({ file: rel, reason: "Journal runtime recreatable" });
      continue;
    }
    if (qRe.test(name) || rel.includes("logs/controller-oc-backups")) {
      moveToQuarantine(f, "Log/debug/dump/backup obsolete", "Faible", moved);
      continue;
    }
    if (/\.log$/i.test(name) && parent === logsDir) {
      const st = fs.statSync(f);
      if (st.size > 2 * 1024 * 1024 && name !== "controller-overclocker.log") {
        moveToQuarantine(f, "Ancien log volumineux (>2 Mo)", "Faible", moved);
      }
    }
    if (parent === logsDir && /^_.*\.ps1$/i.test(name)) {
      moveToQuarantine(f, "Script diagnostic temporaire", "Faible", moved);
    }
  }
}

const backupDir = path.join(projectRoot, "backup");
if (fs.existsSync(backupDir)) {
  for (const f of walk(backupDir)) moveToQuarantine(f, "Backup manuel archive", "Faible", moved);
}

const nvBroken = path.join(projectRoot, "Scripts", "NVIDIA-PS1-BROKEN-BACKUP");
if (fs.existsSync(nvBroken)) {
  for (const f of walk(nvBroken)) moveToQuarantine(f, "Scripts NVIDIA backup casses", "Faible", moved);
}

const strayEq = path.join(projectRoot, "=");
if (fs.existsSync(strayEq)) moveToQuarantine(strayEq, "Fichier parasite racine", "Faible", moved);

for (const rel of [
  "Scripts/Devices/Detect-USBControllers-Fast.ps1",
  "Scripts/Devices/Detect-Controllers-HidusbfLink.ps1",
  "Scripts/Devices/Sync-ControllerDevices.ps1",
  "Scripts/Devices/Merge-ControllerDevices.ps1",
  "Scripts/Devices/Get-ControllerPresentDevices.ps1",
]) {
  if (fs.existsSync(path.join(projectRoot, rel))) {
    suspects.push({
      file: rel,
      whySuspect: "Reference HTA legacy; flux principal = Detect-USBControllers.ps1",
      whyNotMoved: "Chemin encore dans Unreal.hta",
    });
  }
}

const textExt = new Set([
  ".hta", ".ps1", ".js", ".json", ".md", ".html", ".css", ".scss", ".bat", ".cmd", ".xml",
]);

for (const f of allFiles) {
  const ext = path.extname(f).toLowerCase();
  if (!textExt.has(ext)) continue;
  if (/_cleanup_quarantine|node_modules|nvidia-automation-v2[\\/].*[\\/](bin|obj)[\\/]/.test(f)) continue;
  let before;
  try {
    before = fs.readFileSync(f, "utf8");
  } catch {
    continue;
  }
  if (!needsRepair(before)) continue;
  const after = repairText(before);
  if (after === before) continue;
  if (ext === ".ps1") fs.writeFileSync(f, "\uFEFF" + after.replace(/^\uFEFF/, ""), "utf8");
  else fs.writeFileSync(f, after, "utf8");
  encodingFixes.push({
    file: path.relative(projectRoot, f).replace(/\\/g, "/"),
    note: "Mojibake repare UTF-8",
  });
}

ensureDir(path.dirname(labelsPath));
const labelsJs = `/**
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
`;
fs.writeFileSync(labelsPath, labelsJs, "utf8");
encodingFixes.push({ file: "src/constants/labels.js", note: "Cree centralisation labels" });

const tests = [];
const htaPath = path.join(projectRoot, "Unreal.hta");
if (fs.existsSync(htaPath)) {
  const hta = fs.readFileSync(htaPath, "utf8");
  tests.push(`Mojibake Ã absent: ${/Ã/.test(hta) ? "ECHEC" : "OK"}`);
  tests.push(`Detect-USBControllers.ps1: ${/Detect-USBControllers\.ps1/.test(hta) ? "OK" : "ECHEC"}`);
  tests.push(`Apply-ControllerOC.ps1: ${/Apply-ControllerOC\.ps1/.test(hta) ? "OK" : "ECHEC"}`);
  tests.push(`runControllerDetect: ${/function runControllerDetect/.test(hta) ? "OK" : "ECHEC"}`);
  tests.push(`Label Réseau: ${/Réseau/.test(hta) ? "OK" : "ECHEC"}`);
  tests.push(`Label Système: ${/Système/.test(hta) ? "OK" : "ECHEC"}`);
  tests.push(`Label Périphériques: ${/Périphériques|Périphérique/.test(hta) ? "OK" : "ECHEC"}`);
}

let md = `# Audit nettoyage projet Unreal / PurpleBoost

## Résumé
- Nombre total de fichiers scannés : ${allFiles.length}
- Nombre de fichiers déplacés en quarantaine : ${moved.length}
- Nombre de fichiers conservés (logs runtime) : ${kept.length}
- Nombre de fichiers suspects : ${suspects.length}
- Nombre de corrections d'encodage : ${encodingFixes.length}
- Date : ${new Date().toISOString().slice(0, 19).replace("T", " ")}

## Fichiers déplacés en quarantaine
| Fichier original | Destination quarantaine | Raison | Risque |
|---|---|---|---|
`;
for (const m of moved) {
  md += `| ${m.original} | ${m.destination} | ${m.reason} | ${m.risk} |\n`;
}
if (!moved.length) md += `| (aucun) | — | — | — |\n`;

md += `\n## Fichiers conservés volontairement\n| Fichier | Raison |\n|---|---|\n`;
for (const k of kept) md += `| ${k.file} | ${k.reason} |\n`;
md += `| Unreal.hta | Application principale |\n| Scripts/Devices/Apply-ControllerOC.ps1 | Apply Hz — ne pas toucher |\n| Scripts/Devices/Detect-USBControllers.ps1 | Détection PnP active |\n`;

md += `\n## Fichiers suspects non touchés\n| Fichier | Pourquoi suspect | Pourquoi non déplacé |\n|---|---|---|\n`;
for (const s of suspects) {
  md += `| ${s.file} | ${s.whySuspect} | ${s.whyNotMoved} |\n`;
}

md += `\n## Corrections encodage / textes\n| Fichier | Texte cassé | Texte corrigé |\n|---|---|---|\n`;
for (const e of encodingFixes) {
  md += `| ${e.file} | Mojibake (Ã©, rÃ©seau, systÃ¨me, etc.) | UTF-8 français correct (${e.note}) |\n`;
}

md += `\n## Tests après nettoyage\n`;
for (const t of tests) md += `- ${t}\n`;
md += `\n## Restauration depuis quarantaine\n\`\`\`powershell\nMove-Item -LiteralPath "_cleanup_quarantine\\<chemin>" -Destination "<original>" -Force\n\`\`\`\n\n_Quarantaine : _cleanup_quarantine/ — aucune suppression définitive._\n`;

fs.writeFileSync(auditPath, md, "utf8");
console.log(`Done: scanned=${allFiles.length} moved=${moved.length} encoding=${encodingFixes.length}`);
