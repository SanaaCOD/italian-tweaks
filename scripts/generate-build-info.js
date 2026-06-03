const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const root = path.resolve(__dirname, '..');
const srcDir = path.join(root, 'src');
const packagePath = path.join(root, 'package.json');
const outPath = path.join(srcDir, 'build-info.json');

function readJsonSafe(filePath, fallback) {
  try {
    let raw = fs.readFileSync(filePath, 'utf8');
    raw = raw.replace(/^\uFEFF/, '').trim();
    const firstBrace = raw.indexOf('{');
    if (firstBrace > 0) raw = raw.slice(firstBrace);
    return JSON.parse(raw);
  } catch (err) {
    console.warn('[build-info] JSON parse failed:', filePath, err.message);
    return fallback;
  }
}

function execSafe(command, fallback) {
  try {
    const out = cp.execSync(command, {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore']
    }).trim();
    return out || fallback;
  } catch (_) {
    return fallback;
  }
}

function pad(n) {
  return String(n).padStart(2, '0');
}

const pkg = readJsonSafe(packagePath, { version: '0.0.0' });
const version = pkg.version || '0.0.0';

const now = new Date();
const buildDate =
  now.getFullYear() + '-' +
  pad(now.getMonth() + 1) + '-' +
  pad(now.getDate()) + ' ' +
  pad(now.getHours()) + ':' +
  pad(now.getMinutes());

const commit = execSafe('git rev-parse --short HEAD', 'local');

const info = {
  version,
  buildDate,
  buildTime: buildDate,
  commit,
  git: commit,
  buildId: 'v' + version + ' Â· build ' + buildDate + ' Â· ' + commit,
  generatedAt: now.toISOString()
};

fs.mkdirSync(srcDir, { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(info, null, 2) + '\n', 'utf8');
console.log('build-info.json -> v' + version + ' Â· ' + buildDate + ' Â· ' + commit);
