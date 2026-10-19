import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { requireEmulator } from './emulator-guard.js';
import request from 'supertest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';
import { fallbackNudge } from '../src/ai/draft_nudge.js';
import type { ChatTransport } from '../src/ai/client.js';
import type { OrderDoc } from '../src/domain/orders.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-nudge-test', INTERNAL_TOKEN: 'sweep-secret',
});

let db: Firestore;
beforeAll(async () => {
  await requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-nudge-test' });
  db = getFirestore();
});

const HOUR = 60 * 60 * 1000;
const link = 'https://www.sandbox.paypal.com/checkoutnow?token=PP1';
const good = `Hiya Priya! Just checking the £20 deposit link came through: ${link}`;

function said(text: string, extra: Record<string, unknown> = {}): ChatTransport {
  return async () => ({
    content: JSON.stringify({ text, recommendChannel: 'manual_copy', shouldSkip: false, skipReason: null, ...extra }),
  });
}

function appWith(transport: ChatTransport = said(good)) {
  return createApp({
    env, db, transport,
    paypal: async () => { throw new Error('nudging never calls PayPal'); },
    verify: async (t: string) => {
      if (t === 'good') return { uid: 'seller-a' };
      if (t === 'other') return { uid: 'seller-b' };
      throw new Error('no');
    },
  });
}

async function seed(id: string, status: string, sentHoursAgo: number | null, nudge: Record<string, unknown> = {}) {
  await db.doc('sellers/seller-a').set({ displayName: "Ola's Bakehouse", personaTone: 'hiya! x' });
  await db.doc(`sellers/seller-a/orders/${id}`).set({
    id,
    status,
    buyerName: 'Priya K',
    lineItems: [{ nameResolved: 'Celebration cake', nameRaw: 'cake', variantIds: [], qty: 1, unitPriceMinor: 5500, lineTotalMinor: 5500 }],
    subtotalMinor: 5500, amountDueMinor: 2000, depositMinor: 2000,
    fulfilment: { mode: 'collection', date: '2026-10-17', notes: null },
    paypalOrderId: 'PP1',
    approvalUrl: status === 'draft' ? null : link,
    linkSentAt: sentHoursAgo === null ? null : Timestamp.fromMillis(Date.now() - sentHoursAgo * HOUR),
    nudge: { count: 0, lastSentAt: null, lastText: null, channel: null, snoozedUntil: null, ...nudge },
  });
}

const stored = async (id = 'o1') => (await db.doc(`sellers/seller-a/orders/${id}`).get()).data()!;
const post = (app: ReturnType<typeof appWith>, path: string, body: object = {}, token = 'good') =>
  request(app).post(path).set('Authorization', `Bearer ${token}`).send(body);

beforeEach(async () => {
  const sellers = await db.collection('sellers').listDocuments();
  await Promise.all(sellers.map((s) => db.recursiveDelete(s)));
});

describe('POST /v1/orders/:orderId/nudge', () => {
  it('drafts a reminder for a day-old unpaid link and keeps it on the order', async () => {
    await seed('o1', 'link_sent', 30);
    const res = await post(appWith(), '/v1/orders/o1/nudge', { tone: 'friendly' });

    expect(res.status).toBe(200);
    expect(res.body.nudge).toEqual({ text: good, channel: 'manual_copy', count: 0, sentAt: null, snoozedUntil: null });
    expect(res.body.source).toBe('ai');
    const nudge = (await stored()).nudge;
    expect(nudge.draftText).toBe(good);
    expect(nudge.draftedAt).toBeTruthy();
    // Drafting is not sending.
    expect(nudge.count).toBe(0);
    expect(nudge.lastSentAt).toBeNull();
  });

  it('falls back to the template when the model leaves the link out', async () => {
    await seed('o1', 'link_sent', 30);
    const res = await post(appWith(said('Hiya Priya! Just checking the £20 came through.')), '/v1/orders/o1/nudge');
    expect(res.status).toBe(200);
    expect(res.body.source).toBe('template');
    expect(res.body.nudge.text).toContain(link);
    expect(res.body.nudge.text).toContain('£20.00');
  });

  it('writes one anyway when the model would rather not chase, because the seller asked', async () => {
    await seed('o1', 'link_sent', 30);
    const res = await post(appWith(said('', { shouldSkip: true, skipReason: 'Too soon' })), '/v1/orders/o1/nudge');
    expect(res.status).toBe(200);
    expect(res.body.nudge.text).toContain(link);
  });

  it('refuses a link that went out less than a day ago', async () => {
    await seed('o1', 'link_sent', 5);
    const res = await post(appWith(), '/v1/orders/o1/nudge');
    expect(res.status).toBe(409);
    expect(res.body.error.message).toMatch(/less than a day/);
  });

  it.each(['paid', 'cancelled', 'expired', 'processing', 'pending', 'draft'])('never for a %s order', async (status) => {
    await seed('o1', status, 100);
    const res = await post(appWith(), '/v1/orders/o1/nudge');
    expect(res.status).toBe(409);
    expect((await stored()).nudge.draftText).toBeUndefined();
  });

  it('refuses a tone it does not know', async () => {
    await seed('o1', 'link_sent', 30);
    expect((await post(appWith(), '/v1/orders/o1/nudge', { tone: 'angry' })).status).toBe(400);
  });

  it("404s for another seller's order and 401s without a token", async () => {
    await seed('o1', 'link_sent', 30);
    expect((await post(appWith(), '/v1/orders/o1/nudge', {}, 'other')).status).toBe(404);
    expect((await request(appWith()).post('/v1/orders/o1/nudge').send({})).status).toBe(401);
  });
});

describe('POST /v1/orders/:orderId/nudge/sent', () => {
  it('counts the copied nudge as sent and clears the draft and any snooze', async () => {
    await seed('o1', 'link_sent', 30, { draftText: good, snoozedUntil: Timestamp.fromMillis(Date.now() + HOUR) });
    const res = await post(appWith(), '/v1/orders/o1/nudge/sent', { text: good });

    expect(res.status).toBe(200);
    expect(res.body.nudge.count).toBe(1);
    expect(res.body.nudge.sentAt).toBeTruthy();
    const nudge = (await stored()).nudge;
    expect(nudge).toMatchObject({ count: 1, lastText: good, channel: 'manual_copy', snoozedUntil: null, draftText: null });
    expect(nudge.lastSentAt.toMillis()).toBeGreaterThan(Date.now() - 60_000);
  });

  it('a second Copy tap is the same nudge, not another', async () => {
    await seed('o1', 'link_sent', 30);
    const app = appWith();
    await post(app, '/v1/orders/o1/nudge/sent', { text: good });
    const again = await post(app, '/v1/orders/o1/nudge/sent', { text: good });
    expect(again.body.nudge.count).toBe(1);
    expect((await stored()).nudge.count).toBe(1);
  });

  it('counts a different nudge on another day', async () => {
    await seed('o1', 'link_sent', 80, { count: 1, lastText: 'first', lastSentAt: Timestamp.fromMillis(Date.now() - 30 * HOUR) });
    const res = await post(appWith(), '/v1/orders/o1/nudge/sent', { text: good });
    expect(res.body.nudge.count).toBe(2);
  });

  it('refuses once the order is paid or closed', async () => {
    await seed('o1', 'paid', 30);
    const res = await post(appWith(), '/v1/orders/o1/nudge/sent', { text: good });
    expect(res.status).toBe(409);
    expect((await stored()).nudge.count).toBe(0);
  });

  it('needs the text that was sent', async () => {
    await seed('o1', 'link_sent', 30);
    expect((await post(appWith(), '/v1/orders/o1/nudge/sent', {})).status).toBe(400);
  });
});

describe('POST /v1/orders/:orderId/nudge/snooze', () => {
  it('quietens the nudge until tomorrow, without counting one', async () => {
    await seed('o1', 'link_sent', 30);
    const before = Date.now();
    const res = await post(appWith(), '/v1/orders/o1/nudge/snooze');

    expect(res.status).toBe(200);
    const nudge = (await stored()).nudge;
    expect(nudge.snoozedUntil.toMillis()).toBeGreaterThanOrEqual(before + 24 * HOUR);
    expect(nudge.snoozedUntil.toMillis()).toBeLessThanOrEqual(Date.now() + 24 * HOUR);
    expect(nudge.count).toBe(0);
    expect(res.body.nudge.snoozedUntil).toBe(nudge.snoozedUntil.toDate().toISOString());
  });

  it('refuses for an order that is not waiting on a link', async () => {
    await seed('o1', 'cancelled', 30);
    expect((await post(appWith(), '/v1/orders/o1/nudge/snooze')).status).toBe(409);
  });
});

describe('POST /v1/internal/workflows/nudge-sweep', () => {
  const sweep = (app: ReturnType<typeof appWith>, token = 'sweep-secret') =>
    request(app).post('/v1/internal/workflows/nudge-sweep').set('X-Internal-Token', token);

  it('refuses a call without the internal token', async () => {
    await seed('o1', 'link_sent', 30);
    expect((await request(appWith()).post('/v1/internal/workflows/nudge-sweep')).status).toBe(401);
    expect((await sweep(appWith(), 'nope')).status).toBe(401);
  });

  it('drafts a nudge for each order that is due, and sends nothing', async () => {
    await seed('due', 'link_sent', 30);
    await seed('young', 'link_sent', 3);
    await seed('snoozed', 'link_sent', 30, { snoozedUntil: Timestamp.fromMillis(Date.now() + HOUR) });
    await seed('done', 'link_sent', 200, { count: 2, lastSentAt: Timestamp.fromMillis(Date.now() - 50 * HOUR) });
    await seed('paid', 'paid', 30);
    await seed('cancelled', 'cancelled', 30);
    const res = await sweep(appWith());

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ scanned: 1, nudged: 1, skipped: 0 });
    const due = (await stored('due')).nudge;
    expect(due.draftText).toBe(good);
    expect(due.count).toBe(0);
    expect(due.lastSentAt).toBeNull();
    for (const id of ['young', 'snoozed', 'done', 'paid', 'cancelled']) {
      expect((await stored(id)).nudge.draftText).toBeUndefined();
    }
  });

  it('does not rewrite a draft that is already waiting', async () => {
    await seed('o1', 'link_sent', 30, { draftText: 'the one the seller is reading' });
    const res = await sweep(appWith(said(`Different £20 ${link}`)));
    expect(res.body).toEqual({ scanned: 1, nudged: 0, skipped: 1 });
    expect((await stored()).nudge.draftText).toBe('the one the seller is reading');
  });

  it('lets the model decline to chase, and says why', async () => {
    await seed('o1', 'link_sent', 30);
    const res = await sweep(appWith(said('', { shouldSkip: true, skipReason: 'They said Friday.' })));
    expect(res.body).toEqual({ scanned: 1, nudged: 0, skipped: 1 });
    const nudge = (await stored()).nudge;
    expect(nudge.draftText).toBeUndefined();
    expect(nudge.skipReason).toBe('They said Friday.');
  });

  it('still drafts from the template when the model is down', async () => {
    await seed('o1', 'link_sent', 30);
    const res = await sweep(appWith(async () => { throw new Error('503'); }));
    expect(res.body.nudged).toBe(1);
    const order = await stored();
    expect(order.nudge.draftText).toBe(fallbackNudge({
      order: order as OrderDoc, approvalUrl: link, tone: 'friendly', priorCount: 0,
    }));
  });
});
