import { buildTenantEnv, escapeEnvValue } from '../tool/build_tenant_env.mjs';
import { parseEnvFile } from '../tool/provision_instance.mjs';

describe('tenant worker secret bundle', () => {
  test('serializes the generated Firebase identity on one parseable line', () => {
    const serviceAccount = {
      type: 'service_account',
      project_id: 'sias-nsw',
      private_key: '-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----\n',
      client_email: 'sias-runtime@sias-nsw.iam.gserviceaccount.com',
    };
    const text = buildTenantEnv({
      firebaseServiceAccount: serviceAccount,
      firebaseApiKey: 'firebase-key',
      workerSharedSecret: 'shared-secret',
      githubToken: 'github-token',
      scimToken: 'scim-token',
      alertWebhookUrl: 'https://alerts.example/hook',
      ingestSharedSecret: 'ingest-secret',
    });
    const parsed = parseEnvFile(text);
    expect(JSON.parse(parsed.FIREBASE_SERVICE_ACCOUNT)).toEqual(serviceAccount);
    expect(parsed.FB_API_KEY).toBe('firebase-key');
    expect(parsed.INGEST_SHARED_SECRET).toBe('ingest-secret');
    expect(text).not.toContain('\nsecret\n');
  });

  test('fails before writing an incomplete worker bundle', () => {
    expect(() => buildTenantEnv({
      firebaseServiceAccount: {},
      firebaseApiKey: '',
      workerSharedSecret: '',
      githubToken: '',
      scimToken: '',
      alertWebhookUrl: '',
    })).toThrow(/missing tenant worker secrets/i);
  });

  test('strips real line breaks from scalar env values', () => {
    expect(escapeEnvValue('one\r\ntwo')).toBe('onetwo');
  });
});
