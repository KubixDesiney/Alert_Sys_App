import {
  projectIdForOrder,
  tenantSlugFromCode,
  validatePaidOrder,
} from '../tool/provision_paid_order.mjs';

const order = (over = {}) => ({
  id: 42,
  tenant_code: 'NSW#7K2F',
  company: 'Nagati Steel Works',
  plan: 'growth',
  status: 'provisioning',
  pm_name: 'Sonia Trabelsi',
  pm_email: 'pm@nsw.tn',
  supervisor_name: 'Karim Aloui',
  supervisor_email: 'supervisor@nsw.tn',
  ...over,
});

describe('paid-order provisioning identity', () => {
  test('derives a stable DNS-safe tenant slug', () => {
    expect(tenantSlugFromCode('NSW#7K2F')).toBe('nsw-7k2f');
    expect(tenantSlugFromCode(' KBX-UC7L25 ')).toBe('kbx-uc7l25');
  });

  test('derives a globally safer deterministic GCP project id', () => {
    const id = projectIdForOrder('NSW#7K2F');
    expect(id).toMatch(/^sias-nsw-7k2f-[a-f0-9]{6}$/);
    expect(id.length).toBeLessThanOrEqual(30);
    expect(projectIdForOrder('NSW#7K2F')).toBe(id);
    expect(projectIdForOrder('NSW#DIFFERENT')).not.toBe(id);
  });

  test('accepts a complete provisioning order', () => {
    expect(validatePaidOrder(order(), 'NSW#7K2F')).toEqual([]);
  });

  test('rejects dispatch tampering, missing seats, and duplicate role emails', () => {
    const errors = validatePaidOrder(order({
      pm_name: '',
      supervisor_email: 'PM@NSW.TN',
    }), 'OTHER#1').join(' ');
    expect(errors).toMatch(/does not match/);
    expect(errors).toMatch(/pm_name/);
    expect(errors).toMatch(/must be different/);
  });

  test('refuses unpaid or already-reviewed states', () => {
    expect(validatePaidOrder(order({ status: 'confirmed' })).join(' '))
      .toMatch(/not provisionable/);
  });
});
