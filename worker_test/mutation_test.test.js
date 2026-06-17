import { generateMutants, OPERATORS } from '../tool/mutation_test.mjs';

describe('generateMutants', () => {
  test('covers relational, equality, logical and boolean operators', () => {
    const src = 'const a = x >= 1 && y === 2 || z <= 3; const t = true; const f = false;';
    const ops = generateMutants(src).map((m) => m.op);
    expect(ops).toEqual(expect.arrayContaining(['>=->>', '&&->||', '===->!==', '||->&&', '<=-><', 'true->false', 'false->true']));
  });

  test('each mutant changes exactly the targeted token', () => {
    const ms = generateMutants('a >= b');
    expect(ms.length).toBe(1);
    expect(ms[0].mutated).toBe('a > b');
    expect(ms[0].op).toBe('>=->>');
  });

  test('produces one mutant per occurrence', () => {
    expect(generateMutants('a && b && c').filter((m) => m.op === '&&->||').length).toBe(2);
  });

  test('respects --max', () => {
    expect(generateMutants('a && b && c && d', { max: 2 }).length).toBe(2);
  });

  test('reports 1-based line numbers and sorts by position', () => {
    const ms = generateMutants('line1\nx === y');
    expect(ms[0].line).toBe(2);
    for (let i = 1; i < ms.length; i++) expect(ms[i].index).toBeGreaterThanOrEqual(ms[i - 1].index);
  });

  test('handles empty / non-string input', () => {
    expect(generateMutants('')).toEqual([]);
    expect(generateMutants(null)).toEqual([]);
  });

  test('OPERATORS is a non-empty, well-formed set', () => {
    expect(OPERATORS.length).toBeGreaterThan(4);
    for (const o of OPERATORS) {
      expect(typeof o.name).toBe('string');
      expect(o.re).toBeInstanceOf(RegExp);
      expect(typeof o.to).toBe('string');
    }
  });
});
