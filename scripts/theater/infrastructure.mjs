import { DIRS, MinHeap, hash2, lerp, smoothstep } from './math.mjs';
import { THEATER, worldToMapUV } from './worldsmith.mjs';
import { multiSourceDistance } from './hydrology.mjs';

export const ROAD_GRID = 257;

export function siteSettlements(elevation, seaMask, slope, riverMask, worldAt, n) {
  const riverDistance = multiSourceDistance(riverMask, n, 80);
  const candidates = [];
  const step = 12;
  for (let y = step; y < n - step; y += step) {
    for (let x = step; x < n - step; x += step) {
      const i = y * n + x;
      if (seaMask[i]) continue;
      const [east, north] = worldAt(x, y);
      if (Math.hypot(east, north - THEATER.runwayCenterNorthMeters) < 12000) continue;
      const h = elevation[i], s = slope[i];
      if (h < -40 || h > 1500 || s > 0.23) continue;
      const rd = riverDistance[i];
      const waterScore = rd <= 2 ? 0.45 : rd <= 8 ? 1.0 - (rd - 2) / 10 : Math.max(0, 0.45 - (rd - 8) / 55);
      const flatScore = 1 - smoothstep(0.025, 0.23, s);
      const elevScore = 1 - smoothstep(900, 1800, h);
      const coastSafety = Math.min(1, Math.max(0, (h + 40) / 150));
      const regional = 0.88 + 0.12 * hash2(x, y, THEATER.seed + 811);
      const score = (0.50 * flatScore + 0.28 * waterScore + 0.16 * elevScore + 0.06 * coastSafety) * regional;
      candidates.push({ x, y, east, north, score });
    }
  }
  candidates.sort((a, b) => b.score - a.score);
  const selected = [];
  for (const c of candidates) {
    if (c.score < 0.45) break;
    if (selected.some(s => Math.hypot(c.east - s.east, c.north - s.north) < 16500)) continue;
    const kind = c.score > 0.76 ? 'town' : 'village';
    selected.push({
      name: `SITE-${String(selected.length + 1).padStart(2, '0')}`,
      kind,
      east: +c.east.toFixed(1),
      north: +c.north.toFixed(1),
      radiusMeters: kind === 'town' ? 820 : 470,
      seed: (THEATER.seed * 97 + selected.length * 811) | 0,
      score: +c.score.toFixed(4),
      headingRadians: 0,
    });
    if (selected.length >= 9) break;
  }
  return selected;
}

function primMST(nodes) {
  const n = nodes.length, used = new Uint8Array(n), best = new Float64Array(n), parent = new Int32Array(n);
  best.fill(Infinity); parent.fill(-1); best[0] = 0;
  const edges = [];
  for (let k = 0; k < n; k++) {
    let u = -1, bv = Infinity;
    for (let i = 0; i < n; i++) if (!used[i] && best[i] < bv) { bv = best[i]; u = i; }
    if (u < 0) break;
    used[u] = 1;
    if (parent[u] >= 0) edges.push([parent[u], u]);
    for (let v = 0; v < n; v++) if (!used[v]) {
      const d = Math.hypot(nodes[u].east - nodes[v].east, nodes[u].north - nodes[v].north);
      if (d < best[v]) { best[v] = d; parent[v] = u; }
    }
  }
  return edges;
}

function aStarRoad(start, goal, grid) {
  const { size, heights, slopes, water, river, existing } = grid;
  const count = size * size;
  const g = new Float64Array(count); g.fill(Infinity);
  const came = new Int32Array(count); came.fill(-1);
  const closed = new Uint8Array(count);
  const heap = new MinHeap();
  const heuristic = (i) => {
    const x = i % size, y = (i / size) | 0, gx = goal % size, gy = (goal / size) | 0;
    return Math.hypot(x - gx, y - gy);
  };
  g[start] = 0;
  heap.push(heuristic(start), start);
  while (heap.size) {
    const [, i] = heap.pop();
    if (closed[i]) continue;
    closed[i] = 1;
    if (i === goal) break;
    const x = i % size, y = (i / size) | 0;
    for (const [dx, dy, dist] of DIRS) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= size || ny >= size) continue;
      const ni = ny * size + nx;
      if (closed[ni]) continue;
      const meanSlope = (slopes[i] + slopes[ni]) * 0.5;
      const rise = Math.abs(heights[ni] - heights[i]) / (dist * grid.cellMeters);
      const steep = Math.max(meanSlope, rise);
      let penalty = 1 + 22 * steep * steep + 120 * Math.max(0, steep - 0.10) ** 2;
      if (water[ni]) penalty += 900;
      if (river[ni]) penalty += 3.8;
      if (heights[ni] > 1900) penalty += (heights[ni] - 1900) / 280;
      if (existing[ni]) penalty *= 0.48;
      const ng = g[i] + dist * penalty;
      if (ng < g[ni]) {
        g[ni] = ng;
        came[ni] = i;
        heap.push(ng + heuristic(ni) * 1.04, ni);
      }
    }
  }
  if (came[goal] < 0) return null;
  const path = [];
  let c = goal;
  while (c >= 0) { path.push(c); if (c === start) break; c = came[c]; }
  path.reverse();
  return path;
}

function safeSimplifyRoad(points, sampleHeightSlopeWater) {
  if (points.length <= 2) return points;
  const validSegment = (a, b) => {
    const dist = Math.hypot(b[0] - a[0], b[1] - a[1]);
    const steps = Math.max(2, Math.ceil(dist / 180));
    let previousHeight = null;
    for (let k = 0; k <= steps; k++) {
      const t = k / steps, east = lerp(a[0], b[0], t), north = lerp(a[1], b[1], t);
      const uv = worldToMapUV(east, north);
      if (uv[0] < 0 || uv[1] < 0 || uv[0] > 1 || uv[1] > 1) return false;
      const q = sampleHeightSlopeWater(uv[0], uv[1]);
      if (q.water || q.slope > 0.33) return false;
      if (previousHeight !== null) {
        const grade = Math.abs(q.height - previousHeight) / (dist / steps);
        if (grade > 0.20) return false;
      }
      previousHeight = q.height;
    }
    return true;
  };

  const out = [points[0]];
  let i = 0;
  while (i < points.length - 1) {
    let best = i + 1;
    const maxJ = Math.min(points.length - 1, i + 7);
    for (let j = maxJ; j > i + 1; j--) {
      const d = Math.hypot(points[j][0] - points[i][0], points[j][1] - points[i][1]);
      if (d > 3200) continue;
      if (validSegment(points[i], points[j])) { best = j; break; }
    }
    out.push(points[best]);
    i = best;
  }
  return out;
}

export function buildRoadNetwork(settlements, sampleHeightSlopeWater, worldFromRoadGrid) {
  const nodes = [{ name: 'AIRBASE', kind: 'military', east: 420, north: 760, radiusMeters: 0, seed: 0, score: 1, headingRadians: 0 }, ...settlements];
  const size = ROAD_GRID, count = size * size, cellMeters = THEATER.theaterMeters / (size - 1);
  const heights = new Float32Array(count), slopes = new Float32Array(count), water = new Uint8Array(count), river = new Uint8Array(count), existing = new Uint8Array(count);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const i = y * size + x, s = sampleHeightSlopeWater(x / (size - 1), y / (size - 1));
    heights[i] = s.height; slopes[i] = s.slope; water[i] = s.water ? 1 : 0; river[i] = s.river ? 1 : 0;
  }
  const grid = { size, cellMeters, heights, slopes, water, river, existing };
  const nodeCell = (node) => {
    const uv = worldToMapUV(node.east, node.north);
    const x = Math.max(0, Math.min(size - 1, Math.round(uv[0] * (size - 1))));
    const y = Math.max(0, Math.min(size - 1, Math.round(uv[1] * (size - 1))));
    return y * size + x;
  };

  const edges = primMST(nodes);
  const edgeKey = (a, b) => a < b ? `${a}:${b}` : `${b}:${a}`;
  const used = new Set(edges.map(e => edgeKey(e[0], e[1])));
  const extras = [];
  for (let i = 1; i < nodes.length; i++) for (let j = i + 1; j < nodes.length; j++) {
    if (used.has(edgeKey(i, j))) continue;
    const d = Math.hypot(nodes[i].east - nodes[j].east, nodes[i].north - nodes[j].north);
    if (d < 38000) extras.push([d, i, j]);
  }
  extras.sort((a, b) => a[0] - b[0]);
  for (const [, i, j] of extras) {
    if (edges.length >= nodes.length + 2) break;
    edges.push([i, j]);
    used.add(edgeKey(i, j));
  }

  const roads = [];
  for (const [a, b] of edges) {
    const path = aStarRoad(nodeCell(nodes[a]), nodeCell(nodes[b]), grid);
    if (!path) continue;
    let waterCrossings = 0;
    for (const i of path) if (water[i]) waterCrossings++;
    if (waterCrossings > 8) continue;
    for (const i of path) {
      existing[i] = 1;
      const x = i % size, y = (i / size) | 0;
      for (let yy = Math.max(0, y - 1); yy <= Math.min(size - 1, y + 1); yy++)
        for (let xx = Math.max(0, x - 1); xx <= Math.min(size - 1, x + 1); xx++) existing[yy * size + xx] = 1;
    }
    let pts = path.map(i => worldFromRoadGrid(i % size, (i / size) | 0));
    pts = safeSimplifyRoad(pts, sampleHeightSlopeWater);

    // A* runs on a coarse routing grid, but the authored destination is the
    // actual settlement/base center. Terminating on those exact coordinates
    // guarantees that regional roads physically meet local streets and the apron.
    if (pts.length >= 2) {
      pts[0] = [nodes[a].east, nodes[a].north];
      pts[pts.length - 1] = [nodes[b].east, nodes[b].north];
    }

    const cls = (a === 0 || b === 0 || nodes[a].kind === 'town' || nodes[b].kind === 'town') ? 'primary' : 'secondary';
    roads.push({
      class: cls,
      widthMeters: cls === 'primary' ? 10.5 : 7.5,
      shoulderMeters: cls === 'primary' ? 4.0 : 2.5,
      from: nodes[a].name,
      to: nodes[b].name,
      points: pts.map(p => p.map(v => +v.toFixed(1))),
    });
    for (const idx of [a, b]) if (idx > 0 && pts.length >= 2) {
      const settlement = settlements[idx - 1];
      const endpoint = idx === a ? pts[0] : pts[pts.length - 1];
      const neighbor = idx === a ? pts[Math.min(1, pts.length - 1)] : pts[Math.max(0, pts.length - 2)];
      settlement.headingRadians = +Math.atan2(endpoint[0] - neighbor[0], endpoint[1] - neighbor[1]).toFixed(5);
    }
  }
  return roads;
}
