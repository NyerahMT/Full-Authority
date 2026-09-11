#!/usr/bin/env node
// Full Authority fixed-theater authoring pipeline.
//
// The runtime still receives the same RAW16 heightfield + macro albedo contract.
// At build time, this pipeline derives all secondary geography from that terrain:
// Priority-Flood -> D8 flow -> rivers/lakes -> settlement siting -> connected
// terrain-cost roads. No independent/random water or road placement survives.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { clamp01, mixColor, scaleColor, smoothstep } from './theater/math.mjs';
import {
  THEATER, elevationAt, moistureAt, temperatureAt, fbm,
  mapUVToWorld, airfieldBlend,
} from './theater/worldsmith.mjs';
import {
  RIVER_ACCUMULATION_THRESHOLD,
  priorityFloodCondition, d8Flow, flowAccumulation,
  extractRivers, selectLakes, multiSourceDistance,
} from './theater/hydrology.mjs';
import { ROAD_GRID, siteSettlements, buildRoadNetwork } from './theater/infrastructure.mjs';
import { writePNG, writeWaterNormalMap } from './theater/png.mjs';

const HEIGHT_ENCODING_MAX = 1.36;
const FEATURE_FILENAME = 'worldsmith_1337_features.json';
const outDir = process.argv[2] || path.join('Assets', 'JSBSim', 'visuals', 'world');
fs.mkdirSync(outDir, { recursive: true });

const span = Math.min(THEATER.viewSpanX, THEATER.viewSpanY);
const squareOriginX = THEATER.viewOriginX + (THEATER.viewSpanX - span) / 2;
const squareOriginY = THEATER.viewOriginY + (THEATER.viewSpanY - span) / 2;
const sourceScale = span / THEATER.sourceSize;
const n = THEATER.outputSize;
const count = n * n;
const heights = new Uint16Array(count);
const normalized = new Float32Array(count);
const elevationMeters = new Float32Array(count);
const gameElevation = new Float32Array(count);
const slopeGrid = new Float32Array(count);
const seaMask = new Uint8Array(count);
const worldXs = new Float64Array(n);
const worldYs = new Float64Array(n);

for (let i = 0; i < n; i++) {
  worldXs[i] = squareOriginX + (i * THEATER.sourceStride) * sourceScale;
  worldYs[i] = squareOriginY + (i * THEATER.sourceStride) * sourceScale;
}
const worldAt = (x, y) => mapUVToWorld(x / (n - 1), y / (n - 1));

let maxElevation = 0;
let encodingOverflowSamples = 0;
for (let y = 0; y < n; y++) {
  if ((y & 63) === 0) process.stdout.write(`bake height ${y}/${n}\n`);
  for (let x = 0; x < n; x++) {
    const i = y * n + x;
    const e = elevationAt(worldXs[x], worldYs[y], THEATER.seed, THEATER.octaves);
    normalized[i] = e;
    maxElevation = Math.max(maxElevation, e);
    if (e >= HEIGHT_ENCODING_MAX) encodingOverflowSamples++;
    heights[i] = Math.round(Math.min(1, e / HEIGHT_ENCODING_MAX) * 65535);
    elevationMeters[i] = (e - THEATER.baselineNormalized) * THEATER.verticalScaleMeters;
    const [east, north] = worldAt(x, y);
    gameElevation[i] = elevationMeters[i] * airfieldBlend(east, north);
    seaMask[i] = e < THEATER.seaLevel ? 1 : 0;
  }
}
if (encodingOverflowSamples > 0) {
  throw new Error(`Worldsmith height encoding overflow: ${encodingOverflowSamples} samples reached ${HEIGHT_ENCODING_MAX}`);
}

const cellMeters = THEATER.theaterMeters / (n - 1);
for (let y = 1; y < n - 1; y++) {
  for (let x = 1; x < n - 1; x++) {
    const i = y * n + x;
    const dx = (gameElevation[i + 1] - gameElevation[i - 1]) / (2 * cellMeters);
    const dy = (gameElevation[i + n] - gameElevation[i - n]) / (2 * cellMeters);
    slopeGrid[i] = Math.hypot(dx, dy);
  }
}

process.stdout.write('hydrology priority-flood\n');
const filled = priorityFloodCondition(gameElevation, n, seaMask);
const { downstream, indegree } = d8Flow(filled, n, seaMask);
const accumulation = flowAccumulation(downstream, indegree, n);
const { rivers, riverMask } = extractRivers(downstream, accumulation, filled, seaMask, n, worldAt);
const depressionMask = new Uint8Array(count);
for (let i = 0; i < count; i++) {
  if (!seaMask[i] && filled[i] - gameElevation[i] >= 2.5) depressionMask[i] = 1;
}
const { lakes, lakeMask } = selectLakes(depressionMask, n, gameElevation, filled, worldAt);

process.stdout.write('site settlements\n');
const settlements = siteSettlements(gameElevation, seaMask, slopeGrid, riverMask, worldAt, n);
const sampleHeightSlopeWater = (u, v) => {
  const x = Math.max(0, Math.min(n - 1, Math.round(u * (n - 1))));
  const y = Math.max(0, Math.min(n - 1, Math.round(v * (n - 1))));
  const i = y * n + x;
  return {
    height: gameElevation[i],
    slope: slopeGrid[i],
    water: Boolean(seaMask[i] || lakeMask[i]),
    river: Boolean(riverMask[i]),
  };
};
const worldFromRoadGrid = (x, y) => mapUVToWorld(x / (ROAD_GRID - 1), y / (ROAD_GRID - 1));
process.stdout.write('route roads\n');
const roads = buildRoadNetwork(settlements, sampleHeightSlopeWater, worldFromRoadGrid);

// Macro albedo is landclass-derived, not a painted feature map. Rivers remain
// separate geometry. Only the actual ocean and selected real basins are blue.
const albedoN = 1024;
const rgb = new Uint8Array(albedoN * albedoN * 3);
const landclass = new Uint8Array(albedoN * albedoN);
const riverDistance = multiSourceDistance(riverMask, n, 64);
for (let y = 0; y < albedoN; y++) {
  for (let x = 0; x < albedoN; x++) {
    const hi = y * n + x, i = y * albedoN + x;
    const e = normalized[hi], slope = slopeGrid[hi];
    const m0 = moistureAt(worldXs[x], worldYs[y], THEATER.seed, e, THEATER.seaLevel);
    const temperature = temperatureAt(worldYs[y], e, THEATER.seaLevel);
    const u = x / (albedoN - 1), v = y / (albedoN - 1);
    const nwDry = clamp01((0.58 - u) / 0.35) * clamp01((0.60 - v) / 0.38);
    const riparian = Math.max(0, 1 - riverDistance[hi] / 13);
    const moisture = clamp01(m0 * (1 - 0.46 * nwDry) + 0.30 * riparian);
    const cliff = smoothstep(0.05, 0.34, slope);
    const high = smoothstep(0.68, 1.04, e);
    const cold = 1 - smoothstep(0.26, 0.62, temperature);
    const variation = fbm(worldXs[x] * 3.2 + 19, worldYs[y] * 3.2 - 41,
      THEATER.seed + 7001, 3, 2, 0.5);

    let color, cls;
    if (seaMask[hi]) {
      const depth = smoothstep(0.015, 0.16, THEATER.seaLevel - e);
      color = mixColor([40, 82, 103], [12, 34, 52], depth);
      cls = 0;
    } else if (lakeMask[hi]) {
      color = [30, 76, 94];
      cls = 1;
    } else {
      const dryGrass = mixColor([139, 122, 78], [111, 112, 73], moisture);
      const green = mixColor([93, 118, 69], [52, 82, 54], smoothstep(0.46, 0.76, moisture));
      let low = mixColor(dryGrass, green, smoothstep(0.28, 0.68, moisture));

      // NW theater is deliberately arid/semi-arid folded limestone terrain,
      // influenced by northern-Iraq/Zagros color language without copying a real map.
      const iraq = mixColor([151, 128, 88], [139, 133, 112], cliff * 0.72 + high * 0.28);
      low = mixColor(low, iraq, nwDry * 0.83);

      const rock = mixColor([105, 104, 96], [151, 146, 134], high);
      color = mixColor(low, rock, Math.max(cliff * 0.88, high * 0.44));
      const snow = smoothstep(0.96, 1.18, e) * (0.60 + 0.40 * cold) * (1 - cliff * 0.52);
      color = mixColor(color, [218, 221, 216], snow);
      const shore = 1 - smoothstep(0.006, 0.024, e - THEATER.seaLevel);
      color = mixColor(color, [171, 155, 116], shore * (1 - cliff));
      const wetValley = riparian * (1 - cliff) * smoothstep(0.30, 0.62, moisture);
      color = mixColor(color, [68, 101, 59], wetValley * 0.26);
      color = scaleColor(color, 0.955 + variation * 0.075);
      cls = high > 0.55 ? 6 : cliff > 0.45 ? 5 : nwDry > 0.45 ? 4 : moisture > 0.63 ? 3 : 2;
    }

    rgb[i * 3] = Math.round(color[0]);
    rgb[i * 3 + 1] = Math.round(color[1]);
    rgb[i * 3 + 2] = Math.round(color[2]);
    landclass[i] = cls;
  }
}

const raw = Buffer.alloc(heights.length * 2);
for (let i = 0; i < heights.length; i++) raw.writeUInt16LE(heights[i], i * 2);
const heightPath = path.join(outDir, 'worldsmith_1337_height_1025.r16');
fs.writeFileSync(heightPath, raw);
const albedoPath = path.join(outDir, 'worldsmith_1337_albedo_1024.png');
writePNG(albedoPath, albedoN, albedoN, 3, rgb);
writePNG(path.join(outDir, 'worldsmith_1337_landclass_1024.png'), albedoN, albedoN, 1, landclass);
writeWaterNormalMap(path.join(outDir, 'worldsmith_water_normal_256.png'));

const features = {
  version: 1,
  theaterMeters: THEATER.theaterMeters,
  cellMeters: +cellMeters.toFixed(4),
  rivers,
  roads,
  lakes,
  settlements,
};
const featureJSON = JSON.stringify(features, null, 2) + '\n';
fs.writeFileSync(path.join(outDir, FEATURE_FILENAME), featureJSON);

// Hard quality gates. The build fails instead of silently shipping disconnected
// roads, chopped rivers, or a half-empty authoring pass.
if (rivers.length < 4) throw new Error(`Hydrology produced only ${rivers.length} rivers`);
if (settlements.length < 5) throw new Error(`Settlement siting produced only ${settlements.length} sites`);
if (roads.length < settlements.length - 1) {
  throw new Error(`Road network is not sufficiently connected (${roads.length} roads / ${settlements.length} sites)`);
}
const connectedSites = new Set();
for (const road of roads) {
  if (road.points.length < 2) throw new Error(`Road ${road.from}-${road.to} has no usable geometry`);
  connectedSites.add(road.from); connectedSites.add(road.to);
}
for (const site of settlements) {
  if (!connectedSites.has(site.name)) throw new Error(`Settlement ${site.name} is orphaned from the road graph`);
}
if (!connectedSites.has('AIRBASE')) throw new Error('Airbase is orphaned from the road graph');
for (const river of rivers) {
  for (let p = 1; p < river.points.length; p++) {
    const a = river.points[p - 1][2], b = river.points[p][2];
    if (b > a + 0.2) throw new Error(`Hydrologic river surface climbs ${(b - a).toFixed(2)} m`);
  }
}

const manifest = {
  name: 'Full Authority coherent fixed theater',
  generator: 'Worldsmith elevation + Priority-Flood/D8 hydrology + terrain-cost infrastructure',
  sourceCommit: '5c131b42990bf8f3b79a343b722bc466990ee4ee',
  seed: THEATER.seed,
  seaLevel: THEATER.seaLevel,
  outputSize: n,
  heightEncodingMax: HEIGHT_ENCODING_MAX,
  theaterMeters: THEATER.theaterMeters,
  maxElevation,
  riverThresholdCells: RIVER_ACCUMULATION_THRESHOLD,
  riverSegments: rivers.length,
  lakes: lakes.length,
  settlements: settlements.length,
  roads: roads.length,
  featureFile: FEATURE_FILENAME,
  heightSHA256: crypto.createHash('sha256').update(raw).digest('hex'),
  featuresSHA256: crypto.createHash('sha256').update(featureJSON).digest('hex'),
};
fs.writeFileSync(path.join(outDir, 'worldsmith_1337_manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify(manifest, null, 2));
