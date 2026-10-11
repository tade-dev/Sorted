import { describe, expect, it } from 'vitest';
import { matchLineItems, normalise, type StoredProduct } from '../src/domain/match_catalogue.js';

const lemon: StoredProduct = {
  id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200, depositMinor: null, active: true,
  variants: [
    { id: '8-inch', axis: 'size', label: '8 inch', priceDeltaMinor: 0, active: true },
    { id: '10-inch', axis: 'size', label: '10 inch', priceDeltaMinor: 1000, active: true },
  ],
};
const brownies: StoredProduct = {
  id: 'p2', name: 'Brownie box', basePriceMinor: 1400, depositMinor: null, active: true,
  variants: [
    { id: 'box-of-6', axis: 'size', label: 'Box of 6', priceDeltaMinor: 0, active: true },
    { id: 'box-of-12', axis: 'size', label: 'Box of 12', priceDeltaMinor: 1200, active: true },
  ],
};
const catalogue = [lemon, brownies];

describe('normalise', () => {
  it('ignores case, punctuation and extra space', () => {
    expect(normalise('  Lemon-Drizzle  CAKE! ')).toBe(normalise('lemon drizzle cake'));
  });
});

describe('matchLineItems', () => {
  it('reproduces the £56 Jess order the design screens show', () => {
    const { lines, subtotalMinor, ambiguities } = matchLineItems(
      [
        { nameRaw: 'lemon drizzle cake, the 10 inch one', qty: 1, variantLabels: ['10 inch'] },
        { nameRaw: 'brownie box of 6', qty: 1, variantLabels: ['Box of 6'] },
      ],
      catalogue,
    );
    expect(lines[0]!.unitPriceMinor).toBe(4200);
    expect(lines[1]!.unitPriceMinor).toBe(1400);
    expect(subtotalMinor).toBe(5600);
    expect(ambiguities).toEqual([]);
  });

  it('multiplies by quantity', () => {
    const { lines, subtotalMinor } = matchLineItems(
      [{ nameRaw: 'brownie box', qty: 3, variantLabels: ['Box of 6'] }],
      catalogue,
    );
    expect(lines[0]!.lineTotalMinor).toBe(4200);
    expect(subtotalMinor).toBe(4200);
  });

  it('matches a product by a loose name', () => {
    const { lines } = matchLineItems(
      [{ nameRaw: 'the lemon drizzle', qty: 1, variantLabels: ['8 inch'] }],
      catalogue,
    );
    expect(lines[0]!.productId).toBe('p1');
    expect(lines[0]!.nameResolved).toBe('Lemon drizzle cake');
  });

  it('flags a product the catalogue does not have, with no price', () => {
    // "gluten free carrot cake" must not be silently dropped, and must not be
    // priced at zero and sent to a buyer.
    const { lines, ambiguities, subtotalMinor } = matchLineItems(
      [{ nameRaw: 'gluten free carrot cake', qty: 1, variantLabels: [] }],
      catalogue,
    );
    expect(lines[0]!.productId).toBeNull();
    expect(lines[0]!.matchMethod).toBe('unmatched');
    expect(lines[0]!.unitPriceMinor).toBe(0);
    expect(subtotalMinor).toBe(0);
    expect(ambiguities[0]!.kind).toBe('unknown_product');
    expect(ambiguities[0]!.blocking).toBe(true);
  });

  it('asks which size when the product has a choice and the buyer did not say', () => {
    const { lines, ambiguities } = matchLineItems(
      [{ nameRaw: 'a lemon drizzle cake', qty: 1, variantLabels: [] }],
      catalogue,
    );
    expect(lines[0]!.productId).toBe('p1');
    expect(ambiguities[0]!.kind).toBe('missing');
    expect(ambiguities[0]!.blocking).toBe(true);
    expect(ambiguities[0]!.options).toEqual(['8 inch', '10 inch']);
    expect(ambiguities[0]!.field).toBe('lineItems[0].variantIds');
  });

  it('does not ask when the product has only one variant', () => {
    const single: StoredProduct = { ...lemon, variants: [lemon.variants[0]!] };
    const { lines, ambiguities } = matchLineItems(
      [{ nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: [] }],
      [single],
    );
    expect(lines[0]!.unitPriceMinor).toBe(3200);
    expect(ambiguities).toEqual([]);
  });

  it('matches a variant label loosely', () => {
    const { lines } = matchLineItems(
      [{ nameRaw: 'brownies', qty: 1, variantLabels: ['box of 6'] }],
      catalogue,
    );
    expect(lines[0]!.variantIds).toEqual(['box-of-6']);
  });

  it('ignores an inactive product', () => {
    const { lines, ambiguities } = matchLineItems(
      [{ nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: ['8 inch'] }],
      [{ ...lemon, active: false }],
    );
    expect(lines[0]!.matchMethod).toBe('unmatched');
    expect(ambiguities[0]!.kind).toBe('unknown_product');
  });

  it('ignores an inactive variant when offering options', () => {
    const withDead: StoredProduct = {
      ...lemon,
      variants: [lemon.variants[0]!, { ...lemon.variants[1]!, active: false }],
    };
    const { lines, ambiguities } = matchLineItems(
      [{ nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: [] }],
      [withDead],
    );
    expect(lines[0]!.unitPriceMinor).toBe(3200);
    expect(ambiguities).toEqual([]);
  });

  it('gives every line a stable id, so the app can address one', () => {
    const { lines } = matchLineItems(
      [
        { nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: ['8 inch'] },
        { nameRaw: 'brownie box', qty: 1, variantLabels: ['Box of 6'] },
      ],
      catalogue,
    );
    expect(new Set(lines.map((l) => l.id)).size).toBe(2);
  });

  it('returns a zero subtotal for no items rather than throwing', () => {
    expect(matchLineItems([], catalogue).subtotalMinor).toBe(0);
  });
});
