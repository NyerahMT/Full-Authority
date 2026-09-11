import { DIRS, MinHeap, rdp } from './math.mjs';
import { THEATER } from './worldsmith.mjs';

export const HYDRO_EPSILON_METERS = 0.025;
export const RIVER_ACCUMULATION_THRESHOLD = 720;
export const LAKE_MIN_CELLS = 18;

export function priorityFloodCondition(elevation, n, seaMask) {
  const filled = new Float32Array(elevation);
  const visited = new Uint8Array(n * n);
  const heap = new MinHeap();
  const seed = (idx) => {
    if (visited[idx]) return;
    visited[idx] = 1;
    heap.push(filled[idx], idx);
  };

  for (let i = 0; i < n * n; i++) if (seaMask[i]) seed(i);
  for (let x = 0; x < n; x++) { seed(x); seed((n - 1) * n + x); }
  for (let y = 1; y < n - 1; y++) { seed(y * n); seed(y * n + (n - 1)); }

  while (heap.size) {
    const [level, idx] = heap.pop();
    const x = idx % n, y = (idx / n) | 0;
    for (const [dx, dy] of DIRS) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= n || ny >= n) continue;
      const ni = ny * n + nx;
      if (visited[ni]) continue;
      visited[ni] = 1;
      if (!seaMask[ni] && filled[ni] <= level) filled[ni] = level + HYDRO_EPSILON_METERS;
      heap.push(filled[ni], ni);
    }
  }
  return filled;
}

export function d8Flow(filled, n, seaMask) {
  const downstream = new Int32Array(n * n);
  downstream.fill(-1);
  const indegree = new Uint8Array(n * n);
  for (let y = 1; y < n - 1; y++) {
    for (let x = 1; x < n - 1; x++) {
      const i = y * n + x;
      if (seaMask[i]) continue;
      let best = -1, bestSlope = 0;
      const current = filled[i];
      for (const [dx, dy, dist] of DIRS) {
        const ni = (y + dy) * n + (x + dx);
        const slope = (current - filled[ni]) / dist;
        if (slope > bestSlope + 1e-9) { bestSlope = slope; best = ni; }
      }
      if (best >= 0) {
        downstream[i] = best;
        if (indegree[best] < 255) indegree[best]++;
      }
    }
  }
  return { downstream, indegree };
}

export function flowAccumulation(downstream, indegree, n) {
  const count = n * n;
  const accumulation = new Uint32Array(count);
  accumulation.fill(1);
  const remaining = new Uint8Array(indegree);
  const queue = new Int32Array(count);
  let head = 0, tail = 0;
  for (let i = 0; i < count; i++) if (remaining[i] === 0) queue[tail++] = i;
  while (head < tail) {
    const i = queue[head++];
    const d = downstream[i];
    if (d >= 0) {
      accumulation[d] += accumulation[i];
      if (--remaining[d] === 0) queue[tail++] = d;
    }
  }
  return accumulation;
}

export function extractRivers(downstream, accumulation, hydroSurface, seaMask, n, worldAt) {
  const channel = new Uint8Array(n * n);
  for (let i = 0; i < channel.length; i++) {
    if (!seaMask[i] && accumulation[i] >= RIVER_ACCUMULATION_THRESHOLD) channel[i] = 1;
  }
  const upstreamCount = new Uint8Array(n * n);
  for (let i = 0; i < channel.length; i++) {
    if (!channel[i]) continue;
    const d = downstream[i];
    if (d >= 0 && channel[d] && upstreamCount[d] < 255) upstreamCount[d]++;
  }

  const candidates = [];
  for (let source = 0; source < channel.length; source++) {
    if (!channel[source] || upstreamCount[source] !== 0) continue;
    const cells = [];
    let current = source, guard = 0, maxAccum = 0;
    while (current >= 0 && guard++ < n * 4) {
      cells.push(current);
      maxAccum = Math.max(maxAccum, accumulation[current]);
      const d = downstream[current];
      if (d < 0 || seaMask[d]) { if (d >= 0) cells.push(d); break; }
      current = d;
    }
    if (cells.length < 22) continue;
    const approxLengthMeters = cells.length * THEATER.theaterMeters / (n - 1);
    candidates.push({ cells, maxAccum, score: approxLengthMeters * Math.log2(maxAccum + 2) });
  }
  candidates.sort((a, b) => b.score - a.score);

  const rivers = [];
  const claimed = new Uint8Array(n * n);
  for (const candidate of candidates) {
    let overlap = 0;
    for (const i of candidate.cells) if (claimed[i]) overlap++;
    if (overlap / candidate.cells.length > 0.72) continue;

    const rawPoints = candidate.cells.map((i) => {
      const x = i % n, y = (i / n) | 0, p = worldAt(x, y);
      const width = Math.max(6.5, Math.min(52,
        5.5 + 5.0 * Math.log2(accumulation[i] / RIVER_ACCUMULATION_THRESHOLD + 1)));
      return [p[0], p[1], hydroSurface[i], width];
    });
    const simplified = rdp(rawPoints, 190);
    if (simplified.length < 3) continue;
    for (const i of candidate.cells) claimed[i] = 1;
    rivers.push({
      maxAccumulation: candidate.maxAccum,
      points: simplified.map(p => p.map(v => +v.toFixed(2))),
    });
    if (rivers.length >= 18) break;
  }
  return { rivers, riverMask: channel };
}

export function selectLakes(mask, n, original, filled, worldAt) {
  const seen = new Uint8Array(mask.length);
  const queue = new Int32Array(mask.length);
  const components = [];
  for (let start = 0; start < mask.length; start++) {
    if (!mask[start] || seen[start]) continue;
    let head = 0, tail = 0;
    queue[tail++] = start;
    seen[start] = 1;
    const cells = [];
    let surface = -Infinity, maxDepth = 0;
    while (head < tail) {
      const i = queue[head++];
      cells.push(i);
      surface = Math.max(surface, filled[i]);
      maxDepth = Math.max(maxDepth, filled[i] - original[i]);
      const x = i % n, y = (i / n) | 0;
      for (const [dx, dy] of [[-1,0],[1,0],[0,-1],[0,1]]) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= n || ny >= n) continue;
        const ni = ny * n + nx;
        if (mask[ni] && !seen[ni]) { seen[ni] = 1; queue[tail++] = ni; }
      }
    }
    if (cells.length >= LAKE_MIN_CELLS && maxDepth >= 2.5) components.push({ cells, surface, maxDepth });
  }

  components.sort((a, b) => b.cells.length - a.cells.length);
  const selected = components.slice(0, 6);
  const lakeMask = new Uint8Array(mask.length);
  const lakes = selected.map(component => {
    const patches = [];
    for (const i of component.cells) {
      lakeMask[i] = 1;
      const x = i % n, y = (i / n) | 0, p = worldAt(x, y);
      patches.push([+p[0].toFixed(1), +p[1].toFixed(1)]);
    }
    return {
      surfaceMeters: +component.surface.toFixed(2),
      maxDepthMeters: +component.maxDepth.toFixed(2),
      patches,
    };
  });
  return { lakes, lakeMask };
}

export function multiSourceDistance(mask, n, maxDistance = 255) {
  const dist = new Uint16Array(n * n);
  dist.fill(65535);
  const queue = new Int32Array(n * n);
  let head = 0, tail = 0;
  for (let i = 0; i < mask.length; i++) if (mask[i]) { dist[i] = 0; queue[tail++] = i; }
  while (head < tail) {
    const i = queue[head++], d = dist[i];
    if (d >= maxDistance) continue;
    const x = i % n, y = (i / n) | 0;
    for (const [dx, dy] of [[-1,0],[1,0],[0,-1],[0,1],[-1,-1],[1,-1],[-1,1],[1,1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= n || ny >= n) continue;
      const ni = ny * n + nx;
      if (dist[ni] > d + 1) { dist[ni] = d + 1; queue[tail++] = ni; }
    }
  }
  return dist;
}
