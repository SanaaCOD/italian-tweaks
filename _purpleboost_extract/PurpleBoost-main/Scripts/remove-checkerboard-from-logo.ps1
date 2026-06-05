# Retire le damier + nettoie les halos + recadre serre (qualite logo).
param([string]$ImagePath = "")

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not $ImagePath) {
  $ImagePath = Join-Path $PSScriptRoot "..\assets\images\unreal-logo.png"
}
$resolved = Resolve-Path -LiteralPath $ImagePath -ErrorAction SilentlyContinue
if (-not $resolved) {
  Write-Host "Fichier introuvable: $ImagePath"
  exit 1
}
$path = $resolved.Path
$backup = [System.IO.Path]::ChangeExtension($path, ".bak.png")
Copy-Item -LiteralPath $path -Destination $backup -Force
Write-Host "Sauvegarde : $backup"

try {
  $null = [UnrealLogoPolish]
} catch {
  Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;

public static class UnrealLogoPolish {
  static int Sat(int r, int g, int b) {
    int mx = Math.Max(r, Math.Max(g, b));
    int mn = Math.Min(r, Math.Min(g, b));
    return mx - mn;
  }
  static bool Cand(int r, int g, int b) {
    int s = Sat(r, g, b);
    if (s > 48) return false;
    int avg = (r + g + b) / 3;
    if (avg < 65) return false;
    if (avg > 248) return true;
    if (avg > 100 && avg < 225) return true;
    if (s < 22 && avg > 168) return true;
    return false;
  }
  static int GetAlpha(byte[] buf, int stride, int x, int y) {
    return buf[y * stride + x * 4 + 3];
  }
  static void TryE(byte[] buf, int w, int h, int stride, bool[] vis, Queue<int> q, int x, int y) {
    if (x < 0 || x >= w || y < 0 || y >= h) return;
    int idx = y * w + x;
    if (vis[idx]) return;
    int j = y * stride + x * 4;
    int B = buf[j], G = buf[j + 1], R = buf[j + 2];
    if (!Cand(R, G, B)) return;
    vis[idx] = true;
    q.Enqueue(idx);
  }
  public static void Flood(byte[] buf, int w, int h, int stride) {
    bool[] vis = new bool[w * h];
    var q = new Queue<int>(65536);
    for (int x = 0; x < w; x++) {
      TryE(buf, w, h, stride, vis, q, x, 0);
      TryE(buf, w, h, stride, vis, q, x, h - 1);
    }
    for (int y = 0; y < h; y++) {
      TryE(buf, w, h, stride, vis, q, 0, y);
      TryE(buf, w, h, stride, vis, q, w - 1, y);
    }
    int[] dx = { 1, -1, 0, 0 };
    int[] dy = { 0, 0, 1, -1 };
    while (q.Count > 0) {
      int idx = q.Dequeue();
      int cx = idx % w;
      int cy = idx / w;
      int i = cy * stride + cx * 4;
      buf[i + 3] = 0;
      for (int k = 0; k < 4; k++) {
        int nx = cx + dx[k], ny = cy + dy[k];
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        int nidx = ny * w + nx;
        if (vis[nidx]) continue;
        int j = ny * stride + nx * 4;
        int B = buf[j], G = buf[j + 1], R = buf[j + 2];
        if (!Cand(R, G, B)) continue;
        vis[nidx] = true;
        q.Enqueue(nidx);
      }
    }
  }
  /// <summary>Supprime les pixels gris/blanc semi-transparents colles au fond (halos damier).</summary>
  public static void CleanupHalos(byte[] buf, int w, int h, int stride) {
    int[] dx = { -1, 0, 1, -1, 1, -1, 0, 1 };
    int[] dy = { -1, -1, -1, 0, 0, 1, 1, 1 };
    for (int pass = 0; pass < 2; pass++) {
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          int i = y * stride + x * 4;
          int a = buf[i + 3];
          if (a == 0) continue;
          int B = buf[i], G = buf[i + 1], R = buf[i + 2];
          int low = 0;
          for (int k = 0; k < 8; k++) {
            if (GetAlpha(buf, stride, x + dx[k], y + dy[k]) < 28) low++;
          }
          if (Cand(R, G, B) && low >= 5 && a < 245) {
            buf[i + 3] = 0;
            continue;
          }
          if (a < 95 && Cand(R, G, B)) {
            buf[i + 3] = 0;
            continue;
          }
          if (a < 140 && Sat(R, G, B) < 52 && Cand(R, G, B) && low >= 4) {
            buf[i + 3] = 0;
          }
        }
      }
    }
  }
  /// <summary>Renforce legerement les bords opaques du logo (moins de grisatre).</summary>
  public static void SolidifyColorEdges(byte[] buf, int w, int h, int stride) {
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        int i = y * stride + x * 4;
        int a = buf[i + 3];
        if (a < 200) continue;
        int B = buf[i], G = buf[i + 1], R = buf[i + 2];
        if (Cand(R, G, B)) continue;
        if (Sat(R, G, B) < 38) continue;
        buf[i + 3] = 255;
      }
    }
  }
  public static Rectangle ContentBounds(byte[] buf, int w, int h, int stride, int alphaThresh) {
    int minx = w, miny = h, maxx = -1, maxy = -1;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (buf[y * stride + x * 4 + 3] <= alphaThresh) continue;
        if (x < minx) minx = x;
        if (y < miny) miny = y;
        if (x > maxx) maxx = x;
        if (y > maxy) maxy = y;
      }
    }
    if (maxx < 0) return System.Drawing.Rectangle.Empty;
    return new Rectangle(minx, miny, maxx - minx + 1, maxy - miny + 1);
  }
}
"@
}

$src = [System.Drawing.Bitmap]::FromFile($path)
$w = $src.Width
$h = $src.Height
$fmt = [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
$bmp = New-Object System.Drawing.Bitmap $w, $h, $fmt
$gr = [System.Drawing.Graphics]::FromImage($bmp)
$gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gr.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gr.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gr.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$gr.DrawImage($src, 0, 0, $w, $h)
$gr.Dispose()
$src.Dispose()

$rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
$bd = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, $fmt)
$stride = $bd.Stride
$len = [Math]::Abs($stride) * $h
$buf = New-Object byte[] $len
[System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $buf, 0, $len)

[UnrealLogoPolish]::Flood($buf, $w, $h, $stride)
[UnrealLogoPolish]::CleanupHalos($buf, $w, $h, $stride)
[UnrealLogoPolish]::SolidifyColorEdges($buf, $w, $h, $stride)

[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $bd.Scan0, $len)
$bmp.UnlockBits($bd)

$pad = 4
$bb = [UnrealLogoPolish]::ContentBounds($buf, $w, $h, $stride, 12)
if (-not $bb.IsEmpty) {
  $rx = [Math]::Max(0, $bb.X - $pad)
  $ry = [Math]::Max(0, $bb.Y - $pad)
  $rw = [Math]::Min($w - $rx, $bb.Width + 2 * $pad)
  $rh = [Math]::Min($h - $ry, $bb.Height + 2 * $pad)
  if ($rw -gt 8 -and $rh -gt 8 -and ($rw -lt $w - 6 -or $rh -lt $h - 6)) {
    $crop = New-Object System.Drawing.Rectangle $rx, $ry, $rw, $rh
    $bmp2 = $bmp.Clone($crop, $fmt)
    $bmp.Dispose()
    $bmp = $bmp2
    Write-Host "Recadrage contenu : ${rw}x${rh}"
  }
}

$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Host "OK - PNG mis a jour : $path"
