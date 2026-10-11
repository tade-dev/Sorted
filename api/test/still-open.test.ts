import { describe, expect, it } from 'vitest';
import {
  ambiguityBlocks,
  applyBlockingPolicy,
  stillOpen,
  type AmbiguityOrder,
} from '../src/domain/ambiguities.js';
import type { Ambiguity } from '../src/ai/schemas.js';

const order: AmbiguityOrder = {
  lineItems: [
    { id: 'li-1', variantIds: [], productId: 'p1', qty: 1 },
  ],
  buyerName: null,
  buyerHandle: null,
  buyerEmail: null,
  fulfilment: { mode: 'collection', date: null, notes: null },
  depositMinor: null,
};

function ambiguity(field: string, blocking = true): Ambiguity {
  return { field, kind: 'missing', question: 'Which?', options: [], blocking };
}

describe('stillOpen', () => {
  it('stays open while a size has not been chosen', () => {
    expect(stillOpen(ambiguity('lineItems[0].variantIds'), order)).toBe(true);
  });

  it('closes a size once the line has a variant', () => {
    const chosen: AmbiguityOrder = {
      ...order,
      lineItems: [{ ...order.lineItems[0]!, variantIds: ['10-inch'] }],
    };
    expect(stillOpen(ambiguity('lineItems[0].variantIds'), chosen)).toBe(false);
  });

  it('stays open for an unmatched product', () => {
    const unmatched: AmbiguityOrder = {
      ...order,
      lineItems: [{ ...order.lineItems[0]!, productId: null }],
    };
    expect(stillOpen(ambiguity('lineItems[0].productId'), unmatched)).toBe(true);
  });

  it('does not clear a quantity question just because a qty was guessed', () => {
    expect(stillOpen(ambiguity('lineItems[0].qty'), order)).toBe(true);
    expect(
      stillOpen(ambiguity('lineItems[0].qty'), order, {
        lineItems: [{ id: 'li-1', qty: 3 }],
      }),
    ).toBe(false);
  });

  it('stays open for a missing collection date until one is set', () => {
    expect(stillOpen(ambiguity('fulfilment.date'), order)).toBe(true);
    const dated: AmbiguityOrder = {
      ...order,
      fulfilment: { ...order.fulfilment, date: '2026-10-18' },
    };
    expect(stillOpen(ambiguity('fulfilment.date'), dated)).toBe(false);
  });

  it('stays open for an unknown field until the seller marks it answered', () => {
    expect(stillOpen(ambiguity('something.else'), order)).toBe(true);
    expect(
      stillOpen(ambiguity('something.else'), order, {
        resolvedAmbiguities: ['something.else'],
      }),
    ).toBe(false);
  });

  it('does not let a flag dismiss a price-changing question', () => {
    expect(
      stillOpen(ambiguity('lineItems[0].variantIds'), order, {
        resolvedAmbiguities: ['lineItems[0].variantIds'],
      }),
    ).toBe(true);
  });

  it('closes a buyer name once the order has one', () => {
    expect(stillOpen(ambiguity('buyerName'), order)).toBe(true);
    expect(stillOpen(ambiguity('buyerName'), { ...order, buyerName: 'Jess M' })).toBe(false);
  });
});

describe('blocking policy', () => {
  it('does not block on a missing buyer name', () => {
    const named = ambiguity('buyerName');
    expect(ambiguityBlocks(named)).toBe(false);
    expect(applyBlockingPolicy(named).blocking).toBe(false);
  });

  it('still blocks on a missing date or size', () => {
    expect(ambiguityBlocks(ambiguity('fulfilment.date'))).toBe(true);
    expect(ambiguityBlocks(ambiguity('lineItems[0].variantIds'))).toBe(true);
    expect(applyBlockingPolicy(ambiguity('fulfilment.date')).blocking).toBe(true);
  });
});
