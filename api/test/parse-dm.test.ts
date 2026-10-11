import { describe, expect, it, vi } from 'vitest';
import { DM_ORDER_SYSTEM, parseDm, type CatalogueBrief } from '../src/ai/parse_dm.js';
import type { ChatTransport } from '../src/ai/client.js';

const catalogue: CatalogueBrief = [
  { id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200, variantLabels: ['8 inch', '10 inch'] },
  { id: 'p2', name: 'Brownie box', basePriceMinor: 1400, variantLabels: ['Box of 6', 'Box of 12'] },
];

const jess = {
  buyerName: 'Jess M', buyerHandle: 'jess.mcr', buyerEmail: null, channel: 'instagram',
  lineItems: [
    { nameRaw: 'lemon drizzle cake, the 10 inch one', qty: 1, variantLabels: ['10 inch'] },
    { nameRaw: 'brownie box of 6', qty: 1, variantLabels: ['Box of 6'] },
  ],
  fulfilment: { mode: 'collection', date: '2026-10-10', notes: "for her mum's birthday" },
  depositRequestedMinor: null, ambiguities: [], overallConfidence: 0.95,
};

const transportReturning = (payload: unknown): ChatTransport =>
  async () => ({ content: JSON.stringify(payload) });

describe('parseDm', () => {
  it('parses a screenshot into a structured order', async () => {
    const out = await parseDm(
      { image: { buffer: Buffer.from('x'), mime: 'image/png' } },
      catalogue, '2026-10-04', transportReturning(jess), 'm',
    );
    expect(out.buyerName).toBe('Jess M');
    expect(out.lineItems).toHaveLength(2);
    expect(out.fulfilment.date).toBe('2026-10-10');
  });

  it('parses pasted text with no image', async () => {
    const out = await parseDm(
      { text: 'can I get a 10 inch lemon drizzle for sat?' },
      catalogue, '2026-10-04', transportReturning(jess), 'm',
    );
    expect(out.lineItems).toHaveLength(2);
  });

  it('returns no line items for a screenshot that is not an order', async () => {
    // A receipt, a selfie, a menu. Inventing an order here would put a wrong
    // checkout link in front of a buyer.
    const empty = { ...jess, buyerName: null, buyerHandle: null, lineItems: [], overallConfidence: 0.1 };
    const out = await parseDm(
      { image: { buffer: Buffer.from('x'), mime: 'image/png' } },
      catalogue, '2026-10-04', transportReturning(empty), 'm',
    );
    expect(out.lineItems).toEqual([]);
  });

  it('rejects a call with neither an image nor text', async () => {
    await expect(
      parseDm({}, catalogue, '2026-10-04', transportReturning(jess), 'm'),
    ).rejects.toThrow(/image or text/i);
  });

  it('puts the catalogue in the prompt so the model can name real variants', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({ content: JSON.stringify(jess) });
    await parseDm({ text: 'hi' }, catalogue, '2026-10-04', transport, 'm');
    const body = JSON.stringify(transport.mock.calls[0]![0]);
    expect(body).toContain('Lemon drizzle cake');
    expect(body).toContain('10 inch');
  });

  it("tells the model today's date so relative dates resolve", async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({ content: JSON.stringify(jess) });
    await parseDm({ text: 'next saturday please' }, catalogue, '2026-10-04', transport, 'm');
    expect(JSON.stringify(transport.mock.calls[0]![0])).toContain('2026-10-04');
  });

  it('never sets temperature, which the pinned model rejects', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({ content: JSON.stringify(jess) });
    await parseDm({ text: 'hi' }, catalogue, '2026-10-04', transport, 'm');
    expect(transport.mock.calls[0]![0]).not.toHaveProperty('temperature');
  });

  it('instructs the model not to guess a size', () => {
    expect(DM_ORDER_SYSTEM).toMatch(/do not guess/i);
  });

  it('instructs the model that "box of 6" is one box, not six', () => {
    // gpt-4.1-mini got this wrong and would have billed GBP 84 instead of 14.
    expect(DM_ORDER_SYSTEM).toMatch(/box of 6/i);
  });
});
