import fs from 'node:fs';
import zlib from 'node:zlib';

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function pngChunk(type, data) {
  const typeBytes = Buffer.from(type, 'ascii'), out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  typeBytes.copy(out, 4);
  data.copy(out, 8);
  out.writeUInt32BE(crc32(Buffer.concat([typeBytes, data])), 8 + data.length);
  return out;
}

export function writePNG(file, width, height, channels, data) {
  const rowBytes = width * channels, scan = Buffer.alloc((rowBytes + 1) * height);
  for (let y = 0; y < height; y++) {
    const row = y * (rowBytes + 1);
    scan[row] = 0;
    Buffer.from(data.buffer, data.byteOffset + y * rowBytes, rowBytes).copy(scan, row + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = channels === 3 ? 2 : 0;
  fs.writeFileSync(file, Buffer.concat([
    Buffer.from([137,80,78,71,13,10,26,10]),
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', zlib.deflateSync(scan, { level: 9 })),
    pngChunk('IEND', Buffer.alloc(0)),
  ]));
}

export function writeWaterNormalMap(file) {
  const size = 256, rgb = new Uint8Array(size * size * 3);
  const waves = [[3,1,.34,.2],[-2,5,.20,1.4],[7,3,.10,2.3],[5,-6,.07,4.1]];
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const u = x / size, v = y / size;
    let du = 0, dv = 0;
    for (const [fx, fy, a, p] of waves) {
      const angle = Math.PI * 2 * (fx * u + fy * v) + p;
      const c = Math.cos(angle) * Math.PI * 2 * a;
      du += c * fx; dv += c * fy;
    }
    let nx = -du * .020, ny = -dv * .020, nz = 1;
    const l = Math.hypot(nx, ny, nz) || 1;
    nx /= l; ny /= l; nz /= l;
    const o = (y * size + x) * 3;
    rgb[o] = Math.round((nx * .5 + .5) * 255);
    rgb[o + 1] = Math.round((ny * .5 + .5) * 255);
    rgb[o + 2] = Math.round((nz * .5 + .5) * 255);
  }
  writePNG(file, size, size, 3, rgb);
}
