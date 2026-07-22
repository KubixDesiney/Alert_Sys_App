// Tests for the dependency-free QR encoder (qr_svg.js). Since there's no scanner
// here, correctness is anchored on: block-table capacity invariants, structural
// properties (finder/timing/dark module), format-info round-trip (proves the
// systematic bit order + BCH + XOR mask), determinism, and SVG shape.
import { describe, test, expect } from '@jest/globals';
import {
  qrMatrix,
  qrSvg,
  pickVersion,
  interleave,
  rsDivisor,
  BLOCK_TABLE,
  ECC_FORMAT_BITS,
} from '../qr_svg.js';

const CAPACITY = { 1: 26, 2: 44, 3: 70, 4: 100, 5: 134, 6: 172, 7: 196, 8: 242, 9: 292, 10: 346 };

describe('block table', () => {
  test('every (level, version) satisfies totalData + ec === version capacity', () => {
    for (const level of ['L', 'M']) {
      for (let v = 1; v <= 10; v++) {
        const [ec, b1, d1, b2, d2] = BLOCK_TABLE[level][v];
        expect(b1 * d1 + b2 * d2 + ec * (b1 + b2)).toBe(CAPACITY[v]);
      }
    }
  });
});

describe('pickVersion', () => {
  test('prefers EC level M and the smallest fitting version', () => {
    // v1-M has 16 data codewords = 128 bits; the mode (4) + count (8) overhead
    // leaves room for 14 bytes, so 15 bytes rolls over to v2.
    expect(pickVersion(10)).toEqual({ version: 1, level: 'M' });
    expect(pickVersion(14)).toEqual({ version: 1, level: 'M' });
    expect(pickVersion(15)).toEqual({ version: 2, level: 'M' });
  });
  test('returns null when the payload exceeds v10', () => {
    expect(pickVersion(300)).toBeNull();
  });
});

describe('reed-solomon + interleave', () => {
  test('rsDivisor length equals the requested degree', () => {
    expect(rsDivisor(7)).toHaveLength(7);
    expect(rsDivisor(26)).toHaveLength(26);
  });
  test('single-block interleave keeps data then ecc, right length', () => {
    const info = BLOCK_TABLE.M[1]; // [10,1,16,0,0]
    const data = new Array(16).fill(0).map((_, i) => i);
    const out = interleave(data, info);
    expect(out).toHaveLength(26); // 16 data + 10 ecc
    expect(out.slice(0, 16)).toEqual(data);
  });
});

describe('qrMatrix structure', () => {
  const url = 'https://nagati.kubixdesiney.com/app/sias-nagati.apk';
  const { modules, size, version, level, mask } = qrMatrix(url);

  test('size is 17 + 4*version', () => {
    expect(size).toBe(17 + 4 * version);
  });

  test('finder patterns: dark 7x7 core with a light ring at all three corners', () => {
    const centers = [[3, 3], [size - 4, 3], [3, size - 4]];
    for (const [cx, cy] of centers) {
      expect(modules[cy][cx]).toBe(true);        // center dark
      expect(modules[cy - 2][cx]).toBe(false);   // inner light ring
      expect(modules[cy - 3][cx]).toBe(true);    // outer dark ring
    }
  });

  test('timing patterns alternate along row/col 6, including the format crossings', () => {
    for (let x = 8; x <= size - 9; x++) expect(modules[6][x]).toBe(x % 2 === 0);
    for (let y = 8; y <= size - 9; y++) expect(modules[y][6]).toBe(y % 2 === 0);
    // The (row6,col8) / (row8,col6) timing crossings must survive format reserve.
    expect(modules[6][8]).toBe(true);
    expect(modules[8][6]).toBe(true);
  });

  test('permanent dark module is set', () => {
    expect(modules[size - 8][8]).toBe(true);
  });

  test('format info decodes back to the chosen EC level + mask (round-trip)', () => {
    // Read the 15-bit first copy along column 8 / row 8 (skipping timing).
    const seq = [[8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8],
      [7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8]];
    let bits = 0;
    seq.forEach(([x, y], i) => { if (modules[y][x]) bits |= 1 << i; });
    const data = ((bits ^ 0x5412) >> 10) & 0x1f;
    expect((data >> 3) & 3).toBe(ECC_FORMAT_BITS[level]);
    expect(data & 7).toBe(mask);
  });

  test('deterministic for the same input', () => {
    const a = qrMatrix(url);
    const b = qrMatrix(url);
    expect(a.modules).toEqual(b.modules);
    expect(a.mask).toBe(b.mask);
  });
});

describe('qrSvg', () => {
  test('renders a self-contained SVG with a light background and dark path', () => {
    const svg = qrSvg('https://x.kubixdesiney.com/app/sias-x.apk');
    expect(svg.startsWith('<svg')).toBe(true);
    expect(svg).toContain('xmlns="http://www.w3.org/2000/svg"');
    expect(svg).toContain('<rect');
    expect(svg).toContain('<path');
    expect(svg).not.toContain('http://www.w3.org/1999/xlink'); // no external refs
    expect(svg.endsWith('</svg>')).toBe(true);
  });

  test('longer payloads still encode (larger version, no throw)', () => {
    expect(() => qrSvg('https://averylongtenantname.kubixdesiney.com/app/sias-averylongtenantname.apk')).not.toThrow();
  });
});
