const { app } = require('electron');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { getBundledContentRoot } = require('./paths');

let cached = null;

function readJsonFile(filePath) {
  try {
    if (fs.existsSync(filePath)) {
      return JSON.parse(fs.readFileSync(filePath, 'utf8'));
    }
  } catch {
    /* ignore */
  }
  return null;
}

function gitShortFromCwd(cwd) {
  try {
    return execSync('git rev-parse --short HEAD', {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore']
    }).trim();
  } catch {
    return 'local';
  }
}

function formatBuildDate(d) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function resolveBuildInfoPaths() {
  const roots = [];
  try {
    roots.push(getBundledContentRoot());
  } catch {
    /* ignore */
  }
  roots.push(path.join(__dirname, '..', '..'));
  roots.push(process.cwd());
  const files = [];
  for (const r of roots) {
    if (!r) continue;
    files.push(path.join(r, 'src', 'build-info.json'));
    files.push(path.join(r, 'build-info.json'));
  }
  return files;
}

function getBuildInfo() {
  if (cached) return cached;

  let fileInfo = null;
  for (const f of resolveBuildInfoPaths()) {
    fileInfo = readJsonFile(f);
    if (fileInfo) break;
  }

  let pkgVersion = '0.0.0';
  try {
    const pkgPath = path.join(__dirname, '..', '..', 'package.json');
    const pkg = readJsonFile(pkgPath);
    if (pkg?.version) pkgVersion = pkg.version;
  } catch {
    /* ignore */
  }

  const version = fileInfo?.version || pkgVersion;
  const builtAt = fileInfo?.builtAt || formatBuildDate(new Date());
  const commit = fileInfo?.commit || gitShortFromCwd(path.join(__dirname, '..', '..'));
  const packaged = app.isPackaged;
  const devMode = !packaged;

  const displayLine = `v${version} · build ${builtAt} · ${commit}`;

  cached = {
    ok: true,
    version,
    builtAt,
    commit,
    buildId: fileInfo?.buildId || `${version}-${builtAt}-${commit}`,
    displayLine,
    packaged,
    devMode,
    productName: fileInfo?.productName || 'ITALIAN TWEAKS'
  };

  return cached;
}

module.exports = { getBuildInfo };
