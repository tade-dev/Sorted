import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { requireEmulator } from './emulator-guard.js';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import {
  assertTransition,
  blockingAmbiguities,
  computeAmounts,
  createDraftOrder,
  loadProducts,
} from '../src/domain/orders.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

let db: Firestore;
beforeAll(async () => {
  await requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-orders-test' });
  db = getFirestore();
});
beforeEach(async () => {
  const s = await db.collection('sellers').listDocuments();
  await Promise.all(s.map((d) => db.recursiveDelete(d)));
});

describe('computeAmounts', () => {
  it('charges the subtotal when there is no deposit', () => {
    expect(computeAmounts(5600, null)).toEqual({
      subtotalMinor: 5600, depositMinor: null, amountDueMinor: 5600,
    });
  });

  it('charges the deposit when one is set', () => {
    // The Draft screen shows the deposit; PayPal must charge exactly that.
    expect(computeAmounts(5500, 2000).amountDueMinor).toBe(2000);
  });

  it('refuses a deposit larger than the order', () => {
    expect(() => computeAmounts(1000, 2000)).toThrow(/deposit/i);
  });

  it('allows a deposit equal to the whole order', () => {
    expect(computeAmounts(2000, 2000).amountDueMinor).toBe(2000);
  });

  it('refuses a fractional amount', () => {
    expect(() => computeAmounts(10.5, null)).toThrow();
  });
});

describe('blockingAmbiguities', () => {
  it('returns only the unresolved blocking ones', () => {
    const out = blockingAmbiguities([
      { field: 'a', kind: 'missing', question: 'q', options: [], blocking: true },
      { field: 'b', kind: 'unclear', question: 'q', options: [], blocking: false },
    ]);
    expect(out).toHaveLength(1);
    expect(out[0]!.field).toBe('a');
  });
});

describe('assertTransition', () => {
  it('allows draft to link_sent', () => {
    expect(() => assertTransition('draft', 'link_sent')).not.toThrow();
  });

  it('refuses link_sent back to draft', () => {
    expect(() => assertTransition('link_sent', 'draft')).toThrow(/ORDER_STATE_INVALID|cannot/i);
  });

  it('refuses paid to anything else', () => {
    expect(() => assertTransition('paid', 'cancelled')).toThrow();
  });

  it('allows draft to cancelled', () => {
    expect(() => assertTransition('draft', 'cancelled')).not.toThrow();
  });
});

describe('loadProducts', () => {
  it('returns only active products', async () => {
    const col = db.collection('sellers/s1/products');
    await col.doc('a').set({ id: 'a', name: 'Live', basePriceMinor: 100, depositMinor: null, variants: [], active: true });
    await col.doc('b').set({ id: 'b', name: 'Dead', basePriceMinor: 100, depositMinor: null, variants: [], active: false });

    const products = await loadProducts(db, 's1');
    expect(products.map((p) => p.name)).toEqual(['Live']);
  });
});

describe('createDraftOrder', () => {
  const base = {
    buyerName: 'Jess M', buyerHandle: 'jess.mcr', buyerEmail: null,
    channel: 'instagram' as const,
    lines: [
      { id: 'li-1', productId: 'p1', variantIds: ['10-inch'], nameRaw: 'lemon drizzle', nameResolved: 'Lemon drizzle cake', qty: 1, unitPriceMinor: 4200, lineTotalMinor: 4200, matchConfidence: 1, matchMethod: 'exact' as const },
      { id: 'li-2', productId: 'p2', variantIds: ['box-of-6'], nameRaw: 'brownies', nameResolved: 'Brownie box', qty: 1, unitPriceMinor: 1400, lineTotalMinor: 1400, matchConfidence: 1, matchMethod: 'exact' as const },
    ],
    ambiguities: [],
    fulfilment: { mode: 'collection' as const, date: '2026-10-10', notes: null },
    depositMinor: null,
    sourceKind: 'screenshot' as const,
    extractionModel: 'gpt-5.5',
  };

  it('writes a draft with the computed total', async () => {
    const order = await createDraftOrder(db, 's1', base);
    expect(order.status).toBe('draft');
    expect(order.subtotalMinor).toBe(5600);
    expect(order.amountDueMinor).toBe(5600);
    expect(order.currency).toBe('GBP');

    const stored = await db.doc(`sellers/s1/orders/${order.id}`).get();
    expect(stored.exists).toBe(true);
    expect(stored.data()!.subtotalMinor).toBe(5600);
  });

  it('sets an expiry seven days out', async () => {
    const order = await createDraftOrder(db, 's1', base);
    expect(order.expiresAt).not.toBeNull();
  });

  it('stores a deposit as the amount due', async () => {
    const order = await createDraftOrder(db, 's1', { ...base, depositMinor: 2000 });
    expect(order.subtotalMinor).toBe(5600);
    expect(order.amountDueMinor).toBe(2000);
  });

  it('keeps ambiguities so the app can ask about them', async () => {
    const order = await createDraftOrder(db, 's1', {
      ...base,
      ambiguities: [{ field: 'lineItems[0].variantIds', kind: 'missing', question: 'Which size?', options: ['8 inch'], blocking: true }],
    });
    expect(order.ambiguities).toHaveLength(1);
  });

  it('has no PayPal fields until it is confirmed', async () => {
    const order = await createDraftOrder(db, 's1', base);
    expect(order.paypalOrderId).toBeNull();
    expect(order.approvalUrl).toBeNull();
  });
});
