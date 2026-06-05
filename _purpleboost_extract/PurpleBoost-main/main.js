/**
 * Shell Electron — lance Unreal.hta via MSHTA (moteur réel de l'app : ActiveX, WMI, PowerShell).
 * L'interface ne tourne pas dans Chromium : Electron sert d'emballage .exe et de lanceur desktop.
 */
const { app, Menu } = require("electron");
const path = require("path");
const fs = require("fs");
const { spawn } = require("child_process");

const APP_MUTEX_HINT = "unreal-electron-launcher-v1";
let htaChild = null;
let isQuitting = false;

function resolveAppRoot() {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, "app");
  }
  return __dirname;
}

function resolveHtaEntry(appRoot) {
  const hta = path.join(appRoot, "Unreal.hta");
  if (fs.existsSync(hta)) return hta;
  console.warn(
    "[Unreal] Unreal.hta introuvable dans",
    appRoot,
    "— unreal.html seul ne suffit pas (ActiveX / MSHTA requis)."
  );
  return hta;
}

function resolveMshtaPath() {
  const sysRoot = process.env.SystemRoot || process.env.windir || "C:\\Windows";
  const mshta = path.join(sysRoot, "System32", "mshta.exe");
  if (fs.existsSync(mshta)) return mshta;
  return "mshta.exe";
}

function launchUnrealHta() {
  const appRoot = resolveAppRoot();
  const htaPath = resolveHtaEntry(appRoot);

  if (!fs.existsSync(htaPath)) {
    console.error("[Unreal] Fichier introuvable :", htaPath);
    app.exit(2);
    return;
  }

  process.env.UNREAL_APP_BASE = appRoot;

  const mshta = resolveMshtaPath();

  htaChild = spawn(mshta, [htaPath, "--base-dir", appRoot], {
    cwd: appRoot,
    detached: true,
    stdio: "ignore",
    windowsHide: false,
    env: {
      ...process.env,
      UNREAL_APP_BASE: appRoot,
      UNREAL_ELECTRON_LAUNCH: APP_MUTEX_HINT,
    },
  });

  htaChild.unref();

  htaChild.on("error", (err) => {
    console.error("[Unreal] Impossible de lancer mshta.exe :", err);
    app.exit(3);
  });

  htaChild.on("exit", () => {
    htaChild = null;
    if (!isQuitting) {
      app.quit();
    }
  });
}

const gotSingleInstanceLock = app.requestSingleInstanceLock();
if (!gotSingleInstanceLock) {
  app.quit();
} else {
  app.on("second-instance", () => {
    /* L'HTA Unreal.hta utilise déjà SINGLEINSTANCE=yes */
  });

  app.disableHardwareAcceleration();

  app.whenReady().then(() => {
    Menu.setApplicationMenu(null);
    launchUnrealHta();
  });

  app.on("before-quit", () => {
    isQuitting = true;
  });
}
