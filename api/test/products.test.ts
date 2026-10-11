import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { requireEmulator } from './emulator-guard.js';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { productInputSchema, saveProducts, uniqueSlugs } from '../src/domain/products.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

let db: Firestore;
beforeAll(async () => {
  await requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-products-test' });
  db = getFirestore();
});
beforeEach(async () => {
  const s = await db.collection('sellers').listDocuments();
  await Promise.all(s.map((d) => db.recursiveDelete(d)));
});

const cake = {
  name: 'Lemon drizzle cake',
  description: 'Zesty lemon sponge.',
  basePriceMinor: 3200,
  depositMinor: null,
  variants: [
    { axis: 'size', label: '8 inch', priceDeltaMinor: 0 },
    { axis: 'size', label: '10 inch', priceDeltaMinor: 1000 },
  ],
};

describe('uniqueSlugs', () => {
  it('slugifies distinct labels', () => {
    expect(uniqueSlugs(['8 inch', 'Box of 6'])).toEqual(['8-inch', 'box-of-6']);
  });

  it('disambiguates labels that would collide', () => {
    // The model generates these labels, so "Box of 6" and "box of 6" both
    // arriving is realistic. Sharing one id would silently merge two variants
    // and lose a price.
    expect(uniqueSlugs(['Box of 6', 'box of 6', 'BOX OF 6'])).toEqual([
      'box-of-6',
      'box-of-6-2',
      'box-of-6-3',
    ]);
  });

  it('does not collide a numeric suffix with a real slug', () => {
    // The model generates these labels. "Box of 6 2" slugifies to box-of-6-2,
    // which is exactly what the suffix for a second "box of 6" produces, so
    // two variants would share an id and one price would be lost.
    // The exact suffix is an implementation detail; distinctness is the
    // invariant, because the id is what a price is looked up by.
    const slugs = uniqueSlugs(['Box of 6', 'box of 6', 'Box of 6 2']);
    expect(new Set(slugs).size).toBe(3);
    expect(slugs[0]).toBe('box-of-6');
  });

  it('never returns an empty slug', () => {
    expect(uniqueSlugs(['!!!', '???'])).toEqual(['variant-1', 'variant-2']);
  });
});

describe('productInputSchema', () => {
  it('rejects a product with no price, which the UI must resolve first', () => {
    expect(() => productInputSchema.parse({ ...cake, basePriceMinor: null })).toThrow();
  });

  it('rejects a variant delta that would make the price negative', () => {
    expect(() =>
      productInputSchema.parse({
        ...cake,
        basePriceMinor: 500,
        variants: [{ axis: 'size', label: 'tiny', priceDeltaMinor: -600 }],
      }),
    ).toThrow();
  });

  it('accepts a zero price, because a freebie is a real listing', () => {
    expect(() => productInputSchema.parse({ ...cake, basePriceMinor: 0 })).not.toThrow();
  });
});

describe('saveProducts', () => {
  it('writes products and returns their ids', async () => {
    const { created } = await saveProducts(db, 'seller-a', [cake]);
    expect(created).toHaveLength(1);
    const snap = await db.collection('sellers/seller-a/products').get();
    expect(snap.size).toBe(1);
    expect(snap.docs[0]!.data().basePriceMinor).toBe(3200);
    expect(snap.docs[0]!.data().source).toBe('ai_extracted');
  });

  it('gives colliding variant labels distinct ids', async () => {
    await saveProducts(db, 'seller-a', [
      {
        ...cake,
        variants: [
          { axis: 'size', label: 'Box of 6', priceDeltaMinor: 0 },
          { axis: 'size', label: 'box of 6', priceDeltaMinor: 500 },
        ],
      },
    ]);
    const snap = await db.collection('sellers/seller-a/products').get();
    const ids = snap.docs[0]!.data().variants.map((v: { id: string }) => v.id);
    expect(new Set(ids).size).toBe(2);
  });

  it('skips a product whose name already exists rather than duplicating it', async () => {
    // A seller re-snapping a cake they already have, or double-tapping Save.
    await saveProducts(db, 'seller-a', [cake]);
    const second = await saveProducts(db, 'seller-a', [cake]);

    expect(second.created).toHaveLength(0);
    expect(second.skippedDuplicates).toEqual(['Lemon drizzle cake']);
    const snap = await db.collection('sellers/seller-a/products').get();
    expect(snap.size).toBe(1);
  });

  it('matches duplicates case-insensitively and ignoring surrounding space', async () => {
    await saveProducts(db, 'seller-a', [cake]);
    const second = await saveProducts(db, 'seller-a', [
      { ...cake, name: '  LEMON DRIZZLE CAKE ' },
    ]);
    expect(second.created).toHaveLength(0);
  });

  it('does not treat a soft-deleted product as a duplicate', async () => {
    const { created } = await saveProducts(db, 'seller-a', [cake]);
    await db.doc(`sellers/seller-a/products/${created[0]}`).update({ active: false });

    const second = await saveProducts(db, 'seller-a', [cake]);
    expect(second.created).toHaveLength(1);
  });

  it('is race-safe: two concurrent saves of the same product write it once', async () => {
    // "Add 3 products" has no in-flight guard, so a double tap fires two POSTs
    // before either finishes. Read-then-write lets both see an empty catalogue.
    await Promise.all([
      saveProducts(db, 'seller-a', [cake]),
      saveProducts(db, 'seller-a', [cake]),
    ]);
    const snap = await db.collection('sellers/seller-a/products').get();
    expect(snap.size).toBe(1);
  });

  it('writes several products in one call', async () => {
    const { created } = await saveProducts(db, 'seller-a', [
      cake,
      { ...cake, name: 'Brownie box', basePriceMinor: 1400 },
    ]);
    expect(created).toHaveLength(2);
  });
});
