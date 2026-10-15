// Convert a PNG to a white mask: every pixel becomes white (1, 1, 1) and its alpha is the
// average of the original R, G, B (scaled by the original alpha, so transparent pixels stay transparent).
// No dependencies: PNG is decoded/encoded with the built-in zlib.
//
// Usage: node tools/white_alpha.js <input.png> [output.png]     (default output: <input>_white.png)
//        node tools/white_alpha.js <dir> [outDir]               (every .png in dir; default: overwrite-free <name>_white.png)

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const CHANNELS = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }; // color type -> samples per pixel

function decode(buf) {
  if (!buf.subarray(0, 8).equals(SIGNATURE)) throw new Error("not a PNG file");
  let pos = 8, ihdr, palette, trns;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("ascii", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      ihdr = { width: data.readUInt32BE(0), height: data.readUInt32BE(4), depth: data[8], color: data[9], interlace: data[12] };
    } else if (type === "PLTE") palette = data;
    else if (type === "tRNS") trns = data;
    else if (type === "IDAT") idat.push(data);
    else if (type === "IEND") break;
    pos += 12 + len;
  }
  const { width, height, depth, color, interlace } = ihdr;
  if (interlace) throw new Error("interlaced PNG is not supported");
  const channels = CHANNELS[color];
  const bpp = Math.max(1, (channels * depth) >> 3); // bytes per pixel for filtering
  const stride = Math.ceil((width * channels * depth) / 8);
  const raw = zlib.inflateSync(Buffer.concat(idat));

  // Undo the per-row filters.
  const rows = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const cur = rows.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? rows.subarray((y - 1) * stride, y * stride) : Buffer.alloc(stride);
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      let p = 0;
      if (filter === 1) p = a;
      else if (filter === 2) p = b;
      else if (filter === 3) p = (a + b) >> 1;
      else if (filter === 4) {
        const pa = Math.abs(b - c), pb = Math.abs(a - c), pc = Math.abs(a + b - 2 * c);
        p = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      }
      cur[i] = (src[i] + p) & 255;
    }
  }

  // Expand to 8-bit RGBA.
  const max = (1 << depth) - 1;
  const sample = (row, i) => {
    if (depth === 8) return rows[row * stride + i];
    if (depth === 16) return rows[row * stride + i * 2]; // high byte
    const bit = i * depth;
    return (rows[row * stride + (bit >> 3)] >> (8 - depth - (bit & 7))) & max;
  };
  const to8 = (v) => (depth >= 8 ? v : Math.round((v * 255) / max));
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4, i = x * channels;
      let r, g, b, a = 255;
      if (color === 3) {
        const idx = sample(y, i);
        [r, g, b] = palette.subarray(idx * 3, idx * 3 + 3);
        if (trns && idx < trns.length) a = trns[idx];
      } else if (color === 0 || color === 4) {
        r = g = b = to8(sample(y, i));
        if (color === 4) a = to8(sample(y, i + 1));
      } else {
        r = to8(sample(y, i)); g = to8(sample(y, i + 1)); b = to8(sample(y, i + 2));
        if (color === 6) a = to8(sample(y, i + 3));
      }
      rgba[o] = r; rgba[o + 1] = g; rgba[o + 2] = b; rgba[o + 3] = a;
    }
  }
  return { width, height, rgba };
}

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  for (let k = 0; k < 8; k++) n = n & 1 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
  return n >>> 0;
});
function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, "ascii");
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

function encode({ width, height, rgba }) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 6; // 8-bit RGBA
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  return Buffer.concat([SIGNATURE, chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}

function whiteAlpha(img) {
  const p = img.rgba;
  for (let o = 0; o < p.length; o += 4) {
    const avg = (p[o] + p[o + 1] + p[o + 2]) / 3;
    p[o + 3] = Math.round((avg * p[o + 3]) / 255);
    p[o] = p[o + 1] = p[o + 2] = 255;
  }
  return img;
}

function convert(input, output) {
  fs.writeFileSync(output, encode(whiteAlpha(decode(fs.readFileSync(input)))));
  console.log(`${input} -> ${output}`);
}

const [input, output] = process.argv.slice(2);
if (!input) {
  console.error("usage: node white_alpha.js <input.png|dir> [output.png|outDir]");
  process.exit(1);
}
const suffixed = (file, dir) => path.join(dir, path.basename(file, path.extname(file)) + "_white.png");
if (fs.statSync(input).isDirectory()) {
  const outDir = output || input;
  fs.mkdirSync(outDir, { recursive: true });
  for (const name of fs.readdirSync(input)) {
    if (!/\.png$/i.test(name) || (!output && /_white\.png$/i.test(name))) continue;
    const file = path.join(input, name);
    convert(file, output ? path.join(outDir, name) : suffixed(file, outDir));
  }
} else {
  convert(input, output || suffixed(input, path.dirname(input)));
}
