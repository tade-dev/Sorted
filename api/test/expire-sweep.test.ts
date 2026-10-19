import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { requireEmulator } from './emulator-guard.js';
import request from 'supertest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';
import { ApiError } from '../src/lib/errors.js';
import { expiryDueMs } from '../src/domain/closing.js';
import type { PayPalFetch } from '../src/paypal/client.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const base = {
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-expiry-test', INTERNAL_TOKEN: 'sweep-secret',
};

let db: Firestore;
beforeAll(async () => {
  await requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-expiry-test' });
  db = getFirestore();
});

const HOUR = 60 * 60 * 1000;
const unapproved = { id: 'PP-1', status: 'PAYER_ACTION_REQUIRED', purchase_units: [] };

function paypal(body: unknown = unapproved): { fetch: PayPalFetch; calls: string[] } {
  const calls: string[] = [];
  const fetch: PayPalFetch = async (path, init) => {
    calls.push(`${init.method} ${path}`);
    return body;
  };
  return { fetch, calls };
}

function appWith(fetch: PayPalFetch = paypal().fetch, extraEnv: Record<string, string> = {}) {
  return createApp({
    env: loadEnv({ ...base, ...extraEnv }), db, paypal: fetch,
    transport: async () => ({ content: '{}' }),
    verify: async () => { throw new Error('the sweep is not a seller'); },
  });
}

async function seed(id: string, status: string, sentHoursAgo: number | null, extra: Record<string, unknown> = {}) {
  await db.doc('sellers/seller-a').set({ displayName: "Ola's Bakehouse" });
  await db.doc(`sellers/seller-a/orders/${id}`).set({
    id,
    status,
    paypalOrderId: `PP-${id}`,
    approvalUrl: `https://www.sandbox.paypal.com/checkoutnow?token=PP-${id}`,
    amountDueMinor: 4200,
    linkSentAt: sentHoursAgo === null ? null : Timestamp.fromMillis(Date.now() - sentHoursAgo * HOUR),
    ...extra,
  });
}

function sweep(app: ReturnType<typeof appWith>, token = 'sweep-secret') {
  return request(app).post('/v1/internal/workflows/expire-sweep').set('X-Internal-Token', token);
}

const statusOf = async (id: string) => (await db.doc(`sellers/seller-a/orders/${id}`).get()).get('status');

beforeEach(async () => {
  const sellers = await db.collection('sellers').listDocuments();
  await Promise.all(sellers.map((s) => db.recursiveDelete(s)));
});

describe('expiryDueMs', () => {
  it('counts from when the link was sent', () => {
    expect(expiryDueMs(Timestamp.fromMillis(1_000), 2)).toBe(1_000 + 2 * HOUR);
  });

  it('has nothing to count from on a link never sent', () => {
    expect(expiryDueMs(null, 168)).toBeNull();
    expect(expiryDueMs('yesterday', 168)).toBeNull();
  });
});

describe('POST /v1/internal/workflows/expire-sweep', () => {
  it('refuses a call without the internal token', async () => {
    await seed('o1', 'link_sent', 200);
    const open = await request(appWith()).post('/v1/internal/workflows/expire-sweep');
    const wrong = await sweep(appWith(), 'nope');
    expect(open.status).toBe(401);
    expect(wrong.status).toBe(401);
    expect(await statusOf('o1')).toBe('link_sent');
  });

  it('expires an unpaid link older than seven days, once PayPal confirms it is unpaid', async () => {
    await seed('o1', 'link_sent', 169);
    const { fetch, calls } = paypal();
    const res = await sweep(appWith(fetch));

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ scanned: 1, expired: 1, kept: 0, failed: 0 });
    expect(calls).toEqual(['GET /v2/checkout/orders/PP-o1']);
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('expired');
    expect(stored.get('expiredAt')).toBeTruthy();
    expect(stored.get('supersededPaypalOrderIds')).toEqual(['PP-o1']);
    const event = await db.doc('sellers/seller-a/orders/o1/paymentEvents/expire-o1').get();
    expect(event.get('eventType')).toBe('expired');
    expect(event.get('raw')).toEqual({ source: 'expiry_sweep', status: 'expired', from: 'link_sent' });
  });

  it('leaves a link younger than the TTL without asking PayPal', async () => {
    await seed('o1', 'link_sent', 167);
    const { fetch, calls } = paypal();
    const res = await sweep(appWith(fetch));

    expect(res.body).toEqual({ scanned: 0, expired: 0, kept: 0, failed: 0 });
    expect(calls).toEqual([]);
    expect(await statusOf('o1')).toBe('link_sent');
  });

  it('follows ORDER_EXPIRY_HOURS', async () => {
    await seed('o1', 'link_sent', 3);
    const res = await sweep(appWith(paypal().fetch, { ORDER_EXPIRY_HOURS: '2' }));
    expect(res.body.expired).toBe(1);
    expect(await statusOf('o1')).toBe('expired');
  });

  it('expires a declined order the buyer never retried', async () => {
    await seed('o1', 'declined', 200);
    const res = await sweep(appWith());
    expect(res.body.expired).toBe(1);
    expect(await statusOf('o1')).toBe('expired');
  });

  it('marks a missed payment paid instead of expiring it', async () => {
    await seed('o1', 'link_sent', 200);
    const completed = {
      id: 'PP-o1',
      status: 'COMPLETED',
      purchase_units: [{ payments: { captures: [{ id: 'CAP-1', status: 'COMPLETED' }] } }],
    };
    const res = await sweep(appWith(paypal(completed).fetch));

    expect(res.body).toEqual({ scanned: 1, expired: 0, kept: 1, failed: 0 });
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('paid');
    expect(stored.get('supersededPaypalOrderIds')).toBeUndefined();
  });

  it('leaves an order for the next run when PayPal cannot be asked', async () => {
    await seed('o1', 'link_sent', 200);
    await seed('o2', 'link_sent', 200);
    const fetch: PayPalFetch = async (path) => {
      if (path.includes('PP-o1')) {
        throw new ApiError(502, 'PAYPAL_UNAVAILABLE', 'down', { status: 500, detail: 'INTERNAL_SERVER_ERROR' });
      }
      return unapproved;
    };
    const res = await sweep(appWith(fetch));

    expect(res.body).toEqual({ scanned: 2, expired: 1, kept: 0, failed: 1 });
    expect(await statusOf('o1')).toBe('link_sent');
    expect(await statusOf('o2')).toBe('expired');
  });

  it('never touches paid, draft, in-flight or already-closed orders', async () => {
    await seed('paid', 'paid', 400, { paidAt: Timestamp.now() });
    await seed('draft', 'draft', null);
    await seed('processing', 'processing', 400);
    await seed('pending', 'pending', 400);
    await seed('cancelled', 'cancelled', 400);
    const { fetch, calls } = paypal();
    const res = await sweep(appWith(fetch));

    expect(res.body).toEqual({ scanned: 0, expired: 0, kept: 0, failed: 0 });
    expect(calls).toEqual([]);
    for (const id of ['paid', 'draft', 'processing', 'pending', 'cancelled']) {
      expect(await statusOf(id)).toBe(id);
    }
  });

  it('expires an old link with no PayPal order without calling PayPal', async () => {
    await seed('o1', 'link_sent', 200, { paypalOrderId: null });
    const { fetch, calls } = paypal();
    const res = await sweep(appWith(fetch));
    expect(res.body.expired).toBe(1);
    expect(calls).toEqual([]);
  });

  it('is a no-op the second time round', async () => {
    await seed('o1', 'link_sent', 200);
    const app = appWith();
    await sweep(app);
    const again = await sweep(app);
    expect(again.body).toEqual({ scanned: 0, expired: 0, kept: 0, failed: 0 });
    const events = await db.collection('sellers/seller-a/orders/o1/paymentEvents').get();
    expect(events.docs.map((d) => d.id)).toEqual(['expire-o1']);
  });
});
