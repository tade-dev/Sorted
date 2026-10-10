import { describe, expect, it, vi } from 'vitest';
import { extractCatalogue, CATALOGUE_SYSTEM } from '../src/ai/extract_catalogue.js';
import type { ChatTransport } from '../src/ai/client.js';

const img = { buffer: Buffer.from('fake'), mime: 'image/png' };

function transportReturning(payload: unknown): ChatTransport {
  return async () => ({ content: JSON.stringify(payload) });
}

describe('extractCatalogue', () => {
  it('returns candidates the model found', async () => {
    const result = await extractCatalogue(
      [img],
      transportReturning({
        candidates: [
          {
            name: 'Lemon drizzle cake', description: 'Zesty lemon sponge.',
            basePriceMinor: 3200,
            variants: [
              { axis: 'size', label: '8 inch', priceDeltaMinor: 0 },
              { axis: 'size', label: '10 inch', priceDeltaMinor: 1000 },
            ],
            confidence: 0.9, ambiguities: [],
          },
        ],
      }),
      'test-model',
    );
    expect(result.candidates[0]!.name).toBe('Lemon drizzle cake');
    expect(result.candidates[0]!.variants).toHaveLength(2);
  });

  it('keeps a null price and its ambiguity rather than inventing a number', async () => {
    const result = await extractCatalogue(
      [img],
      transportReturning({
        candidates: [
          {
            name: 'Cinnamon buns', description: 'Soft buns.', basePriceMinor: null,
            variants: [{ axis: 'size', label: 'Box of 4', priceDeltaMinor: 0 }],
            confidence: 0.4,
            ambiguities: [
              { field: 'basePriceMinor', kind: 'missing', question: 'What do you charge for a box of 4?' },
            ],
          },
        ],
      }),
      'test-model',
    );
    expect(result.candidates[0]!.basePriceMinor).toBeNull();
    expect(result.candidates[0]!.ambiguities[0]!.kind).toBe('missing');
  });

  it('returns zero candidates for a photo that is not stock', async () => {
    const result = await extractCatalogue([img], transportReturning({ candidates: [] }), 'm');
    expect(result.candidates).toEqual([]);
  });

  it('sends one image part per photo', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ candidates: [] }),
    });
    await extractCatalogue([img, img, img], transport, 'm');
    // Count the parts, not the substring: each part serialises "image_url"
    // twice, once as the type value and once as the key.
    const body = transport.mock.calls[0]![0] as {
      messages: { role: string; content: { type: string }[] }[];
    };
    const user = body.messages.find((m) => m.role === 'user')!;
    expect(user.content.filter((p) => p.type === 'image_url')).toHaveLength(3);
  });

  it('instructs the model never to invent a price', () => {
    expect(CATALOGUE_SYSTEM).toMatch(/never invent/i);
  });
});
