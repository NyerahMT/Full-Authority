import { clamp01, hash2, lerp, smoothstep, smootherstep } from './math.mjs';

export const WORLD = {
  WARP: 0.45,
  LAT_PERIOD: 52,
  CONTRAST: 1.55,
  RIDGE: 0.34,
  RIDGE_FREQ: 1.7,
  RIDGE_OCTAVES: 6,
};

export const THEATER = {
  seed: 1337,
  octaves: 8,
  seaLevel: 0.465,
  sourceSize: 4097,
  outputSize: 1025,
  sourceStride: 4,
  theaterMeters: 150000,
  verticalScaleMeters: 4500,
  baselineNormalized: 0.49768830303526773,
  siteU: 0.3712567,
  siteV: 0.4103772,
  mapHeadingRadians: 1.038470904936626,
  runwayCenterNorthMeters: 1800,
  viewOriginX: -30.8224,
  viewOriginY: -13.5516,
  viewSpanX: 12.2743,
  viewSpanY: 22.1486,
};

const GRAD2 = [[1,1],[-1,1],[1,-1],[-1,-1],[1,0],[-1,0],[0,1],[0,-1]];

export function gradNoise2D(x, y, seed) {
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

export function fbm(x, y, seed, octaves, lacunarity, gain) {
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

export function elevationAt(x, y, seed, octaves) {
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

export function moistureAt(x, y, seed, elev, seaLevel) {
  const m = fbm(x * 0.6 + 100, y * 0.6 - 40, seed + 555, 4, 2, 0.5);
  const dryness = Math.max(0, elev - seaLevel) * 0.95;
  return clamp01(m * 1.15 - dryness * 0.6);
}

export function temperatureAt(y, elev, seaLevel) {
  const lat = Math.cos((y / WORLD.LAT_PERIOD) * Math.PI * 2) * 0.5 + 0.5;
  const lapse = Math.max(0, elev - seaLevel) * 1.7;
  return clamp01(lat + 0.06 - lapse);
}

export function mapUVToWorld(u, v) {
  const c = Math.cos(THEATER.mapHeadingRadians);
  const s = Math.sin(THEATER.mapHeadingRadians);
  const mapEast = (u - THEATER.siteU) * THEATER.theaterMeters;
  const mapNorth = (THEATER.siteV - v) * THEATER.theaterMeters;
  const east = c * mapEast - s * mapNorth;
  const localNorth = s * mapEast + c * mapNorth;
  return [east, localNorth + THEATER.runwayCenterNorthMeters];
}

export function worldToMapUV(east, north) {
  const localNorth = north - THEATER.runwayCenterNorthMeters;
  const c = Math.cos(THEATER.mapHeadingRadians), s = Math.sin(THEATER.mapHeadingRadians);
  const mapEast = c * east + s * localNorth;
  const mapNorth = -s * east + c * localNorth;
  return [THEATER.siteU + mapEast / THEATER.theaterMeters,
          THEATER.siteV - mapNorth / THEATER.theaterMeters];
}

export function airfieldBlend(east, north) {
  const dx = Math.max(Math.abs(east) - 900, 0);
  const dz = Math.max(Math.abs(north - THEATER.runwayCenterNorthMeters) - 2500, 0);
  return smoothstep(0, 750, Math.hypot(dx, dz));
}
