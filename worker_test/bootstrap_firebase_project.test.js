import {
  addIamBinding,
  databaseUrlForRegion,
  isValidProjectId,
  normalizeBillingAccount,
  serviceBatchBody,
  validateBootstrapFlags,
  webConfigFromApi,
} from '../tool/bootstrap_firebase_project.mjs';

describe('automatic Firebase project bootstrap', () => {
  test('accepts only stable GCP project ids', () => {
    expect(isValidProjectId('sias-nsw-7k2f')).toBe(true);
    expect(isValidProjectId('SIAS-NSW')).toBe(false);
    expect(isValidProjectId('ab')).toBe(false);
    expect(isValidProjectId('sias--tenant')).toBe(false);
  });

  test('validates the non-interactive bootstrap contract', () => {
    expect(validateBootstrapFlags({
      'project-id': 'sias-nsw-7k2f',
      tenant: 'nsw-7k2f',
      'output-dir': 'deploy/tenants/nsw-7k2f',
    })).toEqual([]);
    expect(validateBootstrapFlags({})).toHaveLength(3);
  });

  test('normalizes billing account resource names', () => {
    expect(normalizeBillingAccount('000AAA-111BBB-222CCC'))
      .toBe('billingAccounts/000AAA-111BBB-222CCC');
    expect(normalizeBillingAccount('billingAccounts/ABC')).toBe('billingAccounts/ABC');
  });

  test('uses the correct regional RTDB hostname', () => {
    expect(databaseUrlForRegion('sias-nsw', 'us-central1'))
      .toBe('https://sias-nsw-default-rtdb.firebaseio.com');
    expect(databaseUrlForRegion('sias-nsw', 'europe-west1'))
      .toBe('https://sias-nsw-default-rtdb.europe-west1.firebasedatabase.app');
  });

  test('enables every Firebase runtime API in one batch', () => {
    expect(serviceBatchBody('123').serviceIds).toEqual(expect.arrayContaining([
      'firebase.googleapis.com',
      'identitytoolkit.googleapis.com',
      'firebasedatabase.googleapis.com',
      'fcm.googleapis.com',
      'iam.googleapis.com',
    ]));
  });

  test('adds a tenant runtime IAM binding idempotently', () => {
    const member = 'serviceAccount:sias-runtime@sias-nsw.iam.gserviceaccount.com';
    const once = addIamBinding({ version: 1, bindings: [] }, 'roles/firebase.admin', member);
    const twice = addIamBinding(once, 'roles/firebase.admin', member);
    expect(twice.bindings[0].members).toEqual([member]);
    expect(twice.version).toBe(1);
  });

  test('writes the exact web configuration consumed by sias-app', () => {
    expect(webConfigFromApi({
      apiKey: 'api-key',
      appId: '1:123:web:abc',
      messagingSenderId: '123',
    }, 'sias-nsw', 'https://sias-nsw-default-rtdb.firebaseio.com')).toEqual({
      apiKey: 'api-key',
      authDomain: 'sias-nsw.firebaseapp.com',
      projectId: 'sias-nsw',
      storageBucket: 'sias-nsw.firebasestorage.app',
      messagingSenderId: '123',
      appId: '1:123:web:abc',
      databaseURL: 'https://sias-nsw-default-rtdb.firebaseio.com',
    });
  });
});
