import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { requireEmulator } from './emulator-guard.js';
import request from 'supertest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';
import type { PayPalFetch } from '../src/paypal/client.js';
import type { OrderStatus } from '../src/domain/orders.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'wh-1',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-webhook-test', INTERNAL_TOKEN: 't',
});

let db: Firestore;
beforeAll(async () => {
  await requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-webhook-test' });
  db = getFirestore();
});

const HEADERS = {
  'paypal-transmission-id': 'tid',
  'paypal-transmission-time': '2026-10-11T12:00:00Z',
  'paypal-cert-url': 'https://example.test/cert',
  'paypal-auth-algo': 'SHA256withRSA',
  'paypal-transmission-sig': 'sig',
};

type Call = { path: string; requestId?: string; rawBody?: string };

function paypal(opts: { verified?: boolean; captureStatus?: string } = {}): { fetch: PayPalFetch; calls: Call[] } {
  const calls: Call[] = [];
  const fetch: PayPalFetch = async (path, init) => {
    calls.push({ path, requestId: init.requestId, rawBody: init.rawBody });
    if (path.includes('verify-webhook-signature')) {
      return { verification_status: opts.verified === false ? 'FAILURE' : 'SUCCESS' };
    }
    if (path.endsWith('/capture')) {
      const status = opts.captureStatus ?? 'COMPLETED';
      return {
        id: 'PP-1',
        status,
        purchase_units: [{ payments: { captures: [{ id: 'CAP-1', status }] } }],
      };
    }
    return {
      id: 'PP-1',
      status: 'COMPLETED',
      purchase_units: [{ payments: { captures: [{ id: 'CAP-1', status: 'COMPLETED' }] } }],
    };
  };
  return { fetch, calls };
}

function appWith(fetch: PayPalFetch) {
  return createApp({
    env, db, paypal: fetch,
    transport: async () => ({ content: '{}' }),
    verify: async () => { throw new Error('webhooks are not authenticated as a seller'); },
  });
}

function event(eventType: string, id: string, resource: unknown): string {
  return JSON.stringify({ id, event_type: eventType, resource });
}

const approved = () => event('CHECKOUT.ORDER.APPROVED', 'WH-APPROVED', {
  id: 'PP-1',
  purchase_units: [{ custom_id: 'seller-a:o1' }],
});

async function seed(status: OrderStatus = 'link_sent') {
  await db.doc('sellers/seller-a/orders/o1').set({
    id: 'o1',
    status,
    buyerName: 'Tade',
    paypalOrderId: 'PP-1',
    approvalUrl: 'https://www.sandbox.paypal.com/checkoutnow?token=PP-1',
    amountDueMinor: 4200,
  });
}

async function post(app: ReturnType<typeof appWith>, raw: string) {
  const req = request(app).post('/v1/webhooks/paypal').set('Content-Type', 'application/json');
  for (const [name, value] of Object.entries(HEADERS)) req.set(name, value);
  return req.send(raw);
}

beforeEach(async () => {
  const sellers = await db.collection('sellers').listDocuments();
  await Promise.all(sellers.map((s) => db.recursiveDelete(s)));
  const events = await db.collection('webhookEvents').listDocuments();
  await Promise.all(events.map((e) => e.delete()));
});

describe('POST /v1/webhooks/paypal', () => {
  it('rejects an event PayPal does not verify', async () => {
    await seed();
    const { fetch, calls } = paypal({ verified: false });
    const before = await request(appWith(fetch)).get('/v1/health');

    const res = await post(appWith(fetch), approved());

    expect(res.status).toBe(401);
    expect(calls.some((c) => c.path.endsWith('/capture'))).toBe(false);
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('link_sent');
    const ledger = await db.collection('webhookEvents').get();
    expect(ledger.empty).toBe(true);
    const after = await request(appWith(fetch)).get('/v1/health');
    expect(after.body.webhookFailures).toBe(before.body.webhookFailures + 1);
  });

  it('captures an approved order and does not mark it paid', async () => {
    await seed();
    const { fetch, calls } = paypal();
    const raw = approved();
    const res = await post(appWith(fetch), raw);

    expect(res.status).toBe(200);
    const capture = calls.find((c) => c.path.endsWith('/capture'));
    expect(capture?.path).toBe('/v2/checkout/orders/PP-1/capture');
    expect(capture?.requestId).toBe('capture-o1');
    const verify = calls.find((c) => c.path.includes('verify-webhook-signature'));
    expect(verify?.rawBody).toContain(`"webhook_event":${raw}`);

    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('processing');
    expect(stored.get('paypalCaptureId')).toBe('CAP-1');
    expect(stored.get('paidAt')).toBeUndefined();
  });

  it('ignores a duplicate event', async () => {
    await seed();
    const { fetch, calls } = paypal();
    const app = appWith(fetch);
    const raw = approved();

    expect((await post(app, raw)).status).toBe(200);
    expect((await post(app, raw)).status).toBe(200);
    expect(calls.filter((c) => c.path.endsWith('/capture'))).toHaveLength(1);
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('processing');
  });

  it('marks the order paid only when the capture completes', async () => {
    await seed('processing');
    const { fetch, calls } = paypal();
    const res = await post(appWith(fetch), event('PAYMENT.CAPTURE.COMPLETED', 'WH-PAID', {
      id: 'CAP-1',
      status: 'COMPLETED',
      custom_id: 'seller-a:o1',
      amount: { currency_code: 'GBP', value: '42.00' },
      supplementary_data: { related_ids: { order_id: 'PP-1' } },
    }));

    expect(res.status).toBe(200);
    expect(calls.some((c) => c.path.endsWith('/capture'))).toBe(false);
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('paid');
    expect(stored.get('paypalCaptureId')).toBe('CAP-1');
    expect(stored.get('paidAt')).toBeTruthy();
    const payment = await db.doc('sellers/seller-a/orders/o1/paymentEvents/WH-PAID').get();
    expect(payment.get('amountMinor')).toBe(4200);
    expect(payment.get('signatureVerified')).toBe(true);
  });

  it('finds the order by the stored PayPal id when custom_id is absent', async () => {
    await seed('processing');
    const { fetch } = paypal();
    const res = await post(appWith(fetch), event('PAYMENT.CAPTURE.COMPLETED', 'WH-LOOKUP', {
      id: 'CAP-9',
      status: 'COMPLETED',
      supplementary_data: { related_ids: { order_id: 'PP-1' } },
    }));
    expect(res.status).toBe(200);
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('paid');
  });

  it('shows pending without leaving the payment unpaid', async () => {
    await seed();
    const { fetch } = paypal();
    const res = await post(appWith(fetch), event('PAYMENT.CAPTURE.PENDING', 'WH-PENDING', {
      id: 'CAP-1',
      status: 'PENDING',
      custom_id: 'seller-a:o1',
    }));
    expect(res.status).toBe(200);
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('pending');
  });

  it('records a denied capture as a failed payment', async () => {
    await seed();
    const { fetch } = paypal();
    const res = await post(appWith(fetch), event('PAYMENT.CAPTURE.DENIED', 'WH-DENIED', {
      id: 'CAP-1',
      status: 'DENIED',
      custom_id: 'seller-a:o1',
    }));
    expect(res.status).toBe(200);
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('declined');
    expect(stored.get('approvalUrl')).toContain('checkoutnow');
  });

  it('sends a reversed approval back to unpaid and keeps the link', async () => {
    await seed('processing');
    const { fetch } = paypal();
    const res = await post(appWith(fetch), event('CHECKOUT.PAYMENT-APPROVAL.REVERSED', 'WH-REV', {
      id: 'PP-1',
      purchase_units: [{ custom_id: 'seller-a:o1' }],
    }));
    expect(res.status).toBe(200);
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('link_sent');
    expect(stored.get('approvalUrl')).toContain('checkoutnow');
  });

  it('records a refund without moving a paid order', async () => {
    await seed('paid');
    const { fetch } = paypal();
    const res = await post(appWith(fetch), event('PAYMENT.CAPTURE.REFUNDED', 'WH-REFUND', {
      id: 'CAP-1',
      status: 'REFUNDED',
      custom_id: 'seller-a:o1',
      amount: { value: '42.00' },
    }));
    expect(res.status).toBe(200);
    const stored = await db.doc('sellers/seller-a/orders/o1').get();
    expect(stored.get('status')).toBe('paid');
    const payment = await db.doc('sellers/seller-a/orders/o1/paymentEvents/WH-REFUND').get();
    expect(payment.exists).toBe(true);
  });
});
