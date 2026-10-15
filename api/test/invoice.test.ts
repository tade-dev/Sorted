import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { requireEmulator } from './emulator-guard.js';
import request from 'supertest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';
import {
  invoiceNumber,
  invoiceSignature,
  invoiceUrl,
  verifyInvoiceSignature,
} from '../src/domain/invoice.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const SECRET = 'invoice-secret';
const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'wh-1',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-invoice-test', INTERNAL_TOKEN: SECRET,
  PUBLIC_BASE_URL: 'https://api.example.com',
});

let db: Firestore;
beforeAll(async () => {
  await requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-invoice-test' });
  db = getFirestore();
});

const app = () =>
  createApp({
    env, db, paypal: async () => ({}),
    transport: async () => ({ content: '{}' }),
    verify: async (t: string) => {
      if (t === 'seller-a') return { uid: 'seller-a' };
      throw new Error('no');
    },
  });

async function seed(status: string, extra: Record<string, unknown> = {}) {
  await db.doc('sellers/seller-a').set({ displayName: "Ola's Bakehouse" });
  await db.doc('sellers/seller-a/orders/order123abc').set({
    id: 'order123abc',
    status,
    buyerName: 'Sarah <M>',
    buyerHandle: null,
    buyerEmail: 'sarah@example.com',
    paypalOrderId: 'PPORDER9',
    paypalCaptureId: 'CAP-77',
    lineItems: [
      { id: 'l1', productId: 'p1', variantIds: [], nameRaw: 'lemon cake', nameResolved: 'Lemon drizzle cake', qty: 1, unitPriceMinor: 3200, lineTotalMinor: 3200, matchConfidence: 1, matchMethod: 'exact' },
      { id: 'l2', productId: null, variantIds: [], nameRaw: 'cupcakes', nameResolved: null, qty: 6, unitPriceMinor: 250, lineTotalMinor: 1500, matchConfidence: 0, matchMethod: 'unmatched' },
    ],
    subtotalMinor: 4700,
    depositMinor: null,
    amountDueMinor: 4700,
    paidAt: Timestamp.fromDate(new Date('2026-10-14T20:42:00Z')),
    ...extra,
  });
}

const path = (sig = invoiceSignature(SECRET, 'seller-a', 'order123abc')) =>
  `/v1/invoice/seller-a/order123abc/${sig}`;

beforeEach(async () => {
  const sellers = await db.collection('sellers').listDocuments();
  await Promise.all(sellers.map((s) => db.recursiveDelete(s)));
});

describe('invoice signatures', () => {
  it('verifies its own signature and rejects others', () => {
    const sig = invoiceSignature(SECRET, 's', 'o');
    expect(verifyInvoiceSignature(SECRET, 's', 'o', sig)).toBe(true);
    expect(verifyInvoiceSignature(SECRET, 's', 'o2', sig)).toBe(false);
    expect(verifyInvoiceSignature('other', 's', 'o', sig)).toBe(false);
    expect(verifyInvoiceSignature(SECRET, 's', 'o', 'short')).toBe(false);
    expect(verifyInvoiceSignature(SECRET, '../x', 'o', sig)).toBe(false);
  });

  it('numbers invoices from the order id', () => {
    expect(invoiceNumber('order123abc')).toBe('INV-ORDER123');
  });
});

describe('GET /v1/invoice/:sellerId/:orderId/:sig', () => {
  it('shows a paid order as an escaped invoice', async () => {
    await seed('paid');
    const res = await request(app()).get(path());
    expect(res.status).toBe(200);
    expect(res.headers['cache-control']).toBe('no-store');
    expect(res.text).toContain('Invoice from Ola&#39;s Bakehouse');
    expect(res.text).toContain('INV-ORDER123');
    expect(res.text).toContain('Lemon drizzle cake');
    expect(res.text).toContain('cupcakes');
    expect(res.text).toContain('£47.00');
    expect(res.text).toContain('Paid 14 October 2026 with PayPal');
    expect(res.text).toContain('Sarah &lt;M&gt;');
    expect(res.text).not.toContain('sarah@example.com');
  });

  it('shows the deposit when one was taken', async () => {
    await seed('paid', { depositMinor: 1000, amountDueMinor: 1000 });
    const res = await request(app()).get(path());
    expect(res.text).toContain('Deposit paid now');
    expect(res.text).toContain('£10.00');
  });

  it('gives nothing away for an unpaid order or a bad signature', async () => {
    await seed('link_sent');
    const unpaid = await request(app()).get(path());
    expect(unpaid.text).toContain('No invoice here yet.');
    expect(unpaid.text).not.toContain('Lemon');

    await seed('paid');
    const forged = await request(app()).get(path('A'.repeat(32)));
    expect(forged.text).toContain('No invoice here yet.');
    expect(forged.text).not.toContain('Lemon');
  });
});

describe('GET /v1/orders/:orderId/invoice', () => {
  it('returns the signed link for a paid order', async () => {
    await seed('paid');
    const res = await request(app()).get('/v1/orders/order123abc/invoice').set('Authorization', 'Bearer seller-a');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      url: invoiceUrl('https://api.example.com', SECRET, 'seller-a', 'order123abc'),
      number: 'INV-ORDER123',
    });
  });

  it('409s before payment and 404s for a missing order', async () => {
    await seed('link_sent');
    const early = await request(app()).get('/v1/orders/order123abc/invoice').set('Authorization', 'Bearer seller-a');
    expect(early.status).toBe(409);
    const missing = await request(app()).get('/v1/orders/nope/invoice').set('Authorization', 'Bearer seller-a');
    expect(missing.status).toBe(404);
  });
});

describe('buyer return page', () => {
  it('links the invoice once the order is paid', async () => {
    await seed('paid');
    const res = await request(app()).get('/v1/paypal/return').query({ token: 'PPORDER9' });
    expect(res.text).toContain('View your invoice');
    expect(res.text).toContain(path());
  });

  it('has no invoice link while unpaid', async () => {
    await seed('link_sent');
    const res = await request(app()).get('/v1/paypal/return').query({ token: 'PPORDER9' });
    expect(res.text).not.toContain('View your invoice');
  });
});
