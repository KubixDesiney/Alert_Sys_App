// =============================================================================
// qr_svg.js — dependency-free QR Code generator that renders to inline SVG.
// =============================================================================
// Used by the sias-app worker's tenant APK download page (/app) so a supervisor
// can point their phone at the screen and install. Server-side SVG means it
// works under the app worker's strict, nonce-based CSP (no client-side script,
// no external CDN) and prints cleanly.
//
// This is a faithful, byte-mode-only port of Project Nayuki's public-domain QR
// Code generator (versions 1–10, EC levels L/M, all 8 data masks with penalty
// scoring). URLs like https://nagati.kubixdesiney.com/app/sias-nagati.apk sit
// comfortably inside version 3–4, and the ceiling of v10-L (~271 bytes) covers
// any realistic tenant hostname. Everything here is pure and unit-tested in
// worker_test/qr_svg.test.js; the download page also renders the raw URL and a
// copy button, so the page never depends on the QR alone.
// =============================================================================

// EC level → the 2 "format information" bits the QR spec assigns each level.
const ECC_FORMAT_BITS = { L: 1, M: 0, Q: 3, H: 2 };

// Per (EC level, version 1–10) block structure:
//   [ecCodewordsPerBlock, blocksGroup1, dataCwGroup1, blocksGroup2, dataCwGroup2]
// Verified against ISO/IEC 18004: for every entry
//   totalData = b1*d1 + b2*d2  and  totalData + ec*(b1+b2) === version capacity.
const BLOCK_TABLE = {
  L: {
    1: [7, 1, 19, 0, 0], 2: [10, 1, 34, 0, 0], 3: [15, 1, 55, 0, 0],
    4: [20, 1, 80, 0, 0], 5: [26, 1, 108, 0, 0], 6: [18, 2, 68, 0, 0],
    7: [20, 2, 78, 0, 0], 8: [24, 2, 97, 0, 0], 9: [30, 2, 116, 0, 0],
    10: [18, 2, 68, 2, 69],
  },
  M: {
    1: [10, 1, 16, 0, 0], 2: [16, 1, 28, 0, 0], 3: [26, 1, 44, 0, 0],
    4: [18, 2, 32, 0, 0], 5: [24, 2, 43, 0, 0], 6: [16, 4, 27, 0, 0],
    7: [18, 4, 31, 0, 0], 8: [22, 2, 38, 2, 39], 9: [22, 3, 36, 2, 37],
    10: [26, 4, 43, 1, 44],
  },
};

// Alignment-pattern centre coordinates per version (empty for v1).
const ALIGN_POSITIONS = {
  1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30], 6: [6, 34],
  7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50],
};

const MIN_VERSION = 1;
const MAX_VERSION = 10;

// --- GF(256) arithmetic (primitive polynomial 0x11d) -----------------------------
const GF_EXP = new Array(512);
const GF_LOG = new Array(256);
(function initGaloisField() {
  let x = 1;
  for (let i = 0; i < 255; i++) {
    GF_EXP[i] = x;
    GF_LOG[x] = i;
    x <<= 1;
    if (x & 0x100) x ^= 0x11d;
  }
  for (let i = 255; i < 512; i++) GF_EXP[i] = GF_EXP[i - 255];
})();

function gfMul(a, b) {
  if (a === 0 || b === 0) return 0;
  return GF_EXP[GF_LOG[a] + GF_LOG[b]];
}

// Reed–Solomon divisor polynomial (length === degree), per Nayuki.
export function rsDivisor(degree) {
  const result = new Array(degree).fill(0);
  result[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < degree; j++) {
      result[j] = gfMul(result[j], root);
      if (j + 1 < degree) result[j] ^= result[j + 1];
    }
    root = gfMul(root, 2);
  }
  return result;
}

function rsRemainder(data, divisor) {
  const result = new Array(divisor.length).fill(0);
  for (const b of data) {
    const factor = b ^ result[0];
    result.shift();
    result.push(0);
    for (let i = 0; i < divisor.length; i++) result[i] ^= gfMul(divisor[i], factor);
  }
  return result;
}

// --- Version selection -----------------------------------------------------------
function totalDataCodewords(info) {
  const [, nb1, db1, nb2, db2] = info;
  return nb1 * db1 + nb2 * db2;
}

function charCountBits(version) {
  return version < 10 ? 8 : 16; // byte mode: 8 bits for v1–9, 16 for v10–26
}

/** Smallest (version, ecLevel) that fits `byteLen` data bytes. Prefers stronger
 *  EC (M) and only falls back to L when M can't hold the payload. */
export function pickVersion(byteLen) {
  for (const level of ['M', 'L']) {
    for (let v = MIN_VERSION; v <= MAX_VERSION; v++) {
      const capacityBits = totalDataCodewords(BLOCK_TABLE[level][v]) * 8;
      const neededBits = 4 + charCountBits(v) + byteLen * 8;
      if (neededBits <= capacityBits) return { version: v, level };
    }
  }
  return null; // too long for v1–10
}

// --- Bitstream + codewords -------------------------------------------------------
function buildCodewords(bytes, version, level) {
  const info = BLOCK_TABLE[level][version];
  const capacity = totalDataCodewords(info);
  const bits = [];
  const push = (value, len) => { for (let i = len - 1; i >= 0; i--) bits.push((value >> i) & 1); };

  push(0b0100, 4);                    // byte mode indicator
  push(bytes.length, charCountBits(version));
  for (const b of bytes) push(b, 8);

  const capBits = capacity * 8;
  push(0, Math.min(4, capBits - bits.length)); // terminator
  while (bits.length % 8 !== 0) bits.push(0);   // pad to byte boundary

  const data = [];
  for (let i = 0; i < bits.length; i += 8) {
    let byte = 0;
    for (let j = 0; j < 8; j++) byte = (byte << 1) | bits[i + j];
    data.push(byte);
  }
  const pads = [0xec, 0x11];
  for (let p = 0; data.length < capacity; p++) data.push(pads[p % 2]);
  return interleave(data, info);
}

/** Splits data into blocks, appends per-block Reed–Solomon ECC, and interleaves. */
export function interleave(dataCodewords, info) {
  const [ecLen, nb1, db1, nb2, db2] = info;
  const divisor = rsDivisor(ecLen);
  const dataBlocks = [];
  const eccBlocks = [];
  const specs = [];
  for (let b = 0; b < nb1; b++) specs.push(db1);
  for (let b = 0; b < nb2; b++) specs.push(db2);

  let pos = 0;
  for (const len of specs) {
    const block = dataCodewords.slice(pos, pos + len);
    pos += len;
    dataBlocks.push(block);
    eccBlocks.push(rsRemainder(block, divisor));
  }

  const out = [];
  const maxData = Math.max(db1, db2 || 0);
  for (let i = 0; i < maxData; i++) {
    for (const block of dataBlocks) if (i < block.length) out.push(block[i]);
  }
  for (let i = 0; i < ecLen; i++) {
    for (const block of eccBlocks) out.push(block[i]);
  }
  return out;
}

// --- Matrix construction ---------------------------------------------------------
function makeGrid(size, fill) {
  return Array.from({ length: size }, () => new Array(size).fill(fill));
}

function drawFunctionPatterns(modules, isFn, version, size, level) {
  const set = (x, y, dark) => {
    if (x < 0 || y < 0 || x >= size || y >= size) return;
    modules[y][x] = dark;
    isFn[y][x] = true;
  };

  // Timing patterns (row/col 6).
  for (let i = 0; i < size; i++) {
    set(6, i, i % 2 === 0);
    set(i, 6, i % 2 === 0);
  }

  // Finder patterns + separators at three corners (9×9 stamps).
  const finder = (cx, cy) => {
    for (let dy = -4; dy <= 4; dy++) {
      for (let dx = -4; dx <= 4; dx++) {
        const dist = Math.max(Math.abs(dx), Math.abs(dy));
        set(cx + dx, cy + dy, dist !== 2 && dist !== 4);
      }
    }
  };
  finder(3, 3);
  finder(size - 4, 3);
  finder(3, size - 4);

  // Alignment patterns (skip the three that collide with finders).
  const pos = ALIGN_POSITIONS[version];
  for (let i = 0; i < pos.length; i++) {
    for (let j = 0; j < pos.length; j++) {
      const corner =
        (i === 0 && j === 0) ||
        (i === 0 && j === pos.length - 1) ||
        (i === pos.length - 1 && j === 0);
      if (corner) continue;
      const cx = pos[i];
      const cy = pos[j];
      for (let dy = -2; dy <= 2; dy++) {
        for (let dx = -2; dx <= 2; dx++) {
          set(cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
        }
      }
    }
  }

  // Reserve the format-info cells (exact positions only — the row-6/col-6
  // timing crossings are NOT format cells and must stay timing). A dummy mask
  // marks them as function so the data pass skips them; real bits land later.
  drawFormatBits(modules, isFn, size, level, 0);

  // Reserve version-info blocks (v ≥ 7).
  if (version >= 7) {
    for (let i = 0; i < 18; i++) {
      const a = size - 11 + (i % 3);
      const b = Math.floor(i / 3);
      set(a, b, false);
      set(b, a, false);
    }
  }
}

function drawCodewords(modules, isFn, size, codewords) {
  let i = 0; // bit index into the codeword stream
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5; // skip the timing column
    for (let vert = 0; vert < size; vert++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? size - 1 - vert : vert;
        if (!isFn[y][x] && i < codewords.length * 8) {
          modules[y][x] = ((codewords[i >> 3] >> (7 - (i & 7))) & 1) === 1;
          i++;
        }
      }
    }
  }
}

function maskCondition(mask, x, y) {
  switch (mask) {
    case 0: return (x + y) % 2 === 0;
    case 1: return y % 2 === 0;
    case 2: return x % 3 === 0;
    case 3: return (x + y) % 3 === 0;
    case 4: return (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0;
    case 5: return ((x * y) % 2) + ((x * y) % 3) === 0;
    case 6: return (((x * y) % 2) + ((x * y) % 3)) % 2 === 0;
    case 7: return (((x + y) % 2) + ((x * y) % 3)) % 2 === 0;
    default: return false;
  }
}

function applyMask(modules, isFn, size, mask) {
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (!isFn[y][x] && maskCondition(mask, x, y)) modules[y][x] = !modules[y][x];
    }
  }
}

function drawFormatBits(modules, isFn, size, level, mask) {
  const data = (ECC_FORMAT_BITS[level] << 3) | mask; // 5 bits
  let rem = data;
  for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >> 9) * 0x537);
  const bits = ((data << 10) | rem) ^ 0x5412; // 15-bit format string
  const put = (x, y, i) => { modules[y][x] = ((bits >> i) & 1) === 1; if (isFn) isFn[y][x] = true; };

  // First copy (top-left corner, around the finder).
  for (let i = 0; i <= 5; i++) put(8, i, i);
  put(8, 7, 6);
  put(8, 8, 7);
  put(7, 8, 8);
  for (let i = 9; i < 15; i++) put(14 - i, 8, i);

  // Second copy (split along the top-right and bottom-left finders).
  for (let i = 0; i < 8; i++) put(size - 1 - i, 8, i);
  for (let i = 8; i < 15; i++) put(8, size - 15 + i, i);

  modules[size - 8][8] = true; // permanent dark module
  if (isFn) isFn[size - 8][8] = true;
}

function drawVersionBits(modules, size, version) {
  if (version < 7) return;
  let rem = version;
  for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >> 11) * 0x1f25);
  const bits = (version << 12) | rem; // 18-bit version string
  for (let i = 0; i < 18; i++) {
    const on = ((bits >> i) & 1) === 1;
    const a = size - 11 + (i % 3);
    const b = Math.floor(i / 3);
    modules[b][a] = on;
    modules[a][b] = on;
  }
}

function penaltyScore(modules, size) {
  let penalty = 0;
  const N1 = 3, N2 = 3, N3 = 40, N4 = 10;

  // Rule 1: runs of ≥5 same-colour modules per row and column.
  for (let y = 0; y < size; y++) {
    let runColor = modules[y][0], runLen = 1;
    for (let x = 1; x < size; x++) {
      if (modules[y][x] === runColor) { runLen++; if (runLen === 5) penalty += N1; else if (runLen > 5) penalty++; }
      else { runColor = modules[y][x]; runLen = 1; }
    }
  }
  for (let x = 0; x < size; x++) {
    let runColor = modules[0][x], runLen = 1;
    for (let y = 1; y < size; y++) {
      if (modules[y][x] === runColor) { runLen++; if (runLen === 5) penalty += N1; else if (runLen > 5) penalty++; }
      else { runColor = modules[y][x]; runLen = 1; }
    }
  }

  // Rule 2: 2×2 blocks of one colour.
  for (let y = 0; y < size - 1; y++) {
    for (let x = 0; x < size - 1; x++) {
      const c = modules[y][x];
      if (c === modules[y][x + 1] && c === modules[y + 1][x] && c === modules[y + 1][x + 1]) penalty += N2;
    }
  }

  // Rule 3: finder-like 1:1:3:1:1 patterns (rows + columns).
  const hasPattern = (get) => {
    // dark-light-dark-dark-dark-light-dark with 4 light either side
    const p1 = [true, false, true, true, true, false, true, false, false, false, false];
    const p2 = [false, false, false, false, true, false, true, true, true, false, true];
    for (let i = 0; i <= size - 11; i++) {
      let m1 = true, m2 = true;
      for (let k = 0; k < 11; k++) {
        const v = get(i + k);
        if (v !== p1[k]) m1 = false;
        if (v !== p2[k]) m2 = false;
      }
      if (m1 || m2) penalty += N3;
    }
  };
  for (let y = 0; y < size; y++) hasPattern((i) => modules[y][i]);
  for (let x = 0; x < size; x++) hasPattern((i) => modules[i][x]);

  // Rule 4: overall dark/light balance.
  let dark = 0;
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) if (modules[y][x]) dark++;
  const total = size * size;
  const ratio = (dark * 100) / total;
  const k = Math.floor(Math.abs(ratio - 50) / 5);
  penalty += k * N4;
  return penalty;
}

/** Encodes `text` (UTF-8) into a QR module matrix (boolean[][], true = dark). */
export function qrMatrix(text) {
  const bytes = utf8Bytes(text);
  const chosen = pickVersion(bytes.length);
  if (!chosen) throw new Error(`QR payload too long (${bytes.length} bytes) for v1–10`);
  const { version, level } = chosen;
  const size = 17 + 4 * version;
  const codewords = buildCodewords(bytes, version, level);

  const modules = makeGrid(size, false);
  const isFn = makeGrid(size, false);
  drawFunctionPatterns(modules, isFn, version, size, level);
  drawCodewords(modules, isFn, size, codewords);
  drawVersionBits(modules, size, version);

  // Choose the mask with the lowest penalty (mask, score self-contained).
  let bestMask = 0, bestScore = Infinity;
  for (let mask = 0; mask < 8; mask++) {
    applyMask(modules, isFn, size, mask);
    drawFormatBits(modules, isFn, size, level, mask);
    const score = penaltyScore(modules, size);
    if (score < bestScore) { bestScore = score; bestMask = mask; }
    applyMask(modules, isFn, size, mask); // undo (XOR is its own inverse)
  }
  applyMask(modules, isFn, size, bestMask);
  drawFormatBits(modules, isFn, size, level, bestMask);

  return { modules, size, version, level, mask: bestMask };
}

function utf8Bytes(text) {
  return Array.from(new TextEncoder().encode(String(text)));
}

/**
 * Renders `text` as a standalone SVG QR code. `moduleSize` px per module,
 * `margin` quiet-zone modules (spec minimum 4). Dark modules only; the light
 * background is a single rect so it prints correctly.
 */
export function qrSvg(text, { moduleSize = 6, margin = 4, dark = '#0b1220', light = '#ffffff' } = {}) {
  const { modules, size } = qrMatrix(text);
  const dim = (size + margin * 2) * moduleSize;
  let path = '';
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (!modules[y][x]) continue;
      const px = (x + margin) * moduleSize;
      const py = (y + margin) * moduleSize;
      path += `M${px} ${py}h${moduleSize}v${moduleSize}h-${moduleSize}z`;
    }
  }
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${dim}" height="${dim}" ` +
    `viewBox="0 0 ${dim} ${dim}" role="img" aria-label="QR code">` +
    `<rect width="${dim}" height="${dim}" fill="${light}"/>` +
    `<path d="${path}" fill="${dark}"/>` +
    `</svg>`
  );
}

export { ECC_FORMAT_BITS, BLOCK_TABLE };
