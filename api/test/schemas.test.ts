import { describe, expect, it } from 'vitest';
import {
  ambiguitySchema,
  catalogueExtractionSchema,
  dailySummarySchema,
  dmOrderSchema,
  nudgeDraftSchema,
  replyDraftSchema,
} from '../src/ai/schemas.js';

describe('ambiguitySchema', () => {
  it('accepts a seller-facing question with options', () => {
    const parsed = ambiguitySchema.parse({
      field: 'lineItems[0].variantIds',
      kind: 'missing',
      question: 'What size did Jess want?',
      options: ['8 inch', '10 inch'],
      blocking: true,
    });
    expect(parsed.question).toBe('What size did Jess want?');
  });

  it('defaults options to an empty list and blocking to true', () => {
    const parsed = ambiguitySchema.parse({
      field: 'fulfilment.date',
      kind: 'unclear',
      question: 'Which Saturday?',
    });
    expect(parsed.options).toEqual([]);
    expect(parsed.blocking).toBe(true);
  });

  it('rejects an unknown kind', () => {
    expect(() =>
      ambiguitySchema.parse({ field: 'x', kind: 'vibes', question: 'eh?' }),
    ).toThrow();
  });
});

describe('catalogueExtractionSchema', () => {
  it('accepts a product with a null price and an ambiguity', () => {
    // Review.dc.html shows exactly this: "Couldn't read a price. Add one to save."
    const parsed = catalogueExtractionSchema.parse({
      candidates: [
        {
          name: 'Cinnamon buns',
          description: 'Soft cinnamon buns with a vanilla glaze.',
          basePriceMinor: null,
          variants: [{ axis: 'size', label: 'Box of 4', priceDeltaMinor: 0 }],
          confidence: 0.4,
          ambiguities: [
            {
              field: 'basePriceMinor',
              kind: 'missing',
              question: 'What do you charge for a box of 4?',
            },
          ],
        },
      ],
    });
    expect(parsed.candidates[0]!.basePriceMinor).toBeNull();
  });

  it('accepts zero candidates, for a photo that is not stock', () => {
    expect(catalogueExtractionSchema.parse({ candidates: [] }).candidates).toEqual([]);
  });

  it('rejects a fractional price, because money is integer pence', () => {
    expect(() =>
      catalogueExtractionSchema.parse({
        candidates: [
          { name: 'x', description: 'y', basePriceMinor: 32.5, variants: [], confidence: 1, ambiguities: [] },
        ],
      }),
    ).toThrow();
  });

  it('rejects a negative price', () => {
    expect(() =>
      catalogueExtractionSchema.parse({
        candidates: [
          { name: 'x', description: 'y', basePriceMinor: -1, variants: [], confidence: 1, ambiguities: [] },
        ],
      }),
    ).toThrow();
  });

  it('rejects confidence outside 0..1', () => {
    expect(() =>
      catalogueExtractionSchema.parse({
        candidates: [
          { name: 'x', description: 'y', basePriceMinor: 100, variants: [], confidence: 1.5, ambiguities: [] },
        ],
      }),
    ).toThrow();
  });

  it('allows a negative variant delta, which is a legitimate discount', () => {
    const parsed = catalogueExtractionSchema.parse({
      candidates: [
        {
          name: 'Lemon drizzle cake',
          description: 'Zesty lemon sponge.',
          basePriceMinor: 3200,
          variants: [{ axis: 'size', label: '6 inch', priceDeltaMinor: -800 }],
          confidence: 0.9,
          ambiguities: [],
        },
      ],
    });
    expect(parsed.candidates[0]!.variants[0]!.priceDeltaMinor).toBe(-800);
  });
});

describe('dmOrderSchema', () => {
  it('accepts the canonical Jess order', () => {
    const parsed = dmOrderSchema.parse({
      buyerName: 'Jess M',
      buyerHandle: 'jess.mcr',
      buyerEmail: null,
      channel: 'instagram',
      lineItems: [
        { nameRaw: 'lemon drizzle cake, the 10 inch one', qty: 1, variantLabels: ['10 inch'] },
        { nameRaw: 'brownie box of 6', qty: 1, variantLabels: ['Box of 6'] },
      ],
      fulfilment: { mode: 'collection', date: '2026-10-10', notes: "for her mum's birthday" },
      depositRequestedMinor: null,
      ambiguities: [],
      overallConfidence: 0.95,
    });
    expect(parsed.lineItems).toHaveLength(2);
  });

  it('rejects a quantity below 1', () => {
    expect(() =>
      dmOrderSchema.parse({
        buyerName: null, buyerHandle: null, buyerEmail: null, channel: 'unknown',
        lineItems: [{ nameRaw: 'cake', qty: 0, variantLabels: [] }],
        fulfilment: { mode: 'unknown', date: null, notes: null },
        depositRequestedMinor: null, ambiguities: [], overallConfidence: 0.5,
      }),
    ).toThrow();
  });

  it('rejects a fulfilment date that is not an ISO date', () => {
    expect(() =>
      dmOrderSchema.parse({
        buyerName: null, buyerHandle: null, buyerEmail: null, channel: 'unknown',
        lineItems: [{ nameRaw: 'cake', qty: 1, variantLabels: [] }],
        fulfilment: { mode: 'collection', date: 'next Saturday', notes: null },
        depositRequestedMinor: null, ambiguities: [], overallConfidence: 0.5,
      }),
    ).toThrow();
  });
});

describe('the three drafting schemas', () => {
  it('replyDraftSchema caps the reply length', () => {
    expect(() => replyDraftSchema.parse({ reply: 'x'.repeat(1001) })).toThrow();
    expect(replyDraftSchema.parse({ reply: 'Here you go!' }).reply).toBe('Here you go!');
  });

  it('nudgeDraftSchema lets the agent decline to chase', () => {
    const parsed = nudgeDraftSchema.parse({
      text: '', recommendChannel: 'manual_copy', shouldSkip: true,
      skipReason: 'Buyer already said they would pay on collection.',
    });
    expect(parsed.shouldSkip).toBe(true);
  });

  it('dailySummarySchema caps highlights at three', () => {
    expect(() =>
      dailySummarySchema.parse({ highlights: ['a', 'b', 'c', 'd'] }),
    ).toThrow();
  });
});
