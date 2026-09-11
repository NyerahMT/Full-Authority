export function hash2(x, y, seed) {
  let h = (Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263) + Math.imul(seed | 0, 1442695041)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

export function smootherstep(t) { return t * t * t * (t * (t * 6 - 15) + 10); }
export function smoothstep(edge0, edge1, x) {
  const t = Math.min(1, Math.max(0, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}
export function clamp01(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
export function lerp(a, b, t) { return a + (b - a) * t; }
export function mixColor(a, b, t) {
  const k = clamp01(t);
  return [lerp(a[0], b[0], k), lerp(a[1], b[1], k), lerp(a[2], b[2], k)];
}
export function scaleColor(color, scale) {
  return color.map((channel) => Math.max(0, Math.min(255, channel * scale)));
}

export class MinHeap {
  constructor() { this.values = []; this.indices = []; }
  get size() { return this.values.length; }
  push(value, index) {
    let i = this.values.length;
    this.values.push(value);
    this.indices.push(index);
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (this.values[p] <= value) break;
      this.values[i] = this.values[p];
      this.indices[i] = this.indices[p];
      i = p;
    }
    this.values[i] = value;
    this.indices[i] = index;
  }
  pop() {
    if (this.values.length === 0) return null;
    const value = this.values[0], index = this.indices[0];
    const lastValue = this.values.pop(), lastIndex = this.indices.pop();
    if (this.values.length > 0) {
      let i = 0;
      while (true) {
        let child = i * 2 + 1;
        if (child >= this.values.length) break;
        if (child + 1 < this.values.length && this.values[child + 1] < this.values[child]) child++;
        if (this.values[child] >= lastValue) break;
        this.values[i] = this.values[child];
        this.indices[i] = this.indices[child];
        i = child;
      }
      this.values[i] = lastValue;
      this.indices[i] = lastIndex;
    }
    return [value, index];
  }
}

export const DIRS = [
  [-1, -1, Math.SQRT2], [0, -1, 1], [1, -1, Math.SQRT2],
  [-1,  0, 1],                         [1,  0, 1],
  [-1,  1, Math.SQRT2], [0,  1, 1], [1,  1, Math.SQRT2],
];

export function rdp(points, tolerance) {
  if (points.length <= 2) return points;
  const a = points[0], b = points[points.length - 1];
  const vx = b[0] - a[0], vy = b[1] - a[1];
  const len2 = vx * vx + vy * vy;
  let maxD2 = -1, index = -1;
  for (let i = 1; i < points.length - 1; i++) {
    const px = points[i][0] - a[0], py = points[i][1] - a[1];
    let t = len2 > 0 ? (px * vx + py * vy) / len2 : 0;
    t = Math.max(0, Math.min(1, t));
    const dx = a[0] + vx * t - points[i][0];
    const dy = a[1] + vy * t - points[i][1];
    const d2 = dx * dx + dy * dy;
    if (d2 > maxD2) { maxD2 = d2; index = i; }
  }
  if (maxD2 > tolerance * tolerance) {
    const left = rdp(points.slice(0, index + 1), tolerance);
    const right = rdp(points.slice(index), tolerance);
    return left.slice(0, -1).concat(right);
  }
  return [a, b];
}
