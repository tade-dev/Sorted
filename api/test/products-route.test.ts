import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-products-route-test', INTERNAL_TOKEN: 't',
});

let db: Firestore;
beforeAll(() => {
  if (getApps().length === 0) {
    initializeApp({ projectId: 'sorted-products-route-test' });
  }
  db = getFirestore();
});
beforeEach(async () => {
  const s = await db.collection('sellers').listDocuments();
  await Promise.all(s.map((d) => db.recursiveDelete(d)));
});

function app() {
  return createApp({
    env,
    db,
    verify: async (t: string) => {
      if (t === 'good') return { uid: 'seller-a' };
      throw new Error('no');
    },
    transport: async () => ({ content: '{}' }),
    paypal: async () => ({}),
  paypal: async () => ({}),
  });
}

const body = {
  products: [
    {
      name: 'Lemon drizzle cake', description: 'Zesty.',
      basePriceMinor: 3200, depositMinor: null,
      variants: [{ axis: 'size', label: '8 inch', priceDeltaMinor: 0 }],
    },
  ],
};

async function create() {
  const res = await request(app())
    .post('/v1/catalogue/products')
    .set('Authorization', 'Bearer good')
    .send(body);
  return res.body.created[0] as string;
}

describe('POST /v1/catalogue/products', () => {
  it('creates a product and returns its id', async () => {
    const res = await request(app())
      .post('/v1/catalogue/products')
      .set('Authorization', 'Bearer good')
      .send(body);
    expect(res.status).toBe(200);
    expect(res.body.created).toHaveLength(1);
    expect(res.body.skippedDuplicates).toEqual([]);
  });

  it('401s without a token', async () => {
    const res = await request(app()).post('/v1/catalogue/products').send(body);
    expect(res.status).toBe(401);
  });

  it('400s on a product with a null price', async () => {
    const res = await request(app())
      .post('/v1/catalogue/products')
      .set('Authorization', 'Bearer good')
      .send({ products: [{ ...body.products[0], basePriceMinor: null }] });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
  });

  it('400s on an empty products array', async () => {
    const res = await request(app())
      .post('/v1/catalogue/products')
      .set('Authorization', 'Bearer good')
      .send({ products: [] });
    expect(res.status).toBe(400);
  });
});

describe('PATCH /v1/catalogue/products/:productId', () => {
  it('updates a field and returns the product', async () => {
    const id = await create();
    const res = await request(app())
      .patch(`/v1/catalogue/products/${id}`)
      .set('Authorization', 'Bearer good')
      .send({ basePriceMinor: 3500 });
    expect(res.status).toBe(200);
    expect(res.body.product.basePriceMinor).toBe(3500);
  });

  it('404s for a product that does not exist', async () => {
    const res = await request(app())
      .patch('/v1/catalogue/products/nope')
      .set('Authorization', 'Bearer good')
      .send({ basePriceMinor: 100 });
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('400s on a change that would make a variant price negative', async () => {
    const id = await create();
    const res = await request(app())
      .patch(`/v1/catalogue/products/${id}`)
      .set('Authorization', 'Bearer good')
      .send({
        basePriceMinor: 100,
        variants: [{ axis: 'size', label: 'big', priceDeltaMinor: -500 }],
      });
    expect(res.status).toBe(400);
  });

  it('401s without a token', async () => {
    const id = await create();
    const res = await request(app())
      .patch(`/v1/catalogue/products/${id}`)
      .send({ basePriceMinor: 1 });
    expect(res.status).toBe(401);
  });

  it('400s when only the price is sent and a STORED variant turns it negative', async () => {
    // The guard only ran when price and variants arrived together, so dropping
    // the price alone stored an effective -GBP 4.00 that week 3 would total.
    const id = await create();
    await db.doc(`sellers/seller-a/products/${id}`).update({
      variants: [{ id: 'big', axis: 'size', label: 'big', priceDeltaMinor: -500, active: true }],
    });

    const res = await request(app())
      .patch(`/v1/catalogue/products/${id}`)
      .set('Authorization', 'Bearer good')
      .send({ basePriceMinor: 100 });

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
  });
});

describe('DELETE /v1/catalogue/products/:productId', () => {
  it('soft deletes rather than removing the document', async () => {
    // Week 3 orders reference products by id. A hard delete would orphan a
    // line item on an order already sent to a buyer.
    const id = await create();
    const res = await request(app())
      .delete(`/v1/catalogue/products/${id}`)
      .set('Authorization', 'Bearer good');

    expect(res.status).toBe(200);
    const doc = await db.doc(`sellers/seller-a/products/${id}`).get();
    expect(doc.exists).toBe(true);
    expect(doc.data()!.active).toBe(false);
  });

  it('404s for a product that does not exist', async () => {
    const res = await request(app())
      .delete('/v1/catalogue/products/nope')
      .set('Authorization', 'Bearer good');
    expect(res.status).toBe(404);
  });

  it('401s without a token', async () => {
    const id = await create();
    const res = await request(app()).delete(`/v1/catalogue/products/${id}`);
    expect(res.status).toBe(401);
  });
});
