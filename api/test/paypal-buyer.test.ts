import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { requireEmulator } from './emulator-guard.js';
import request from 'supertest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';
import { ApiError } from '../src/lib/errors.js';
import type { PayPalFetch } from '../src/paypal/client.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'wh-1',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-buyer-test', INTERNAL_TOKEN: 'reconcile-secret',
});

let db: Firestore;
beforeAll(async () => {
  await requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-buyer-test' });
  db = getFirestore();
});

function appWith(fetch: PayPalFetch = async () => ({})) {
  return createApp({
    env, db, paypal: fetch,
    transport: async () => ({ content: '{}' }),
    verify: async () => { throw new Error('buyers are not signed in'); },
  });
}

const completed = {
  id: 'PPORDER1',
  status: 'COMPLETED',
  purchase_units: [{ payments: { captures: [{ id: 'CAP-1', status: 'COMPLETED' }] } }],
};

async function seed(status: string, extra: Record<string, unknown> = {}) {
  await db.doc('sellers/seller-a').set({ displayName: "Ola's Bakehouse" });
  await db.doc('sellers/seller-a/orders/o1').set({
    id: 'o1',
    status,
    buyerName: 'Tade',
    buyerEmail: 'tade@example.com',
    paypalOrderId: 'PPORDER1',
    approvalUrl: 'https://www.sandbox.paypal.com/checkoutnow?token=PPORDER1',
    amountDueMinor: 4200,
    linkSentAt: Timestamp.fromMillis(Date.now() - 10 * 60 * 1000),
    ...extra,
  });
}

beforeEach(async () => {
  const sellers = await db.collection('sellers').listDocuments();
  await Promise.all(sellers.map((s) => db.recursiveDelete(s)));
});

describe('GET /v1/paypal/return', () => {
  it('thanks the buyer and names the shop, without marking the order paid', async () => {
    await seed('link_sent');
    const res = await request(appWith()).get('/v1/paypal/return').query({ token: 'PPORDER1', PayerID: 'PAYER' });

    expect(res.status).toBe(200);
    expect(res.type).toBe('text/html');
    expect(res.text).toContain('Thanks, payment sent to Ola&#39;s Bakehouse.');
    expect(res.text).toContain('You can close this page.');
    expect(res.text).not.toContain('It&#39;s paid.');
    expect(res.text).not.toContain('Tade');
    expect(res.text).not.toContain('tade@example.com');
    expect(res.text).not.toContain('4200');
    expect(res.text).not.toContain('PPORDER1');
    expect(res.text).not.toContain('PAYER');
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('link_sent');
    expect(stored.get('paidAt')).toBeUndefined();
  });

  it('escapes the shop name and says paid only when the order already is', async () => {
    await seed('paid', {});
    await db.doc('sellers/seller-a').set({ displayName: 'Tom & Jerry <bakery>' });
    const res = await request(appWith()).get('/v1/paypal/return').query({ token: 'PPORDER1' });

    expect(res.status).toBe(200);
    expect(res.text).toContain('Tom &amp; Jerry &lt;bakery&gt;');
    expect(res.text).not.toContain('<bakery>');
    expect(res.text).toContain('It&#39;s paid.');
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('paid');
  });

  it('still thanks the buyer when the token matches nothing', async () => {
    const res = await request(appWith()).get('/v1/paypal/return').query({ token: '<script>' });
    expect(res.status).toBe(200);
    expect(res.text).toContain('Thanks, payment sent.');
    expect(res.text).not.toContain('<script');
    expect(res.text).not.toContain('Ola');
  });
});

describe('GET /v1/paypal/cancel', () => {
  it('says the payment was cancelled and changes nothing', async () => {
    await seed('link_sent');
    const res = await request(appWith()).get('/v1/paypal/cancel').query({ token: 'PPORDER1' });

    expect(res.status).toBe(200);
    expect(res.text).toContain('Payment cancelled.');
    expect(res.text).toContain('Nothing was charged.');
    expect(res.text).not.toContain('PPORDER1');
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('link_sent');
  });
});

describe('POST /v1/internal/workflows/reconcile', () => {
  it('refuses a call without the internal token', async () => {
    await seed('link_sent');
    const open = await request(appWith()).post('/v1/internal/workflows/reconcile');
    const wrong = await request(appWith())
      .post('/v1/internal/workflows/reconcile')
      .set('X-Internal-Token', 'nope');
    expect(open.status).toBe(401);
    expect(wrong.status).toBe(401);
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('link_sent');
  });

  it('marks a completed PayPal capture paid when the webhook never arrived', async () => {
    await seed('link_sent');
    const calls: string[] = [];
    const fetch: PayPalFetch = async (path) => {
      calls.push(path);
      return completed;
    };
    const res = await request(appWith(fetch))
      .post('/v1/internal/workflows/reconcile')
      .set('X-Internal-Token', 'reconcile-secret');

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ checked: 1, promoted: 1, failed: 0 });
    expect(calls.some((p) => p.endsWith('/capture'))).toBe(false);
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('paid');
    expect(stored.get('paypalCaptureId')).toBe('CAP-1');
    expect(stored.get('paidAt')).toBeTruthy();
    const payment = await db.doc('sellers/seller-a/orders/o1/paymentEvents/reconcile-o1').get();
    expect(JSON.stringify(payment.data())).not.toContain('tade@example.com');
    expect(payment.get('signatureVerified')).toBe(false);
  });

  it('captures an approved order and then marks that capture paid', async () => {
    await seed('link_sent');
    const calls: string[] = [];
    const fetch: PayPalFetch = async (path, init) => {
      calls.push(`${init.method} ${path}`);
      if (path.endsWith('/capture')) return completed;
      return { id: 'PPORDER1', status: 'APPROVED', purchase_units: [{ custom_id: 'seller-a:o1' }] };
    };
    const res = await request(appWith(fetch))
      .post('/v1/internal/workflows/reconcile')
      .set('X-Internal-Token', 'reconcile-secret');

    expect(res.status).toBe(200);
    expect(res.body.promoted).toBe(1);
    expect(calls).toContain('POST /v2/checkout/orders/PPORDER1/capture');
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('paid');
  });

  it('leaves a link that is only a minute old', async () => {
    await seed('link_sent', { linkSentAt: Timestamp.fromMillis(Date.now() - 30_000) });
    const fetch: PayPalFetch = async () => {
      throw new Error('should not ask PayPal');
    };
    const res = await request(appWith(fetch))
      .post('/v1/internal/workflows/reconcile')
      .set('X-Internal-Token', 'reconcile-secret');

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ checked: 0, promoted: 0, failed: 0 });
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('link_sent');
  });

  it('keeps going when one PayPal order cannot be read', async () => {
    await seed('link_sent');
    await db.doc('sellers/seller-a/orders/o2').set({
      id: 'o2',
      status: 'processing',
      paypalOrderId: 'PP-BAD',
      linkSentAt: Timestamp.fromMillis(Date.now() - 10 * 60 * 1000),
    });
    const fetch: PayPalFetch = async (path) => {
      if (path.includes('PP-BAD')) {
        throw new ApiError(502, 'PAYPAL_UNAVAILABLE', 'down', { status: 500, detail: 'INTERNAL_SERVER_ERROR' });
      }
      return completed;
    };
    const res = await request(appWith(fetch))
      .post('/v1/internal/workflows/reconcile')
      .set('X-Internal-Token', 'reconcile-secret');

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ checked: 2, promoted: 1, failed: 1 });
    expect((await db.doc('sellers/seller-a/orders/o1').get()).get('status')).toBe('paid');
    expect((await db.doc('sellers/seller-a/orders/o2').get()).get('status')).toBe('processing');
  });
});
