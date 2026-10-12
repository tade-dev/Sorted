import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { requireEmulator } from './emulator-guard.js';
import request from 'supertest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';
import { sellerPatchSchema } from '../src/routes/session.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-session-route-test', INTERNAL_TOKEN: 't',
});

describe('sellerPatchSchema', () => {
  it('rejects unknown fields and empty names', () => {
    expect(sellerPatchSchema.safeParse({ currency: 'USD' }).success).toBe(false);
    expect(sellerPatchSchema.safeParse({ displayName: '  ' }).success).toBe(false);
    expect(sellerPatchSchema.safeParse({ fulfilmentMode: 'both', onboarded: true }).success).toBe(true);
  });
});

describe('PATCH /v1/session/seller', () => {
  let db: Firestore;
  beforeAll(async () => {
    await requireEmulator();
    if (getApps().length === 0) initializeApp({ projectId: 'sorted-session-route-test' });
    db = getFirestore();
  });
  beforeEach(async () => {
    const sellers = await db.collection('sellers').listDocuments();
    await Promise.all(sellers.map((s) => db.recursiveDelete(s)));
  });

  const app = () => createApp({
    env, db, transport: async () => ({ content: '{}' }), paypal: async () => ({}),
    verify: async (t: string) => {
      if (t === 'good') return { uid: 'seller-a' };
      throw new Error('no');
    },
  });

  it('saves setup answers and stamps onboarding and the shared merchant', async () => {
    await db.doc('sellers/seller-a').set({ displayName: 'My shop', personaTone: '' });
    const res = await request(app())
      .patch('/v1/session/seller')
      .set('Authorization', 'Bearer good')
      .send({ displayName: "Mia's Bakes", fulfilmentMode: 'collection', paypalConnected: true, onboarded: true });
    expect(res.status).toBe(200);
    const doc = (await db.doc('sellers/seller-a').get()).data()!;
    expect(doc.displayName).toBe("Mia's Bakes");
    expect(doc.paypalMerchant).toBe('shared_sandbox');
    expect(doc.onboardedAt).toBeDefined();
  });

  it('404s before bootstrap has made the shop', async () => {
    const res = await request(app())
      .patch('/v1/session/seller')
      .set('Authorization', 'Bearer good')
      .send({ onboarded: true });
    expect(res.status).toBe(404);
  });
});
