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
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-cancel-test', INTERNAL_TOKEN: 't',
});

let db: Firestore;
beforeAll(async () => {
  await requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-cancel-test' });
  db = getFirestore();
});

const unapproved = { id: 'PP-1', status: 'PAYER_ACTION_REQUIRED', purchase_units: [] };
const completed = {
  id: 'PP-1',
  status: 'COMPLETED',
  purchase_units: [{ payments: { captures: [{ id: 'CAP-1', status: 'COMPLETED' }] } }],
};

function paypal(body: unknown = unapproved): { fetch: PayPalFetch; calls: string[] } {
  const calls: string[] = [];
  const fetch: PayPalFetch = async (path, init) => {
    calls.push(`${init.method} ${path}`);
    return body;
  };
  return { fetch, calls };
}

function appWith(fetch: PayPalFetch = paypal().fetch) {
  return createApp({
    env, db, paypal: fetch,
    transport: async () => ({ content: '{}' }),
    verify: async (t: string) => {
      if (t === 'good') return { uid: 'seller-a' };
      if (t === 'other') return { uid: 'seller-b' };
      throw new Error('no');
    },
  });
}

async function seed(status: string, extra: Record<string, unknown> = {}) {
  await db.doc('sellers/seller-a/orders/o1').set({
    id: 'o1',
    status,
    buyerName: 'Jess M',
    paypalOrderId: status === 'draft' ? null : 'PP-1',
    approvalUrl: status === 'draft' ? null : 'https://www.sandbox.paypal.com/checkoutnow?token=PP-1',
    amountDueMinor: 4200,
    linkSentAt: status === 'draft' ? null : Timestamp.fromMillis(Date.now() - 60 * 60 * 1000),
    ...extra,
  });
}

function cancel(app: ReturnType<typeof appWith>, token = 'good', id = 'o1') {
  return request(app).post(`/v1/orders/${id}/cancel`).set('Authorization', `Bearer ${token}`).send({});
}

const order = () => db.doc('sellers/seller-a/orders/o1');

beforeEach(async () => {
  const sellers = await db.collection('sellers').listDocuments();
  await Promise.all(sellers.map((s) => db.recursiveDelete(s)));
});

describe('POST /v1/orders/:orderId/cancel', () => {
  it('cancels a draft without asking PayPal', async () => {
    await seed('draft');
    const { fetch, calls } = paypal();
    const res = await cancel(appWith(fetch));

    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('cancelled');
    expect(calls).toEqual([]);
    const stored = await order().get();
    expect(stored.get('status')).toBe('cancelled');
    expect(stored.get('cancelledAt')).toBeTruthy();
    const event = await order().collection('paymentEvents').doc('cancel-o1').get();
    expect(event.get('eventType')).toBe('cancelled');
    expect(event.get('raw')).toEqual({ source: 'seller', status: 'cancelled', from: 'draft' });
  });

  it('cancels a sent link and retires its PayPal order so it is never captured', async () => {
    await seed('link_sent');
    const { fetch, calls } = paypal();
    const res = await cancel(appWith(fetch));

    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('cancelled');
    expect(calls).toEqual(['GET /v2/checkout/orders/PP-1']);
    const stored = await order().get();
    expect(stored.get('status')).toBe('cancelled');
    // Kept for the record and for the buyer's return page.
    expect(stored.get('paypalOrderId')).toBe('PP-1');
    expect(stored.get('supersededPaypalOrderIds')).toEqual(['PP-1']);
  });

  it('cancels a declined order', async () => {
    await seed('declined');
    const res = await cancel(appWith());
    expect(res.status).toBe(200);
    expect((await order().get()).get('status')).toBe('cancelled');
  });

  it('cancels an approval PayPal never captured, without capturing it', async () => {
    await seed('link_sent');
    const { fetch, calls } = paypal({ id: 'PP-1', status: 'APPROVED', purchase_units: [] });
    const res = await cancel(appWith(fetch));

    expect(res.status).toBe(200);
    expect(calls.some((c) => c.endsWith('/capture'))).toBe(false);
    expect((await order().get()).get('status')).toBe('cancelled');
  });

  it('is safe to ask twice: one cancellation, one event', async () => {
    await seed('link_sent');
    const app = appWith();
    await cancel(app);
    const again = await cancel(app);

    expect(again.status).toBe(200);
    expect(again.body.order.status).toBe('cancelled');
    const events = await order().collection('paymentEvents').get();
    expect(events.docs.map((d) => d.id)).toEqual(['cancel-o1']);
    expect((await order().get()).get('supersededPaypalOrderIds')).toEqual(['PP-1']);
  });

  it('never cancels a paid order', async () => {
    await seed('paid', { paidAt: Timestamp.now() });
    const { fetch, calls } = paypal();
    const res = await cancel(appWith(fetch));

    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('ORDER_STATE_INVALID');
    expect(res.body.error.message).toMatch(/Refund it in PayPal/);
    expect(calls).toEqual([]);
    expect((await order().get()).get('status')).toBe('paid');
  });

  it.each(['processing', 'pending'])('refuses while the buyer is mid-payment (%s)', async (status) => {
    await seed(status);
    const res = await cancel(appWith());
    expect(res.status).toBe(409);
    expect(res.body.error.message).toMatch(/paying for this right now/);
    expect((await order().get()).get('status')).toBe(status);
  });

  it('refuses an expired order', async () => {
    await seed('expired');
    const res = await cancel(appWith());
    expect(res.status).toBe(409);
    expect((await order().get()).get('status')).toBe('expired');
  });

  it('marks the order paid, not cancelled, when PayPal already has the money', async () => {
    await seed('link_sent');
    const res = await cancel(appWith(paypal(completed).fetch));

    expect(res.status).toBe(409);
    expect(res.body.error.message).toMatch(/already paid/);
    const stored = await order().get();
    expect(stored.get('status')).toBe('paid');
    expect(stored.get('paypalCaptureId')).toBe('CAP-1');
    expect(stored.get('supersededPaypalOrderIds')).toBeUndefined();
  });

  it('cancels nothing when PayPal cannot be asked', async () => {
    await seed('link_sent');
    const down: PayPalFetch = async () => {
      throw new ApiError(502, 'PAYPAL_UNAVAILABLE', 'down', { status: 503 });
    };
    const res = await cancel(appWith(down));

    expect(res.status).toBe(502);
    expect(res.body.error.code).toBe('PAYPAL_UNAVAILABLE');
    expect((await order().get()).get('status')).toBe('link_sent');
    expect((await order().collection('paymentEvents').get()).empty).toBe(true);
  });

  it("404s for another seller's order", async () => {
    await seed('link_sent');
    const res = await cancel(appWith(), 'other');
    expect(res.status).toBe(404);
    expect((await order().get()).get('status')).toBe('link_sent');
  });

  it('404s for an order that is not there', async () => {
    const res = await cancel(appWith(), 'good', 'nope');
    expect(res.status).toBe(404);
  });

  it('401s without a token', async () => {
    await seed('draft');
    const res = await request(appWith()).post('/v1/orders/o1/cancel').send({});
    expect(res.status).toBe(401);
    expect((await order().get()).get('status')).toBe('draft');
  });

  it('a cancelled order can no longer be edited', async () => {
    await seed('link_sent', { lineItems: [] });
    const app = appWith();
    await cancel(app);
    const res = await request(app)
      .post('/v1/orders/o1/edit')
      .set('Authorization', 'Bearer good')
      .send({ note: 'later' });
    expect(res.status).toBe(409);
  });
});
