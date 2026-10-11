import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
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
  FIREBASE_PROJECT_ID: 'sorted-orders-route-test', INTERNAL_TOKEN: 't',
});

let db: Firestore;
beforeAll(() => {
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-orders-route-test' });
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
    env, db, transport,
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

describe('POST /v1/orders/draft', () => {
  it('turns a screenshot into a priced draft', async () => {
    const res = await request(appWith(jess))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .attach('image', png, { filename: 'dm.png', contentType: 'image/png' });

    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('draft');
    expect(res.body.order.subtotalMinor).toBe(5600);
    expect(res.body.order.buyerName).toBe('Jess M');
    expect(res.body.order.sourceKind).toBe('screenshot');
  });

  it('accepts pasted text, which is the web path', async () => {
    const res = await request(appWith(jess))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .field('text', 'can I get a 10 inch lemon drizzle and a box of 6 brownies');

    expect(res.status).toBe(200);
    expect(res.body.order.sourceKind).toBe('text');
    expect(res.body.order.subtotalMinor).toBe(5600);
  });

  it('400s with neither image nor text', async () => {
    const res = await request(appWith(jess))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
  });

  it('401s without a token', async () => {
    const res = await request(appWith(jess))
      .post('/v1/orders/draft')
      .field('text', 'hello');
    expect(res.status).toBe(401);
  });

  it('writes no order when the conversation contains none', async () => {
    const empty = { ...jess, lineItems: [], buyerName: null };
    const res = await request(appWith(empty))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .field('text', 'a photo of a cat');

    expect(res.status).toBe(200);
    expect(res.body.order).toBeNull();
    expect(res.body.reason).toMatch(/could not find an order/i);
    const orders = await db.collection('sellers/seller-a/orders').get();
    expect(orders.size).toBe(0);
  });

  it('carries an unknown product through as a blocking ambiguity', async () => {
    const odd = {
      ...jess,
      lineItems: [{ nameRaw: 'gluten free carrot cake', qty: 1, variantLabels: [] }],
    };
    const res = await request(appWith(odd))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .field('text', 'carrot cake please');

    expect(res.status).toBe(200);
    expect(res.body.order.ambiguities[0].kind).toBe('unknown_product');
    expect(res.body.order.subtotalMinor).toBe(0);
  });
});

describe('POST /v1/orders/:orderId/resolve', () => {
  async function draft() {
    const res = await request(appWith(jess))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .field('text', 'order please');
    return res.body.order.id as string;
  }

  it('sets a variant and reprices the line', async () => {
    const id = await draft();
    const res = await request(appWith(jess))
      .post(`/v1/orders/${id}/resolve`)
      .set('Authorization', 'Bearer good')
      .send({ lineItems: [{ id: 'li-1', variantIds: ['8-inch'] }] });

    expect(res.status).toBe(200);
    const line = res.body.order.lineItems.find((l: { id: string }) => l.id === 'li-1');
    expect(line.unitPriceMinor).toBe(3200);
    expect(res.body.order.subtotalMinor).toBe(4600);
  });

  it('changes a quantity and reprices', async () => {
    const id = await draft();
    const res = await request(appWith(jess))
      .post(`/v1/orders/${id}/resolve`)
      .set('Authorization', 'Bearer good')
      .send({ lineItems: [{ id: 'li-2', qty: 3 }] });

    expect(res.body.order.subtotalMinor).toBe(4200 + 4200);
  });

  it('sets a deposit as the amount due', async () => {
    const id = await draft();
    const res = await request(appWith(jess))
      .post(`/v1/orders/${id}/resolve`)
      .set('Authorization', 'Bearer good')
      .send({ depositMinor: 2000 });

    expect(res.body.order.subtotalMinor).toBe(5600);
    expect(res.body.order.amountDueMinor).toBe(2000);
  });

  it('400s on a deposit bigger than the order', async () => {
    const id = await draft();
    const res = await request(appWith(jess))
      .post(`/v1/orders/${id}/resolve`)
      .set('Authorization', 'Bearer good')
      .send({ depositMinor: 999999 });
    expect(res.status).toBe(400);
  });

  it('clears the ambiguity once the variant is chosen', async () => {
    const vague = {
      ...jess,
      lineItems: [{ nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: [] }],
    };
    const created = await request(appWith(vague))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .field('text', 'a lemon drizzle');
    expect(created.body.order.ambiguities).toHaveLength(1);

    const res = await request(appWith(vague))
      .post(`/v1/orders/${created.body.order.id}/resolve`)
      .set('Authorization', 'Bearer good')
      .send({ lineItems: [{ id: 'li-1', variantIds: ['10-inch'] }] });

    expect(res.body.order.ambiguities).toHaveLength(0);
    expect(res.body.order.subtotalMinor).toBe(4200);
  });

  it('404s for an order that does not exist', async () => {
    const res = await request(appWith(jess))
      .post('/v1/orders/nope/resolve')
      .set('Authorization', 'Bearer good')
      .send({ depositMinor: null });
    expect(res.status).toBe(404);
  });
});
