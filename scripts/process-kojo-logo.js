/**
 * Logo Kojo — PNG transparent premium :
 * - supprime damier / fond / halo blanc-gris
 * - conserve texte noir + glow orange
 * - netteté légère sur l’encre
 */
const fs = require('fs');
const path = require('path');
const { PNG } = require('pngjs');
const jpeg = require('jpeg-js');

const root = path.join(__dirname, '..');
const defaultSrc = path.join(root, 'assets', 'kojo-logo-source.png');

function chroma(r, g, b) {
  return Math.max(r, g, b) - Math.min(r, g, b);
}

function luminance(r, g, b) {
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

function isOrangeGlow(r, g, b) {
  const c = chroma(r, g, b);
  const lum = luminance(r, g, b);
  if (lum < 42 || c < 18) return false;
  if (r < g + 14) return false;
  if (r < 58) return false;
  if (g > r - 6 && b > r - 10 && lum > 175) return false;
  return r > g + 12 && g >= b - 18 && c >= 20;
}

function isBlackInk(r, g, b) {
  const lum = luminance(r, g, b);
  const c = chroma(r, g, b);
  return lum < 92 && c < 55;
}

function isBackground(r, g, b) {
  const c = chroma(r, g, b);
  const lum = luminance(r, g, b);
  if (isBlackInk(r, g, b) || isOrangeGlow(r, g, b)) return false;
  if (c < 44 && lum > 112) return true;
  if (lum > 242 && c < 30) return true;
  return false;
}

function isWhiteFringe(r, g, b) {
  const c = chroma(r, g, b);
  const lum = luminance(r, g, b);
  if (isBlackInk(r, g, b) || isOrangeGlow(r, g, b)) return false;
  if (c < 36 && lum > 138) return true;
  if (c < 28 && lum > 118 && r > 105 && g > 100 && b > 95) return true;
  return false;
}

function computeAlpha(r, g, b) {
  if (isBackground(r, g, b) || isWhiteFringe(r, g, b)) return 0;
  if (isBlackInk(r, g, b)) return 255;

  if (isOrangeGlow(r, g, b)) {
    const warmth = Math.min(255, (r - g) * 2.1 + (r - 55) * 0.65);
    const lum = luminance(r, g, b);
    const edge = lum > 165 ? Math.max(0, 1 - (lum - 165) / 70) : 1;
    return Math.round(Math.min(235, Math.max(48, warmth * edge)));
  }

  const c = chroma(r, g, b);
  const lum = luminance(r, g, b);
  if (c < 38 && lum > 95) return 0;
  if (r > g + 8 && r > 50) {
    return Math.round(Math.min(160, (r - g) * 1.8));
  }
  return 0;
}

function cleanRgb(r, g, b, a) {
  if (a === 0) return [0, 0, 0];

  if (isBlackInk(r, g, b) || luminance(r, g, b) < 95) {
    const k = Math.min(1, 72 / Math.max(1, luminance(r, g, b)));
    return [
      Math.round(Math.min(42, r * k)),
      Math.round(Math.min(42, g * k)),
      Math.round(Math.min(42, b * k))
    ];
  }

  if (isOrangeGlow(r, g, b)) {
    let nr = r;
    let ng = Math.min(g, r * 0.72);
    let nb = Math.min(b, r * 0.38);
    const lum = luminance(nr, ng, nb);
    if (lum > 200) {
      const damp = 200 / lum;
      nr = Math.round(nr * damp);
      ng = Math.round(ng * damp);
      nb = Math.round(nb * damp);
    }
    return [nr, ng, nb];
  }

  return [r, g, b];
}

function sharpenPass(data, width, height, alphaBuf, amount = 0.38) {
  const copy = Buffer.from(data);
  const w = width;
  const h = height;

  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      const i = (w * y + x) * 4;
      if (alphaBuf[i >> 2] < 200) continue;
      if (luminance(copy[i], copy[i + 1], copy[i + 2]) > 100) continue;

      let sr = 0;
      let sg = 0;
      let sb = 0;
      const taps = [
        [-1, -1], [0, -1], [1, -1],
        [-1, 0], [1, 0],
        [-1, 1], [0, 1], [1, 1]
      ];
      for (const [dx, dy] of taps) {
        const j = (w * (y + dy) + (x + dx)) * 4;
        sr += copy[j];
        sg += copy[j + 1];
        sb += copy[j + 2];
      }
      const center = i;
      const nr = Math.round(copy[center] * (1 + amount) - (sr / taps.length) * amount);
      const ng = Math.round(copy[center + 1] * (1 + amount) - (sg / taps.length) * amount);
      const nb = Math.round(copy[center + 2] * (1 + amount) - (sb / taps.length) * amount);
      data[i] = Math.max(0, Math.min(255, nr));
      data[i + 1] = Math.max(0, Math.min(255, ng));
      data[i + 2] = Math.max(0, Math.min(255, nb));
    }
  }
}

function defringePass(data, width, height, alphaBuf) {
  const w = width;
  const h = height;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const idx = w * y + x;
      const i = idx * 4;
      const a = alphaBuf[idx];
      if (a === 0) continue;

      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      if (isWhiteFringe(r, g, b) || (chroma(r, g, b) < 34 && luminance(r, g, b) > 130)) {
        data[i + 3] = 0;
        alphaBuf[idx] = 0;
        continue;
      }

      let lightNeighbors = 0;
      let transparentNeighbors = 0;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          if (dx === 0 && dy === 0) continue;
          const nx = x + dx;
          const ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          const ni = w * ny + nx;
          if (alphaBuf[ni] === 0) {
            transparentNeighbors++;
            continue;
          }
          const nr = data[ni * 4];
          const ng = data[ni * 4 + 1];
          const nb = data[ni * 4 + 2];
          if (chroma(nr, ng, nb) < 32 && luminance(nr, ng, nb) > 150) lightNeighbors++;
        }
      }
      if (transparentNeighbors >= 3 && chroma(r, g, b) < 40 && luminance(r, g, b) > 125) {
        data[i + 3] = 0;
        alphaBuf[idx] = 0;
      } else if (lightNeighbors >= 4 && chroma(r, g, b) < 38 && luminance(r, g, b) > 140) {
        data[i + 3] = Math.max(0, a - 120);
        alphaBuf[idx] = data[i + 3];
      }
    }
  }
}

function loadRaster(inputPath) {
  const buf = fs.readFileSync(inputPath);
  const isJpeg = buf[0] === 0xff && buf[1] === 0xd8;
  const isPng = buf[0] === 0x89 && buf[1] === 0x50;

  if (isJpeg) {
    const decoded = jpeg.decode(buf, { useTArray: true });
    return { width: decoded.width, height: decoded.height, data: Buffer.from(decoded.data) };
  }
  if (isPng) {
    const png = PNG.sync.read(buf);
    return { width: png.width, height: png.height, data: Buffer.from(png.data) };
  }
  throw new Error(`Format non supporté: ${inputPath}`);
}

function toTransparentPng(raster) {
  const { width, height, data } = raster;
  const out = new PNG({ width, height });
  const alphaBuf = new Uint8Array(width * height);

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const si = (width * y + x) * 4;
      const idx = width * y + x;
      const r = data[si];
      const g = data[si + 1];
      const b = data[si + 2];
      const a = computeAlpha(r, g, b);
      alphaBuf[idx] = a;
      const [cr, cg, cb] = cleanRgb(r, g, b, a);
      out.data[si] = cr;
      out.data[si + 1] = cg;
      out.data[si + 2] = cb;
      out.data[si + 3] = a;
    }
  }

  sharpenPass(out.data, width, height, alphaBuf);
  defringePass(out.data, width, height, alphaBuf);

  return out;
}

function main() {
  const src = process.argv[2] ? path.resolve(process.argv[2]) : defaultSrc;
  if (!fs.existsSync(src)) {
    console.error('[process-kojo-logo] Source introuvable:', src);
    process.exit(1);
  }

  const raster = loadRaster(src);
  const png = toTransparentPng(raster);
  const logoOut = path.join(root, 'assets', 'logo.png');
  const iconOut = path.join(root, 'assets', 'icon.png');
  fs.writeFileSync(logoOut, PNG.sync.write(png));

  let fringe = 0;
  let opaque = 0;
  let transparent = 0;
  for (let i = 3; i < png.data.length; i += 4) {
    const a = png.data[i];
    if (a === 0) transparent++;
    else if (a === 255) opaque++;
    else fringe++;
  }
  const total = transparent + opaque + fringe;
  console.log(
    `[process-kojo-logo] ${src}\n` +
    `  → ${logoOut} (${png.width}x${png.height})\n` +
    `  alpha: transparent=${(transparent / total * 100).toFixed(1)}% ` +
    `opaque=${(opaque / total * 100).toFixed(1)}% soft=${(fringe / total * 100).toFixed(1)}%`
  );

  fs.copyFileSync(logoOut, iconOut);
}

main();
