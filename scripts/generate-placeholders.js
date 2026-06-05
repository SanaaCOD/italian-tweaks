/**
 * Generates replaceable placeholder assets (logo, background, icon).
 * Run: node scripts/generate-placeholders.js
 */
const fs = require('fs');
const path = require('path');

const assetsDir = path.join(__dirname, '..', 'assets');
fs.mkdirSync(assetsDir, { recursive: true });

function writePng(filePath, r, g, b, size = 256) {
  const width = size;
  const height = size;
  const raw = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      const vignette = 1 - Math.hypot(x - width / 2, y - height / 2) / (width * 0.72);
      raw[i] = Math.min(255, Math.floor(r * vignette));
      raw[i + 1] = Math.min(255, Math.floor(g * vignette));
      raw[i + 2] = Math.min(255, Math.floor(b * vignette));
      raw[i + 3] = 255;
    }
  }
  const png = encodePng(width, height, raw);
  fs.writeFileSync(filePath, png);
}

function crc32(buf) {
  let c = 0xffffffff;
  const table = crc32.table || (crc32.table = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c;
    }
    return t;
  })());
  for (let i = 0; i < buf.length; i++) c = table[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const t = Buffer.from(type);
  const crcBuf = Buffer.concat([t, data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(crcBuf));
  return Buffer.concat([len, t, data, crc]);
}

function encodePng(width, height, rgba) {
  const stride = width * 4;
  const filtered = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    const rowStart = y * (stride + 1);
    filtered[rowStart] = 0;
    rgba.copy(filtered, rowStart + 1, y * stride, y * stride + stride);
  }
  const zlib = require('zlib');
  const compressed = zlib.deflateSync(filtered);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', compressed),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

const { execSync } = require('child_process');
const logoSource = path.join(assetsDir, 'kojo-logo-source.png');
const logoOut = path.join(assetsDir, 'logo.png');

writeBackgroundLowPoly(path.join(assetsDir, 'background.png'), 1280, 720);

if (fs.existsSync(logoSource)) {
  execSync('node scripts/process-kojo-logo.js', { cwd: root, stdio: 'inherit' });
} else if (!fs.existsSync(logoOut)) {
  writeLogoPng(logoOut, 256);
  writePng(path.join(assetsDir, 'icon.png'), 255, 122, 24, 256);
} else {
  console.log('[placeholders] logo.png conservé (Kojo)');
}

function writeBackgroundLowPoly(filePath, width, height) {
  const raw = Buffer.alloc(width * height * 4);
  const shades = [
    [11, 11, 13],
    [12, 12, 15],
    [13, 13, 16],
    [14, 14, 18],
    [15, 15, 19],
    [16, 16, 21]
  ];
  const hash = (i, j) => ((i * 92837111) ^ (j * 689287499)) >>> 0;
  const cellW = 90;
  const cellH = cellW * 0.866;

  const fillTri = (p1, p2, p3, col, row) => {
    const s = shades[hash(col, row) % shades.length];
    const minX = Math.max(0, Math.floor(Math.min(p1.x, p2.x, p3.x)));
    const maxX = Math.min(width - 1, Math.ceil(Math.max(p1.x, p2.x, p3.x)));
    const minY = Math.max(0, Math.floor(Math.min(p1.y, p2.y, p3.y)));
    const maxY = Math.min(height - 1, Math.ceil(Math.max(p1.y, p2.y, p3.y)));
    for (let y = minY; y <= maxY; y++) {
      for (let x = minX; x <= maxX; x++) {
        if (pointInTri(x + 0.5, y + 0.5, p1, p2, p3)) {
          const i = (y * width + x) * 4;
          raw[i] = s[0];
          raw[i + 1] = s[1];
          raw[i + 2] = s[2];
          raw[i + 3] = 255;
        }
      }
    }
  };

  const pointAt = (col, row) => {
    const offsetX = row % 2 ? cellW * 0.5 : 0;
    const hx = hash(col, row);
    const jx = ((hx % 1000) / 1000 - 0.5) * 4;
    const jy = (((hx >> 10) % 1000) / 1000 - 0.5) * 4;
    return { x: col * cellW + offsetX + jx, y: row * cellH + jy };
  };

  const cols = Math.ceil(width / cellW) + 2;
  const rows = Math.ceil(height / cellH) + 2;
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const a = pointAt(col, row);
      const b = pointAt(col + 1, row);
      const c = pointAt(col, row + 1);
      const d = pointAt(col + 1, row + 1);
      if (hash(col, row) % 2 === 0) {
        fillTri(a, b, c, col, row);
        fillTri(b, d, c, col + 1, row);
      } else {
        fillTri(a, b, d, col, row);
        fillTri(a, d, c, col, row + 1);
      }
    }
  }

  fs.writeFileSync(filePath, encodePng(width, height, raw));
}

function pointInTri(px, py, p1, p2, p3) {
  const sign = (ax, ay, bx, by, cx, cy) => (ax - cx) * (by - cy) - (bx - cx) * (ay - cy);
  const d1 = sign(px, py, p1.x, p1.y, p2.x, p2.y);
  const d2 = sign(px, py, p2.x, p2.y, p3.x, p3.y);
  const d3 = sign(px, py, p3.x, p3.y, p1.x, p1.y);
  const hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
  const hasPos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(hasNeg && hasPos);
}

function writeLogoPng(filePath, size) {
  const raw = Buffer.alloc(size * size * 4);
  const cx = size / 2;
  const cy = size / 2;
  const radius = size * 0.42;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const i = (y * size + x) * 4;
      const d = Math.hypot(x - cx, y - cy);
      if (d > radius) {
        raw[i + 3] = 0;
        continue;
      }
      const ring = d > radius - 3 && d <= radius;
      if (ring) {
        raw[i] = 0;
        raw[i + 1] = 212;
        raw[i + 2] = 238;
        raw[i + 3] = 180;
        continue;
      }
      const letterI = Math.abs(x - cx) < size * 0.06 && y > cy - size * 0.22 && y < cy + size * 0.22;
      if (letterI) {
        raw[i] = 0;
        raw[i + 1] = 212;
        raw[i + 2] = 238;
        raw[i + 3] = 255;
      } else {
        raw[i] = 14;
        raw[i + 1] = 14;
        raw[i + 2] = 20;
        raw[i + 3] = 255;
      }
    }
  }
  fs.writeFileSync(filePath, encodePng(size, size, raw));
}

const icoHeader = Buffer.from([
  0, 0, 1, 0, 1, 0, 32, 32, 0, 0, 1, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0
]);
const iconPng = fs.readFileSync(path.join(assetsDir, 'icon.png'));
const ico = Buffer.concat([icoHeader, Buffer.alloc(4), iconPng]);
ico.writeUInt32LE(22, 14);
ico.writeUInt32LE(iconPng.length, 18);
fs.writeFileSync(path.join(assetsDir, 'icon.ico'), ico);

console.log('Placeholder assets written to assets/');
