import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { requireEmulator } from './emulator-guard.js';
import request from 'supertest';
import express from 'express';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';
import { summaryRouter } from '../src/routes/summary.js';
import { errorHandler } from '../src/lib/errors.js';
import type { ChatTransport } from '../src/ai/client.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-summary-test', INTERNAL_TOKEN: 't',
});

let db: Firestore;
beforeAll(async () => {
  await requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-summary-test' });
  db = getFirestore();
});

const verify = async (t: string) => {
  if (t === 'good') return { uid: 'seller-a' };
  throw new Error('no');
};

let calls = 0;
const transport: ChatTransport = async () => {
  calls++;
  return { content: JSON.stringify({ highlights: ['Two orders paid today', 'One link still open'] }) };
};

let clock = new Date('2026-10-15T09:00:00Z');
function app() {
  const a = express();
  a.use('/v1', summaryRouter({ db, verify, transport, model: 'm', now: () => clock }));
  a.use(errorHandler);
  return a;
}

const orders = () => db.collection('sellers/seller-a/orders');

beforeEach(async () => {
  const sellers = await db.collection('sellers').listDocuments();
  await Promise.all(sellers.map((s) => db.recursiveDelete(s)));
  calls = 0;
  clock = new Date('2026-10-15T09:00:00Z');
  const old = Timestamp.fromDate(new Date('2026-10-15T07:00:00Z'));
  await orders().doc('o1').set({ status: 'paid', amountDueMinor: 4800, paidAt: Timestamp.fromDate(new Date('2026-10-15T08:00:00Z')), updatedAt: old });
  await orders().doc('o2').set({ status: 'paid', amountDueMinor: 3200, paidAt: Timestamp.fromDate(new Date('2026-10-15T08:30:00Z')), updatedAt: old });
  await orders().doc('o3').set({ status: 'link_sent', amountDueMinor: 2000, paidAt: null, updatedAt: old });
  await db.doc('sellers/seller-b/orders/x').set({ status: 'paid', amountDueMinor: 99900, paidAt: Timestamp.fromDate(clock), updatedAt: old });
});

describe('GET /v1/summary/today', () => {
  it('returns counts from code and highlights from the model, and stores them', async () => {
    const res = await request(app()).get('/v1/summary/today').set('Authorization', 'Bearer good');
    expect(res.status).toBe(200);
    expect(res.body.summary).toMatchObject({
      date: '2026-10-15', paidCount: 2, waitingCount: 1, draftCount: 0,
      paidTotalMinor: 8000, waitingTotalMinor: 2000,
      highlights: ['Two orders paid today', 'One link still open'],
    });
    const stored = (await db.doc('sellers/seller-a/summaries/2026-10-15').get()).data();
    expect(stored?.highlights).toHaveLength(2);
  });

  it('serves the stored summary for 15 minutes', async () => {
    await request(app()).get('/v1/summary/today').set('Authorization', 'Bearer good');
    clock = new Date(clock.getTime() + 10 * 60 * 1000);
    await request(app()).get('/v1/summary/today').set('Authorization', 'Bearer good');
    expect(calls).toBe(1);
    clock = new Date(clock.getTime() + 6 * 60 * 1000);
    await request(app()).get('/v1/summary/today').set('Authorization', 'Bearer good');
    expect(calls).toBe(2);
  });

  it('regenerates when an order changes status', async () => {
    await request(app()).get('/v1/summary/today').set('Authorization', 'Bearer good');
    await orders().doc('o3').update({ status: 'paid', paidAt: Timestamp.fromDate(clock), updatedAt: Timestamp.fromDate(new Date(clock.getTime() + 1000)) });
    clock = new Date(clock.getTime() + 2000);
    const res = await request(app()).get('/v1/summary/today').set('Authorization', 'Bearer good');
    expect(calls).toBe(2);
    expect(res.body.summary.paidCount).toBe(3);
    expect(res.body.summary.paidTotalMinor).toBe(10000);
  });

  it('401s without a token', async () => {
    const res = await request(createApp({ env, db, verify, transport, paypal: async () => ({}) })).get('/v1/summary/today');
    expect(res.status).toBe(401);
  });
});
