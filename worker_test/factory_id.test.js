import { describe, test, expect } from '@jest/globals';
import { aiSanitizeFactoryId, aiResolveFactory } from '../cloudflare_worker.js';

describe('aiSanitizeFactoryId', () => {
  test('lowercases input', () => {
    expect(aiSanitizeFactoryId('USINE A')).toBe('usine_a');
  });

  test('replaces non-alphanumeric runs with underscore', () => {
    expect(aiSanitizeFactoryId('Usine-A.North/2')).toBe('usine_a_north_2');
  });

  test('trims leading and trailing underscores', () => {
    expect(aiSanitizeFactoryId('---factory---')).toBe('factory');
  });

  test('returns empty string for non-alpha input', () => {
    expect(aiSanitizeFactoryId('!!!')).toBe('');
  });

  test('preserves digits', () => {
    expect(aiSanitizeFactoryId('Plant 42')).toBe('plant_42');
  });

  test('null/undefined-safe', () => {
    expect(aiSanitizeFactoryId(null)).toBe('');
    expect(aiSanitizeFactoryId(undefined)).toBe('');
  });

  test('matches the Dart-side sanitizer semantics for round-trip ids', () => {
    // The Dart util in lib/utils/factory_id.dart applies the same algorithm.
    // Keep these in sync — the worker uses sanitized ids as Firebase keys.
    expect(aiSanitizeFactoryId('  Usine A  ')).toBe('usine_a');
    expect(aiSanitizeFactoryId('a__b')).toBe('a_b');
  });
});

describe('aiResolveFactory', () => {
  test('prefers factoryId over usine when both present', () => {
    expect(aiResolveFactory({ factoryId: 'main', usine: 'Other' })).toBe('main');
  });

  test('falls back to usine when factoryId is missing', () => {
    expect(aiResolveFactory({ usine: 'Usine B' })).toBe('usine_b');
  });

  test('returns null for null / non-object', () => {
    expect(aiResolveFactory(null)).toBeNull();
    expect(aiResolveFactory(undefined)).toBeNull();
    expect(aiResolveFactory('a string')).toBeNull();
  });

  test('returns null when both fields are blank', () => {
    expect(aiResolveFactory({ factoryId: '', usine: '' })).toBeNull();
    expect(aiResolveFactory({ factoryId: '   ', usine: '   ' })).toBeNull();
  });
});
