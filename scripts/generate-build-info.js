/**
 * Génère build-info.json (version, date build, commit git).
 * Appelé en postinstall / prebuild.
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const root = path.join(__dirname, '..');
const pkgPath = path.join(root, 'package.json');
const outPath = path.join(root, 'src', 'build-info.json');

function gitShort() {
  try {
    return execSync('git rev-parse --short HEAD', {
      cwd: root,
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

const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
const builtAt = formatBuildDate(new Date());
const commit = gitShort();

const info = {
  version: pkg.version || '0.0.0',
  productName: pkg.productName || pkg.name,
  builtAt,
  commit,
  buildId: `${pkg.version}-${builtAt.replace(/[:\s]/g, '')}-${commit}`
};

fs.writeFileSync(outPath, JSON.stringify(info, null, 2), 'utf8');
console.log(`build-info.json → v${info.version} · ${info.builtAt} · ${info.commit}`);
