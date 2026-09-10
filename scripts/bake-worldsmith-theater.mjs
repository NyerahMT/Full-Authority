#!/usr/bin/env node
// Full Authority fixed theater bake.
// Terrain/noise/biome equations are adapted from Worldsmith by Hridhaan Shah
// (MIT), adapted from commit 5c131b42990bf8f3b79a343b722bc466990ee4ee.
// This script runs at build time only. The app ships and loads static assets;
// it does not generate or reroll terrain at runtime.

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import zlib from "node:zlib";

const WORLD = {
  WARP: 0.45,
  LAT_PERIOD: 52,
  CONTRAST: 1.55,
  RIDGE: 0.34,
  RIDGE_FREQ: 1.7,
  RIDGE_OCTAVES: 6,
};

const THEATER = {
  seed: 1337,
  octaves: 8,
  seaLevel: 0.465,
  sourceSize: 4097,
  outputSize: 1025,
  sourceStride: 4,
  viewOriginX: -30.8224,
  viewOriginY: -13.5516,
  viewSpanX: 12.2743,
  viewSpanY: 22.1486,
};

const COLORS = [
  [20, 44, 76], [32, 72, 112], [60, 112, 152], [216, 202, 160],
  [222, 199, 148], [193, 186, 122], [143, 165, 101], [156, 157, 117],
  [94, 129, 83], [76, 132, 78], [56, 108, 68],
  [76, 108, 95], [164, 170, 154], [140, 133, 124], [240, 242, 240],
];

const B = {
  DEEP: 0, OCEAN: 1, SHALLOW: 2, BEACH: 3,
  DESERT: 4, SAVANNA: 5, GRASSLAND: 6, SHRUBLAND: 7,
  TEMPERATE_FOREST: 8, TROPICAL_FOREST: 9, RAINFOREST: 10,
  TAIGA: 11, TUNDRA: 12, ROCK: 13, SNOW: 14,
};

function hash2(x, y, seed) {
  let h = (Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263) + Math.imul(seed | 0, 1442695041)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

function smootherstep(t) { return t * t * t * (t * (t * 6 - 15) + 10); }
function smoothstep(edge0, edge1, x) {
  const t = Math.min(1, Math.max(0, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}
function clamp01(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
function lerp(a, b, t) { return a + (b - a) * t; }

const GRAD2 = [
  [1, 1], [-1, 1], [1, -1], [-1, -1],
  [1, 0], [-1, 0], [0, 1], [0, -1],
];

function gradNoise2D(x, y, seed) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const xf = x - xi, yf = y - yi;
  const u = smootherstep(xf), v = smootherstep(yf);
  const g00 = GRAD2[(hash2(xi, yi, seed) * 8) & 7];
  const g10 = GRAD2[(hash2(xi + 1, yi, seed) * 8) & 7];
  const g01 = GRAD2[(hash2(xi, yi + 1, seed) * 8) & 7];
  const g11 = GRAD2[(hash2(xi + 1, yi + 1, seed) * 8) & 7];
  const n00 = g00[0] * xf + g00[1] * yf;
  const n10 = g10[0] * (xf - 1) + g10[1] * yf;
  const n01 = g01[0] * xf + g01[1] * (yf - 1);
  const n11 = g11[0] * (xf - 1) + g11[1] * (yf - 1);
  return lerp(lerp(n00, n10, u), lerp(n01, n11, u), v) * 0.7071 + 0.5;
}

function fbm(x, y, seed, octaves, lacunarity, gain) {
  let amp = 0.5, freq = 1, sum = 0, norm = 0;
  for (let i = 0; i < octaves; i++) {
    sum += amp * gradNoise2D(x * freq, y * freq, seed + i * 101);
    norm += amp;
    amp *= gain;
    freq *= lacunarity;
  }
  return norm > 0 ? sum / norm : 0;
}

function ridgedFbm(x, y, seed, octaves, lacunarity, gain) {
  let amp = 0.5, freq = 1, sum = 0, norm = 0;
  for (let i = 0; i < octaves; i++) {
    const n = gradNoise2D(x * freq, y * freq, seed + i * 131);
    let r = 1 - Math.abs(n * 2 - 1);
    r *= r;
    sum += amp * r;
    norm += amp;
    amp *= gain;
    freq *= lacunarity;
  }
  return norm > 0 ? sum / norm : 0;
}

function elevationAt(x, y, seed, octaves) {
  const wx = fbm(x * 0.5, y * 0.5, seed + 911, 2, 2, 0.5) - 0.5;
  const wy = fbm(x * 0.5 + 3.7, y * 0.5 + 8.1, seed + 977, 2, 2, 0.5) - 0.5;
  const px = x + wx * WORLD.WARP;
  const py = y + wy * WORLD.WARP;
  let base = fbm(px, py, seed, octaves, 2, 0.5);
  base = clamp01((base - 0.5) * WORLD.CONTRAST + 0.5);
  const mask = smoothstep(0.52, 0.80, base);
  if (mask > 0.001) {
    const ridge = ridgedFbm(px * WORLD.RIDGE_FREQ, py * WORLD.RIDGE_FREQ, seed + 313,
      Math.min(octaves, WORLD.RIDGE_OCTAVES), 2, 0.5);
    base += ridge * mask * WORLD.RIDGE;
  }
  return clamp01(base);
}

function moistureAt(x, y, seed, elev, seaLevel) {
  const m = fbm(x * 0.6 + 100, y * 0.6 - 40, seed + 555, 4, 2, 0.5);
  const dryness = Math.max(0, elev - seaLevel) * 0.95;
  return clamp01(m * 1.15 - dryness * 0.6);
}

function temperatureAt(y, elev, seaLevel) {
  const lat = Math.cos((y / WORLD.LAT_PERIOD) * Math.PI * 2) * 0.5 + 0.5;
  const lapse = Math.max(0, elev - seaLevel) * 1.7;
  return clamp01(lat + 0.06 - lapse);
}

function classify(e, m, t, seaLevel) {
  if (e < seaLevel - 0.12) return B.DEEP;
  if (e < seaLevel - 0.035) return B.OCEAN;
  if (e < seaLevel) return B.SHALLOW;
  if (e < seaLevel + 0.012) return B.BEACH;
  if (e > 0.88) return B.SNOW;
  if (e > 0.78) return t < 0.32 ? B.SNOW : B.ROCK;
  if (t < 0.20) return e > seaLevel + 0.2 ? B.SNOW : B.TUNDRA;
  if (t < 0.38) return m > 0.45 ? B.TAIGA : B.TUNDRA;
  if (t < 0.68) {
    if (m < 0.28) return B.SHRUBLAND;
    if (m < 0.50) return B.GRASSLAND;
    return B.TEMPERATE_FOREST;
  }
  if (m < 0.24) return B.DESERT;
  if (m < 0.42) return B.SAVANNA;
  if (m < 0.62) return B.TROPICAL_FOREST;
  return B.RAINFOREST;
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBytes = Buffer.from(type, "ascii");
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  typeBytes.copy(out, 4);
  data.copy(out, 8);
  const checksumInput = Buffer.concat([typeBytes, data]);
  out.writeUInt32BE(crc32(checksumInput), 8 + data.length);
  return out;
}

function writePNG24(file, width, height, rgb) {
  const rowBytes = width * 3;
  const scanlines = Buffer.alloc((rowBytes + 1) * height);
  for (let y = 0; y < height; y++) {
    const row = y * (rowBytes + 1);
    scanlines[row] = 0; // PNG filter: None
    Buffer.from(rgb.buffer, rgb.byteOffset + y * rowBytes, rowBytes)
      .copy(scanlines, row + 1);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 2;  // truecolor RGB
  ihdr[10] = 0; // compression
  ihdr[11] = 0; // filter
  ihdr[12] = 0; // no interlace

  fs.writeFileSync(file, Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", zlib.deflateSync(scanlines, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]));
}

const outDir = process.argv[2] || path.join("Assets", "JSBSim", "visuals", "world");
fs.mkdirSync(outDir, { recursive: true });

const span = Math.min(THEATER.viewSpanX, THEATER.viewSpanY);
const squareOriginX = THEATER.viewOriginX + (THEATER.viewSpanX - span) / 2;
const squareOriginY = THEATER.viewOriginY + (THEATER.viewSpanY - span) / 2;
const sourceScale = span / THEATER.sourceSize;
const n = THEATER.outputSize;
const heights = new Uint16Array(n * n);
const worldXs = new Float64Array(n);
const worldYs = new Float64Array(n);
for (let i = 0; i < n; i++) {
  worldXs[i] = squareOriginX + (i * THEATER.sourceStride) * sourceScale;
  worldYs[i] = squareOriginY + (i * THEATER.sourceStride) * sourceScale;
}

for (let y = 0; y < n; y++) {
  if ((y & 63) === 0) process.stdout.write(`bake height ${y}/${n}\n`);
  const wy = worldYs[y];
  for (let x = 0; x < n; x++) {
    const e = elevationAt(worldXs[x], wy, THEATER.seed, THEATER.octaves);
    heights[y * n + x] = Math.round(e * 65535);
  }
}

const raw = Buffer.alloc(heights.length * 2);
for (let i = 0; i < heights.length; i++) raw.writeUInt16LE(heights[i], i * 2);
const heightPath = path.join(outDir, "worldsmith_1337_height_1025.r16");
fs.writeFileSync(heightPath, raw);

const albedoN = 1024;
const rgb = new Uint8Array(albedoN * albedoN * 3);
const sample = (x, y) => heights[Math.max(0, Math.min(n - 1, y)) * n + Math.max(0, Math.min(n - 1, x))] / 65535;
for (let y = 0; y < albedoN; y++) {
  const wy = worldYs[y];
  for (let x = 0; x < albedoN; x++) {
    const e = sample(x, y);
    const m = moistureAt(worldXs[x], wy, THEATER.seed, e, THEATER.seaLevel);
    const t = temperatureAt(wy, e, THEATER.seaLevel);
    const biome = classify(e, m, t, THEATER.seaLevel);
    const base = COLORS[biome];

    const dx = sample(x + 1, y) - sample(x - 1, y);
    const dy = sample(x, y + 1) - sample(x, y - 1);
    const relief = Math.max(-0.22, Math.min(0.22, (-dx * 1.15 - dy * 0.75) * 6.0));
    const highLift = e > 0.72 ? Math.min(0.08, (e - 0.72) * 0.25) : 0;
    const brightness = 1.0 + relief + highLift;

    const o = (y * albedoN + x) * 3;
    rgb[o] = Math.max(0, Math.min(255, Math.round(base[0] * brightness)));
    rgb[o + 1] = Math.max(0, Math.min(255, Math.round(base[1] * brightness)));
    rgb[o + 2] = Math.max(0, Math.min(255, Math.round(base[2] * brightness)));
  }
}

const albedoPath = path.join(outDir, "worldsmith_1337_albedo_1024.png");
writePNG24(albedoPath, albedoN, albedoN, rgb);

const manifest = {
  name: "Full Authority fixed Worldsmith theater",
  generator: "Worldsmith-derived build-time bake",
  sourceCommit: "5c131b42990bf8f3b79a343b722bc466990ee4ee",
  selectedPermalink: "https://thedatawiz-dot.github.io/Worldsmith/#w=generated&seed=1337&x=-30.82&y=-13.55&z=0.35&d=8&s=0.465&t=natural&r=1&l=1&c=0&g=0",
  seed: THEATER.seed,
  octaves: THEATER.octaves,
  seaLevel: THEATER.seaLevel,
  viewOrigin: [THEATER.viewOriginX, THEATER.viewOriginY],
  viewSpan: [THEATER.viewSpanX, THEATER.viewSpanY],
  squareOrigin: [squareOriginX, squareOriginY],
  squareSpan: span,
  sourceSize: THEATER.sourceSize,
  outputSize: THEATER.outputSize,
  sourceStride: THEATER.sourceStride,
  heightSHA256: crypto.createHash("sha256").update(raw).digest("hex"),
};
fs.writeFileSync(path.join(outDir, "worldsmith_1337_manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log(`wrote ${heightPath} (${raw.length} bytes)`);
console.log(`wrote ${albedoPath}`);
console.log(JSON.stringify(manifest, null, 2));
