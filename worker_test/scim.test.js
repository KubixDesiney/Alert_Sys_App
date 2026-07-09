import {
  emailKey,
  grantableRoles,
  scimToRecord,
  recordToScim,
  parseFilter,
  applyPatch,
  timingSafeEqual,
  scimRateLimit,
  scimAuthLogThrottle,
  writeUser,
} from '../cloudflare_scim_worker.js';

const ENTERPRISE = 'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User';

describe('emailKey', () => {
  test('lowercases and sanitizes RTDB-unsafe chars', () => {
    expect(emailKey('A.B@Co.com')).toBe('a_b@co_com');
    expect(emailKey(' user#1$/x[y] ')).toBe('user_1__x_y_');
  });
  test('handles empty/nullish', () => {
    expect(emailKey('')).toBe('');
    expect(emailKey(undefined)).toBe('');
  });
});

describe('grantableRoles', () => {
  test('defaults to admin,supervisor', () => {
    expect(grantableRoles({})).toEqual(['admin', 'supervisor']);
  });
  test('honours env CSV override', () => {
    expect(grantableRoles({ SCIM_GRANTABLE_ROLES: 'admin, supervisor, viewer' }))
      .toEqual(['admin', 'supervisor', 'viewer']);
  });
});

describe('scimToRecord', () => {
  test('maps core fields from userName/emails/name', () => {
    const rec = scimToRecord({
      userName: 'jane@acme.com',
      name: { givenName: 'Jane', familyName: 'Doe' },
      emails: [{ value: 'jane@acme.com', primary: true }],
      externalId: 'ext-1',
    }, {});
    expect(rec.email).toBe('jane@acme.com');
    expect(rec.firstName).toBe('Jane');
    expect(rec.lastName).toBe('Doe');
    expect(rec.externalId).toBe('ext-1');
    expect(rec.active).toBe(true); // active omitted => true
    expect(rec.role).toBe('supervisor'); // default
  });

  test('active:false is preserved', () => {
    const rec = scimToRecord({ userName: 'x@y.com', active: false }, {});
    expect(rec.active).toBe(false);
  });

  test('clamps role to the grantable set (cannot escalate to superadmin)', () => {
    const rec = scimToRecord({ userName: 'x@y.com', role: 'superadmin' }, {});
    expect(rec.role).toBe('supervisor'); // falls back to default
  });

  test('honours an explicit grantable role', () => {
    const rec = scimToRecord({ userName: 'x@y.com', role: 'admin' }, {});
    expect(rec.role).toBe('admin');
  });

  test('reads role/factory from the enterprise extension', () => {
    const rec = scimToRecord({
      userName: 'x@y.com',
      [ENTERPRISE]: { department: 'admin', division: 'Plant 2' },
    }, {});
    expect(rec.role).toBe('admin');
    expect(rec.factory).toBe('Plant 2');
  });

  test('uses primary email when userName differs', () => {
    const rec = scimToRecord({
      userName: 'login-id',
      emails: [
        { value: 'secondary@y.com' },
        { value: 'primary@y.com', primary: true },
      ],
    }, {});
    expect(rec.email).toBe('primary@y.com');
  });
});

describe('recordToScim', () => {
  test('renders a valid SCIM User', () => {
    const u = recordToScim('id-1', {
      email: 'jane@acme.com', firstName: 'Jane', lastName: 'Doe',
      active: true, externalId: 'ext-1',
    }, 'https://w/scim/v2/Users/id-1');
    expect(u.schemas).toContain('urn:ietf:params:scim:schemas:core:2.0:User');
    expect(u.id).toBe('id-1');
    expect(u.userName).toBe('jane@acme.com');
    expect(u.emails[0]).toEqual({ value: 'jane@acme.com', primary: true });
    expect(u.active).toBe(true);
    expect(u.meta.resourceType).toBe('User');
    expect(u.meta.location).toBe('https://w/scim/v2/Users/id-1');
  });
});

describe('parseFilter', () => {
  test('parses userName eq', () => {
    expect(parseFilter('userName eq "x@y.com"')).toEqual({ attr: 'username', value: 'x@y.com' });
  });
  test('parses emails.value eq', () => {
    expect(parseFilter('emails.value eq "a@b.com"')).toEqual({ attr: 'emails.value', value: 'a@b.com' });
  });
  test('returns null for unsupported filters', () => {
    expect(parseFilter('active eq true')).toBeNull();
    expect(parseFilter('')).toBeNull();
    expect(parseFilter(null)).toBeNull();
  });
});

describe('applyPatch', () => {
  const base = { email: 'x@y.com', firstName: 'X', lastName: 'Y', active: true, role: 'supervisor' };

  test('deactivates via path=active (Okta style)', () => {
    const out = applyPatch(base, {
      Operations: [{ op: 'replace', path: 'active', value: false }],
    });
    expect(out.active).toBe(false);
    expect(out.role).toBe('supervisor'); // unrelated fields untouched
  });

  test('deactivates via pathless object value (Azure style)', () => {
    const out = applyPatch(base, {
      Operations: [{ op: 'Replace', value: { active: false } }],
    });
    expect(out.active).toBe(false);
  });

  test('updates name', () => {
    const out = applyPatch(base, {
      Operations: [{ op: 'replace', path: 'name.givenName', value: 'Zed' }],
    });
    expect(out.firstName).toBe('Zed');
  });

  test('string "true" is treated as active', () => {
    const out = applyPatch({ ...base, active: false }, {
      Operations: [{ op: 'replace', path: 'active', value: 'true' }],
    });
    expect(out.active).toBe(true);
  });

  test('never mutates the input record', () => {
    const snapshot = JSON.stringify(base);
    applyPatch(base, { Operations: [{ op: 'replace', path: 'active', value: false }] });
    expect(JSON.stringify(base)).toBe(snapshot);
  });
});


describe('timingSafeEqual', () => {
  test('true only for identical strings', () => {
    expect(timingSafeEqual('secret-token', 'secret-token')).toBe(true);
  });
  test('false for different content or length', () => {
    expect(timingSafeEqual('secret-token', 'secret-tokenX')).toBe(false);
    expect(timingSafeEqual('abc', 'abd')).toBe(false);
    expect(timingSafeEqual('', 'x')).toBe(false);
    expect(timingSafeEqual(undefined, '')).toBe(true);
  });
});

describe('scimRateLimit', () => {
  test('allows up to the limit then blocks within the window', () => {
    const b = new Map();
    let last;
    for (let i = 0; i < 3; i++) last = scimRateLimit(b, 'ip1', 3, 60000, 1000 + i);
    expect(last.allowed).toBe(true);
    expect(scimRateLimit(b, 'ip1', 3, 60000, 1003).allowed).toBe(false);
  });
  test('window slides so old hits expire', () => {
    const b = new Map();
    scimRateLimit(b, 'ip2', 1, 1000, 0);
    expect(scimRateLimit(b, 'ip2', 1, 1000, 500).allowed).toBe(false);
    expect(scimRateLimit(b, 'ip2', 1, 1000, 2000).allowed).toBe(true);
  });
  test('keys are independent', () => {
    const b = new Map();
    scimRateLimit(b, 'a', 1, 60000, 0);
    expect(scimRateLimit(b, 'b', 1, 60000, 0).allowed).toBe(true);
  });
});


describe('scimAuthLogThrottle', () => {
  test('allows first write, blocks within the gap, allows after it', () => {
    expect(scimAuthLogThrottle(0, 5000, 5000)).toBe(true);
    expect(scimAuthLogThrottle(5000, 7000, 5000)).toBe(false);
    expect(scimAuthLogThrottle(5000, 10000, 5000)).toBe(true);
  });
});


describe('writeUser retires stale provisioning keys on email change', () => {
  const ENV = { FB_DB_URL: 'https://db.example' };
  let calls;
  beforeEach(() => {
    calls = [];
    globalThis.fetch = async (url, opts = {}) => {
      const method = (opts.method || 'GET').toUpperCase();
      calls.push({
        url: String(url),
        method,
        body: opts.body != null ? JSON.parse(opts.body) : undefined,
      });
      // GET (e.g. provisioning/{key}/uid live-account lookup) → no linked uid.
      if (method === 'GET') return { ok: true, json: async () => null };
      return { ok: true, json: async () => ({}) };
    };
  });

  test('deletes provisioning/{oldKey} + scim/byUserName/{oldKey} and writes the new keys', async () => {
    await writeUser(
      ENV, 'tok', 'id1',
      { email: 'new@acme.com', role: 'supervisor', active: true },
      'old@acme.com',
    );
    const oldKey = emailKey('old@acme.com');
    const newKey = emailKey('new@acme.com');
    const puts = calls.filter((c) => c.method === 'PUT');
    // Old authorization keys retired (PUT null == delete).
    expect(puts.some((c) => c.url.includes(`provisioning/${oldKey}.json`) && c.body === null)).toBe(true);
    expect(puts.some((c) => c.url.includes(`scim/byUserName/${oldKey}.json`) && c.body === null)).toBe(true);
    // New keys written.
    expect(puts.some((c) => c.url.includes(`scim/byUserName/${newKey}.json`) && c.body === 'id1')).toBe(true);
    expect(puts.some((c) => c.url.includes(`provisioning/${newKey}.json`) && c.body && c.body.email === 'new@acme.com')).toBe(true);
  });

  test('does not delete anything when the email is unchanged', async () => {
    await writeUser(
      ENV, 'tok', 'id1',
      { email: 'same@acme.com', role: 'supervisor', active: true },
      'same@acme.com',
    );
    const key = emailKey('same@acme.com');
    const puts = calls.filter((c) => c.method === 'PUT');
    expect(puts.some((c) => c.body === null)).toBe(false);
    expect(puts.some((c) => c.url.includes(`provisioning/${key}.json`) && c.body && c.body.email === 'same@acme.com')).toBe(true);
  });
});
