#!/usr/bin/env node
// Full Authority fixed theater bake.
// Terrain/noise equations are adapted from Worldsmith by Hridhaan Shah
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
  theaterMeters: 150000,
  verticalScaleMeters: 4500,
  viewOriginX: -30.8224,
  viewOriginY: -13.5516,
  viewSpanX: 12.2743,
  viewSpanY: 22.1486,
};

// Worldsmith's ridge pass can legitimately push normalized terrain above 1.0.
// RAW16 still stores 0...65535, so reserve enough encoding headroom for the full
// generator range instead of clipping every value above 1.0 into a flat plateau.
// Runtime sampling decodes this factor before applying the existing meter scale.
const HEIGHT_ENCODING_MAX = 1.36;

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
function mixColor(a, b, t) {
  const k = clamp01(t);
  return [
    lerp(a[0], b[0], k),
    lerp(a[1], b[1], k),
    lerp(a[2], b[2], k),
  ];
}
function scaleColor(color, scale) {
  return color.map((channel) => Math.max(0, Math.min(255, channel * scale)));
}

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
  return Math.max(0, base);
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

// GPU Gems' terrain texturing guidance uses surface normal/slope and altitude to
// keep cliffs rocky while flatter areas carry vegetation. We bake that same idea
// into one mobile-friendly macro albedo instead of asking RealityKit to run a
// multi-texture terrain shader every frame. Water is gated strictly by sea level.
function terrainColor(e, moisture, temperature, steepness, variation, seaLevel) {
  if (e < seaLevel) {
    const depth = smoothstep(0.015, 0.16, seaLevel - e);
    return scaleColor(
      mixColor([46, 78, 96], [15, 35, 52], depth),
      0.97 + variation * 0.03
    );
  }

  const aboveSea = e - seaLevel;
  const high = smoothstep(0.68, 1.04, e);
  const veryHigh = smoothstep(0.94, 1.20, e);
  const cliff = smoothstep(0.055, 0.32, steepness);
  const wet = smoothstep(0.36, 0.74, moisture);
  const cold = 1 - smoothstep(0.26, 0.62, temperature);

  const dryGrass = [128, 125, 79];
  const greenGrass = [79, 111, 68];
  const forest = [48, 76, 54];
  const lowland = mixColor(dryGrass, greenGrass, moisture * 0.92);
  let color = mixColor(lowland, forest, wet * (1 - high) * 0.56);

  const lowRock = [102, 101, 94];
  const alpineRock = [145, 141, 130];
  const rock = mixColor(lowRock, alpineRock, high);
  const rockWeight = Math.max(cliff * 0.90, high * 0.46);
  color = mixColor(color, rock, rockWeight);

  // Snow prefers genuinely high/cold terrain and recedes on the steepest faces,
  // leaving readable exposed rock instead of flat white billboard-like patches.
  const snowAltitude = smoothstep(0.96, 1.18, e);
  const snowWeight = clamp01(snowAltitude * (0.62 + cold * 0.38) * (1 - cliff * 0.52));
  color = mixColor(color, [218, 220, 214], snowWeight);

  // A restrained shoreline band is the only bright transition next to water.
  // This prevents low-elevation blue from bleeding visually onto nearby slopes.
  const shore = 1 - smoothstep(0.006, 0.024, aboveSea);
  color = mixColor(color, [168, 153, 116], shore * (1 - cliff));

  // Keep the macro map free of baked directional shadows. Runtime PBR lighting
  // owns form; the bake only adds low-frequency natural color variation.
  const brightness = 0.965 + variation * 0.070 + veryHigh * 0.015;
  return scaleColor(color, brightness);
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
    scanlines[row] = 0;
    Buffer.from(rgb.buffer, rgb.byteOffset + y * rowBytes, rowBytes)
      .copy(scanlines, row + 1);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  fs.writeFileSync(file, Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", zlib.deflateSync(scanlines, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]));
}

function writeWaterNormalMap(file) {
  const size = 256;
  const rgb = new Uint8Array(size * size * 3);
  const waves = [
    [3, 1, 0.34, 0.2],
    [-2, 5, 0.20, 1.4],
    [7, 3, 0.10, 2.3],
    [5, -6, 0.07, 4.1],
  ];
  const normalStrength = 0.020;

  for (let y = 0; y < size; y++) {
    const v = y / size;
    for (let x = 0; x < size; x++) {
      const u = x / size;
      let du = 0;
      let dv = 0;
      for (const [fx, fy, amplitude, phase] of waves) {
        const angle = Math.PI * 2 * (fx * u + fy * v) + phase;
        const c = Math.cos(angle) * Math.PI * 2 * amplitude;
        du += c * fx;
        dv += c * fy;
      }

      let nx = -du * normalStrength;
      let ny = -dv * normalStrength;
      let nz = 1;
      const length = Math.hypot(nx, ny, nz) || 1;
      nx /= length;
      ny /= length;
      nz /= length;

      const o = (y * size + x) * 3;
      rgb[o] = Math.round((nx * 0.5 + 0.5) * 255);
      rgb[o + 1] = Math.round((ny * 0.5 + 0.5) * 255);
      rgb[o + 2] = Math.round((nz * 0.5 + 0.5) * 255);
    }
  }

  writePNG24(file, size, size, rgb);
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

let maxElevation = 0;
let encodingOverflowSamples = 0;
for (let y = 0; y < n; y++) {
  if ((y & 63) === 0) process.stdout.write(`bake height ${y}/${n}\n`);
  const wy = worldYs[y];
  for (let x = 0; x < n; x++) {
    const e = elevationAt(worldXs[x], wy, THEATER.seed, THEATER.octaves);
    maxElevation = Math.max(maxElevation, e);
    if (e >= HEIGHT_ENCODING_MAX) encodingOverflowSamples += 1;
    heights[y * n + x] = Math.round(Math.min(1, e / HEIGHT_ENCODING_MAX) * 65535);
  }
}

if (encodingOverflowSamples > 0) {
  throw new Error(
    `Worldsmith height encoding overflow: ${encodingOverflowSamples} samples reached ` +
    `${HEIGHT_ENCODING_MAX}; raise HEIGHT_ENCODING_MAX instead of clipping terrain.`
  );
}

const raw = Buffer.alloc(heights.length * 2);
for (let i = 0; i < heights.length; i++) raw.writeUInt16LE(heights[i], i * 2);
const heightPath = path.join(outDir, "worldsmith_1337_height_1025.r16");
fs.writeFileSync(heightPath, raw);

const sample = (x, y) => (
  heights[Math.max(0, Math.min(n - 1, y)) * n + Math.max(0, Math.min(n - 1, x))] /
  65535 * HEIGHT_ENCODING_MAX
);

const albedoN = 1024;
const rgb = new Uint8Array(albedoN * albedoN * 3);
const metersPerTexel = THEATER.theaterMeters / (n - 1);
for (let y = 0; y < albedoN; y++) {
  const wy = worldYs[y];
  for (let x = 0; x < albedoN; x++) {
    const e = sample(x, y);
    const moisture = moistureAt(worldXs[x], wy, THEATER.seed, e, THEATER.seaLevel);
    const temperature = temperatureAt(wy, e, THEATER.seaLevel);

    const dx = (sample(x + 1, y) - sample(x - 1, y)) * 0.5;
    const dy = (sample(x, y + 1) - sample(x, y - 1)) * 0.5;
    const gx = dx * THEATER.verticalScaleMeters / metersPerTexel;
    const gy = dy * THEATER.verticalScaleMeters / metersPerTexel;
    const normalY = 1 / Math.sqrt(1 + gx * gx + gy * gy);
    const steepness = 1 - normalY;

    const macroNoise = gradNoise2D(
      worldXs[x] * 0.72 + 18.0,
      wy * 0.72 - 11.0,
      THEATER.seed + 1709
    );
    const color = terrainColor(
      e,
      moisture,
      temperature,
      steepness,
      macroNoise - 0.5,
      THEATER.seaLevel
    );

    const o = (y * albedoN + x) * 3;
    rgb[o] = Math.round(color[0]);
    rgb[o + 1] = Math.round(color[1]);
    rgb[o + 2] = Math.round(color[2]);
  }
}

const albedoPath = path.join(outDir, "worldsmith_1337_albedo_1024.png");
writePNG24(albedoPath, albedoN, albedoN, rgb);

const waterNormalPath = path.join(outDir, "worldsmith_water_normal_256.png");
writeWaterNormalMap(waterNormalPath);

const manifest = {
  name: "Full Authority fixed Worldsmith theater",
  generator: "Worldsmith-derived build-time bake",
  sourceCommit: "5c131b42990bf8f3b79a343b722bc466990ee4ee",
  selectedPermalink: "https://thedatawiz-dot.github.io/Worldsmith/#w=generated&seed=1337&x=-30.82&y=-13.55&z=0.35&d=8&s=0.465&t=natural&r=1&l=1&c=0&g=0",
  seed: THEATER.seed,
  octaves: THEATER.octaves,
  seaLevel: THEATER.seaLevel,
  heightEncodingMax: HEIGHT_ENCODING_MAX,
  maxGeneratedElevation: maxElevation,
  albedoModel: "slope-height-moisture-v2",
  waterNormal: path.basename(waterNormalPath),
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
console.log(`wrote ${waterNormalPath}`);
console.log(JSON.stringify(manifest, null, 2));
