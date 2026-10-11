import { describe, expect, it } from 'vitest';
import {
  ambiguityBlocks,
  applyBlockingPolicy,
  stillOpen,
  withoutSettledVariantQuestions,
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

  it('closes a size question the model filed under another name once a variant is stored', () => {
    expect(stillOpen(ambiguity('lineItems[0].variantLabels'), order)).toBe(true);
    expect(stillOpen(ambiguity('lineItems[0].size'), order)).toBe(true);
    const chosen: AmbiguityOrder = {
      ...order,
      lineItems: [{ ...order.lineItems[0]!, variantIds: ['8-inch'] }],
    };
    expect(stillOpen(ambiguity('lineItems[0].variantLabels'), chosen)).toBe(false);
    expect(stillOpen(ambiguity('lineItems[0].size'), chosen)).toBe(false);
    expect(stillOpen(ambiguity('lineItems[0].variant'), chosen)).toBe(false);
  });

  it('closes a line question when the seller marks that field answered', () => {
    expect(
      stillOpen(ambiguity('lineItems[0].variantIds'), order, {
        resolvedAmbiguities: ['lineItems[0].variantIds'],
      }),
    ).toBe(false);
    expect(
      stillOpen(ambiguity('lineItems[0].size'), order, {
        resolvedAmbiguities: ['lineItems[0].size'],
      }),
    ).toBe(false);
    expect(
      stillOpen(ambiguity('lineItems[0].icing'), order, {
        resolvedAmbiguities: ['lineItems[0].icing'],
      }),
    ).toBe(false);
  });

  it('closes a buyer name once the order has one', () => {
    expect(stillOpen(ambiguity('buyerName'), order)).toBe(true);
    expect(stillOpen(ambiguity('buyerName'), { ...order, buyerName: 'Jess M' })).toBe(false);
  });
});

describe('withoutSettledVariantQuestions', () => {
  const redVelvet = {
    id: 'red',
    variants: [{ active: true }],
  };

  it('drops a variant question once the line already has a variant', () => {
    const lines = [{ variantIds: ['8-inch'], productId: 'red' }];
    expect(
      withoutSettledVariantQuestions(
        [ambiguity('lineItems[0].variantLabels')],
        lines,
        [redVelvet],
      ),
    ).toEqual([]);
  });

  it('drops a variant question when the product has a single live variant', () => {
    const lines = [{ variantIds: [] as string[], productId: 'red' }];
    expect(
      withoutSettledVariantQuestions(
        [ambiguity('lineItems[0].size')],
        lines,
        [redVelvet],
      ),
    ).toEqual([]);
  });

  it('keeps a size question when the product still has a real choice', () => {
    const lines = [{ variantIds: [] as string[], productId: 'lemon' }];
    const lemon = { id: 'lemon', variants: [{ active: true }, { active: true }] };
    const kept = withoutSettledVariantQuestions(
      [ambiguity('lineItems[0].size')],
      lines,
      [lemon],
    );
    expect(kept).toHaveLength(1);
    expect(kept[0]!.field).toBe('lineItems[0].size');
  });

  it('leaves a question that is not about a variant', () => {
    const date = ambiguity('fulfilment.date');
    expect(
      withoutSettledVariantQuestions(
        [date],
        [{ variantIds: ['8-inch'], productId: 'red' }],
        [redVelvet],
      ),
    ).toEqual([date]);
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
