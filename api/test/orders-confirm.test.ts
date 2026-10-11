import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { requireEmulator } from './emulator-guard.js';
import request from 'supertest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';
import { ApiError } from '../src/lib/errors.js';
import type { ChatTransport } from '../src/ai/client.js';
import type { PayPalFetch } from '../src/paypal/client.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-confirm-test', INTERNAL_TOKEN: 't',
});

let db: Firestore;
beforeAll(async () => {
  await requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-confirm-test' });
  db = getFirestore();
});

const LINK = 'https://www.sandbox.paypal.com/checkoutnow?token=PP-1';

const parsed = {
  buyerName: 'Jess M', buyerHandle: 'jess.mcr', buyerEmail: null, channel: 'instagram',
  lineItems: [{ nameRaw: 'lemon drizzle cake 10 inch', qty: 1, variantLabels: ['10 inch'] }],
  fulfilment: { mode: 'collection', date: '2026-10-10', notes: null },
  depositRequestedMinor: null, ambiguities: [], overallConfidence: 0.95,
};

function transportFor(payload: unknown): ChatTransport {
  return async (body) => {
    const sent = JSON.stringify(body);
    // The reply call carries the link in its system prompt; the parse call does not.
    if (sent.includes('checkoutnow')) {
      return { content: JSON.stringify({ reply: `All sorted! Pay here: ${LINK}` }) };
    }
    return { content: JSON.stringify(payload) };
  };
}

const happyPayPal: PayPalFetch = async () => ({
  id: 'PP-1',
  status: 'PAYER_ACTION_REQUIRED',
  links: [{ rel: 'payer-action', method: 'GET', href: LINK }],
});

function appWith(payload: unknown, paypal: PayPalFetch = happyPayPal) {
  return createApp({
    env, db, paypal,
    transport: transportFor(payload),
    verify: async (t: string) => {
      if (t === 'good') return { uid: 'seller-a' };
      throw new Error('no');
    },
  });
}

beforeEach(async () => {
  const sellers = await db.collection('sellers').listDocuments();
  await Promise.all(sellers.map((s) => db.recursiveDelete(s)));
  await db.doc('sellers/seller-a').set({
    id: 'seller-a', displayName: "Ola's Bakehouse", personaTone: 'hiya! x',
    currency: 'GBP', timezone: 'Europe/London', demoSeeded: true,
  });
  await db.doc('sellers/seller-a/products/p1').set({
    id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200, depositMinor: null, active: true,
    variants: [
      { id: '8-inch', axis: 'size', label: '8 inch', priceDeltaMinor: 0, active: true },
      { id: '10-inch', axis: 'size', label: '10 inch', priceDeltaMinor: 1000, active: true },
    ],
  });
});

async function draft(app: ReturnType<typeof appWith>) {
  const res = await request(app)
    .post('/v1/orders/draft')
    .set('Authorization', 'Bearer good')
    .field('text', 'a 10 inch lemon drizzle please');
  return res.body.order.id as string;
}

describe('POST /v1/orders/:orderId/confirm', () => {
  it('creates the PayPal order and returns the link and reply', async () => {
    const app = appWith(parsed);
    const id = await draft(app);

    const res = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});

    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('link_sent');
    expect(res.body.order.paypalOrderId).toBe('PP-1');
    expect(res.body.order.approvalUrl).toBe(LINK);
    expect(res.body.order.draftedReply).toContain(LINK);
  });

  it('stores a human-dated reply when the model cannot write one', async () => {
    const app = createApp({
      env, db, paypal: happyPayPal,
      transport: async (body) => {
        const sent = JSON.stringify(body);
        if (sent.includes('checkoutnow')) throw new Error('model down');
        return { content: JSON.stringify(parsed) };
      },
      verify: async (t: string) => {
        if (t === 'good') return { uid: 'seller-a' };
        throw new Error('no');
      },
    });
    const id = await draft(app);

    const res = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});

    expect(res.status).toBe(200);
    expect(res.body.order.draftedReply).toContain('Sat 10 Oct');
    expect(res.body.order.draftedReply).not.toContain('2026-10-10');
    expect(res.body.order.draftedReply).toContain(LINK);
  });

  it('charges exactly what the order says is due', async () => {
    const paypal = vi.fn<PayPalFetch>().mockResolvedValue({
      id: 'PP-1', status: 'PAYER_ACTION_REQUIRED',
      links: [{ rel: 'payer-action', method: 'GET', href: LINK }],
    });
    const app = appWith(parsed, paypal);
    const id = await draft(app);
    await request(app).post(`/v1/orders/${id}/confirm`).set('Authorization', 'Bearer good').send({});

    const body = paypal.mock.calls[0]![1].body as {
      purchase_units: { amount: { value: string } }[];
    };
    // The draft is a 10 inch lemon drizzle: GBP 32 base + GBP 10 = GBP 42.
    expect(body.purchase_units[0]!.amount.value).toBe('42.00');
  });

  it('refuses while a blocking ambiguity is unanswered', async () => {
    // Otherwise a link goes out with a guessed size and a price the seller
    // never agreed to.
    const vague = {
      ...parsed,
      lineItems: [{ nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: [] }],
    };
    const app = appWith(vague);
    const id = await draft(app);

    const res = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});

    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('ORDER_STATE_INVALID');
    const stored = await db.doc(`sellers/seller-a/orders/${id}`).get();
    expect(stored.data()!.status).toBe('draft');
  });

  it('refuses while the collection date is unanswered, then allows it once picked', async () => {
    const undated = {
      ...parsed,
      fulfilment: { mode: 'collection', date: null, notes: null },
      ambiguities: [{
        field: 'fulfilment.date', kind: 'missing',
        question: "They didn't say which day.", options: [], blocking: true,
      }],
    };
    const app = appWith(undated);
    const id = await draft(app);

    const blocked = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});
    expect(blocked.status).toBe(409);
    expect(blocked.body.error.details.unresolved).toEqual(['fulfilment.date']);

    const resolved = await request(app)
      .post(`/v1/orders/${id}/resolve`)
      .set('Authorization', 'Bearer good')
      .send({ fulfilment: { date: '2026-10-18' } });
    expect(resolved.status).toBe(200);
    expect(resolved.body.order.ambiguities).toHaveLength(0);

    const res = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});
    expect(res.status).toBe(200);
  });

  it('does not refuse confirm when the only open question is the buyer name', async () => {
    const unnamed = {
      ...parsed,
      buyerName: null,
      ambiguities: [{
        field: 'buyerName', kind: 'missing',
        question: 'Who is the cake for?', options: [], blocking: true,
      }],
    };
    const app = appWith(unnamed);
    const id = await draft(app);

    const res = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});
    expect(res.status).toBe(200);
    expect(res.body.order.buyerName).toBeNull();
  });

  it('leaves the order a draft when PayPal rejects it', async () => {
    const angry: PayPalFetch = async () => {
      throw new ApiError(502, 'PAYPAL_UNAVAILABLE', 'PayPal rejected that request (AMOUNT_MISMATCH). Nothing was charged.');
    };
    const app = appWith(parsed, angry);
    const id = await draft(app);

    const res = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});

    expect(res.status).toBe(502);
    expect(res.body.error.code).toBe('PAYPAL_UNAVAILABLE');

    const stored = await db.doc(`sellers/seller-a/orders/${id}`).get();
    expect(stored.data()!.status).toBe('draft');
    expect(stored.data()!.paypalOrderId).toBeNull();
    // The seller's work is still there to retry with.
    expect(stored.data()!.lineItems).toHaveLength(1);
  });

  it('refuses to confirm the same order twice', async () => {
    const app = appWith(parsed);
    const id = await draft(app);
    await request(app).post(`/v1/orders/${id}/confirm`).set('Authorization', 'Bearer good').send({});

    const second = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});

    expect(second.status).toBe(409);
  });

  it('applies a deposit sent at confirm time', async () => {
    const paypal = vi.fn<PayPalFetch>().mockResolvedValue({
      id: 'PP-1', status: 'PAYER_ACTION_REQUIRED',
      links: [{ rel: 'payer-action', method: 'GET', href: LINK }],
    });
    const app = appWith(parsed, paypal);
    const id = await draft(app);

    const res = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({ depositMinor: 1000 });

    expect(res.body.order.amountDueMinor).toBe(1000);
    const body = paypal.mock.calls[0]![1].body as { purchase_units: { amount: { value: string } }[] };
    expect(body.purchase_units[0]!.amount.value).toBe('10.00');
  });

  it('404s for an order that does not exist', async () => {
    const res = await request(appWith(parsed))
      .post('/v1/orders/nope/confirm')
      .set('Authorization', 'Bearer good')
      .send({});
    expect(res.status).toBe(404);
  });

  it('401s without a token', async () => {
    const app = appWith(parsed);
    const id = await draft(app);
    const res = await request(app).post(`/v1/orders/${id}/confirm`).send({});
    expect(res.status).toBe(401);
  });
});

describe('POST /v1/orders/:orderId/reply/regenerate', () => {
  it('rewrites the reply in another tone', async () => {
    const app = appWith(parsed);
    const id = await draft(app);
    await request(app).post(`/v1/orders/${id}/confirm`).set('Authorization', 'Bearer good').send({});

    const res = await request(app)
      .post(`/v1/orders/${id}/reply/regenerate`)
      .set('Authorization', 'Bearer good')
      .send({ tone: 'formal' });

    expect(res.status).toBe(200);
    expect(res.body.draftedReply).toContain(LINK);
  });

  it('409s on an order with no link yet', async () => {
    const app = appWith(parsed);
    const id = await draft(app);
    const res = await request(app)
      .post(`/v1/orders/${id}/reply/regenerate`)
      .set('Authorization', 'Bearer good')
      .send({ tone: 'short' });
    expect(res.status).toBe(409);
  });
});

describe('GET /v1/orders', () => {
  it('lists the seller\'s orders, newest first', async () => {
    const app = appWith(parsed);
    await draft(app);
    await draft(app);

    const res = await request(app).get('/v1/orders').set('Authorization', 'Bearer good');
    expect(res.status).toBe(200);
    expect(res.body.orders).toHaveLength(2);
  });

  it('401s without a token', async () => {
    const res = await request(appWith(parsed)).get('/v1/orders');
    expect(res.status).toBe(401);
  });
});
