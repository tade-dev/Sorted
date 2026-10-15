import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { requireEmulator } from './emulator-guard.js';
import request from 'supertest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';
import type { ChatTransport } from '../src/ai/client.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-orders-edit-test', INTERNAL_TOKEN: 't',
});

let db: Firestore;
beforeAll(async () => {
  await requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-orders-edit-test' });
  db = getFirestore();
});

const jess = {
  buyerName: 'Jess M', buyerHandle: 'jess.mcr', buyerEmail: null, channel: 'instagram',
  lineItems: [
    { nameRaw: 'lemon drizzle cake 10 inch', qty: 1, variantLabels: ['10 inch'] },
    { nameRaw: 'brownie box of 6', qty: 1, variantLabels: ['Box of 6'] },
  ],
  fulfilment: { mode: 'collection', date: '2026-10-10', notes: null },
  depositRequestedMinor: null, ambiguities: [], overallConfidence: 0.95,
};

function appWith(payload: unknown) {
  const transport: ChatTransport = async () => ({ content: JSON.stringify(payload) });
  return createApp({
    env, db, transport, paypal: async () => ({}),
    verify: async (t: string) => {
      if (t === 'good') return { uid: 'seller-a' };
      throw new Error('no');
    },
  });
}

beforeEach(async () => {
  const sellers = await db.collection('sellers').listDocuments();
  await Promise.all(sellers.map((s) => db.recursiveDelete(s)));

  const col = db.collection('sellers/seller-a/products');
  await col.doc('p1').set({
    id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200, depositMinor: null, active: true,
    variants: [
      { id: '8-inch', axis: 'size', label: '8 inch', priceDeltaMinor: 0, active: true },
      { id: '10-inch', axis: 'size', label: '10 inch', priceDeltaMinor: 1000, active: true },
    ],
  });
  await col.doc('p2').set({
    id: 'p2', name: 'Brownie box', basePriceMinor: 1400, depositMinor: null, active: true,
    variants: [{ id: 'box-of-6', axis: 'size', label: 'Box of 6', priceDeltaMinor: 0, active: true }],
  });
});

const png = Buffer.from('89504e470d0a1a0a', 'hex');

async function draft() {
  const res = await request(appWith(jess))
    .post('/v1/orders/draft')
    .set('Authorization', 'Bearer good')
    .attach('image', png, { filename: 'dm.png', contentType: 'image/png' });
  return res.body.order as { id: string; lineItems: { id: string }[] };
}

function edit(orderId: string, body: unknown) {
  return request(appWith(jess))
    .post(`/v1/orders/${orderId}/edit`)
    .set('Authorization', 'Bearer good')
    .send(body as object);
}

describe('POST /v1/orders/:orderId/edit', () => {
  it('replaces lines, reprices and recalculates totals', async () => {
    const order = await draft();
    const res = await edit(order.id, {
      lineItems: [
        { id: order.lineItems[0]!.id, productId: 'p1', variantIds: ['8-inch'], qty: 2 },
        { productId: 'p2', variantIds: ['box-of-6'], qty: 1 },
      ],
      note: 'Write Happy Birthday',
    });
    expect(res.status).toBe(200);
    expect(res.body.order.lineItems).toHaveLength(2);
    expect(res.body.order.lineItems[0].id).toBe(order.lineItems[0]!.id);
    expect(res.body.order.lineItems[0].lineTotalMinor).toBe(6400);
    expect(res.body.order.subtotalMinor).toBe(7800);
    expect(res.body.order.amountDueMinor).toBe(7800);
    expect(res.body.order.fulfilment.notes).toBe('Write Happy Birthday');

    const stored = (await db.doc(`sellers/seller-a/orders/${order.id}`).get()).data()!;
    expect(stored.subtotalMinor).toBe(7800);
  });

  it('reopens a sent order as a draft and drops the stale link', async () => {
    const order = await draft();
    await db.doc(`sellers/seller-a/orders/${order.id}`).update({
      status: 'link_sent', approvalUrl: 'https://paypal.test/x', paypalOrderId: 'PP1', draftedReply: 'hi',
    });
    const res = await edit(order.id, { lineItems: [{ productId: 'p2', variantIds: [], qty: 3 }] });
    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('draft');
    expect(res.body.order.approvalUrl).toBeNull();
    expect(res.body.order.paypalOrderId).toBeNull();
    expect(res.body.order.amountDueMinor).toBe(4200);
  });

  it('keeps a sent link when only the note changes', async () => {
    const order = await draft();
    await db.doc(`sellers/seller-a/orders/${order.id}`).update({
      status: 'link_sent', approvalUrl: 'https://paypal.test/x', paypalOrderId: 'PP1',
    });
    const res = await edit(order.id, { note: 'Collect after 3pm' });
    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('link_sent');
    expect(res.body.order.approvalUrl).toBe('https://paypal.test/x');
  });

  it('409s on a paid order and leaves it untouched', async () => {
    const order = await draft();
    await db.doc(`sellers/seller-a/orders/${order.id}`).update({ status: 'paid' });
    const res = await edit(order.id, { lineItems: [{ productId: 'p2', variantIds: [], qty: 9 }] });
    expect(res.status).toBe(409);
    expect(res.body.error.message).toMatch(/paid/);
    const stored = (await db.doc(`sellers/seller-a/orders/${order.id}`).get()).data()!;
    expect(stored.subtotalMinor).toBe(5600);
  });

  it.each(['processing', 'pending', 'cancelled', 'expired'])('409s while the order is %s', async (status) => {
    const order = await draft();
    await db.doc(`sellers/seller-a/orders/${order.id}`).update({ status });
    const res = await edit(order.id, { note: 'x' });
    expect(res.status).toBe(409);
  });

  it('400s on a product or variant that is not in the catalogue', async () => {
    const order = await draft();
    expect((await edit(order.id, { lineItems: [{ productId: 'nope', qty: 1 }] })).status).toBe(400);
    expect(
      (await edit(order.id, { lineItems: [{ productId: 'p1', variantIds: ['12-inch'], qty: 1 }] })).status,
    ).toBe(400);
  });

  it('400s on an empty line list or a bad quantity', async () => {
    const order = await draft();
    expect((await edit(order.id, { lineItems: [] })).status).toBe(400);
    expect((await edit(order.id, { lineItems: [{ productId: 'p1', qty: 0 }] })).status).toBe(400);
  });

  it('404s for an unknown order and 401s without a token', async () => {
    expect((await edit('missing', { note: 'x' })).status).toBe(404);
    const res = await request(appWith(jess)).post('/v1/orders/x/edit').send({ note: 'x' });
    expect(res.status).toBe(401);
  });
});

describe('superseding the old PayPal order on edit', () => {
  function appWithPayPal(paypal: (path: string, init: { method: string }) => Promise<unknown>) {
    const transport: ChatTransport = async () => ({ content: JSON.stringify(jess) });
    return createApp({
      env, db, transport, paypal,
      verify: async (t: string) => {
        if (t === 'good') return { uid: 'seller-a' };
        throw new Error('no');
      },
    });
  }

  async function sent() {
    const order = await draft();
    await db.doc(`sellers/seller-a/orders/${order.id}`).update({
      status: 'link_sent', approvalUrl: 'https://paypal.test/x', paypalOrderId: 'PP1',
    });
    return order;
  }

  it('records the old PayPal order as superseded and checks it', async () => {
    const order = await sent();
    const calls: string[] = [];
    const res = await request(appWithPayPal(async (path, init) => {
      calls.push(`${init.method} ${path}`);
      return { id: 'PP1', status: 'PAYER_ACTION_REQUIRED' };
    }))
      .post(`/v1/orders/${order.id}/edit`).set('Authorization', 'Bearer good')
      .send({ lineItems: [{ productId: 'p2', variantIds: [], qty: 2 }] });
    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('draft');
    expect(calls).toEqual(['GET /v2/checkout/orders/PP1']);
    const stored = (await db.doc(`sellers/seller-a/orders/${order.id}`).get()).data()!;
    expect(stored.supersededPaypalOrderIds).toEqual(['PP1']);
    expect(stored.paypalOrderId).toBeNull();
  });

  it('still saves the edit when PayPal fails', async () => {
    const order = await sent();
    const res = await request(appWithPayPal(async () => { throw new Error('PayPal down'); }))
      .post(`/v1/orders/${order.id}/edit`).set('Authorization', 'Bearer good')
      .send({ lineItems: [{ productId: 'p2', variantIds: [], qty: 2 }] });
    expect(res.status).toBe(200);
    const stored = (await db.doc(`sellers/seller-a/orders/${order.id}`).get()).data()!;
    expect(stored.supersededPaypalOrderIds).toEqual(['PP1']);
    expect(stored.amountDueMinor).toBe(2800);
  });

  it('does not touch PayPal when only the note changes', async () => {
    const order = await sent();
    const calls: string[] = [];
    const res = await request(appWithPayPal(async (path) => { calls.push(path); return {}; }))
      .post(`/v1/orders/${order.id}/edit`).set('Authorization', 'Bearer good')
      .send({ note: 'After 3pm' });
    expect(res.status).toBe(200);
    expect(calls).toEqual([]);
    const stored = (await db.doc(`sellers/seller-a/orders/${order.id}`).get()).data()!;
    expect(stored.supersededPaypalOrderIds).toBeUndefined();
  });
});
