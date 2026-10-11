import { describe, expect, it, vi } from 'vitest';
import { REPLY_SYSTEM, draftReply } from '../src/ai/draft_reply.js';
import type { ChatTransport } from '../src/ai/client.js';
import type { OrderDoc } from '../src/domain/orders.js';

const order = {
  id: 'o1', buyerName: 'Jess M',
  lineItems: [
    { nameResolved: 'Lemon drizzle cake', variantIds: ['10-inch'], qty: 1, unitPriceMinor: 4200, lineTotalMinor: 4200 },
    { nameResolved: 'Brownie box', variantIds: ['box-of-6'], qty: 1, unitPriceMinor: 1400, lineTotalMinor: 1400 },
  ],
  amountDueMinor: 5600, depositMinor: null,
  fulfilment: { mode: 'collection', date: '2026-10-10', notes: null },
} as unknown as OrderDoc;

const link = 'https://www.sandbox.paypal.com/checkoutnow?token=PP1';
const ok: ChatTransport = async () => ({
  content: JSON.stringify({ reply: `Hi Jess! That's sorted. Pay here: ${link}` }),
});

describe('draftReply', () => {
  it('returns the reply text', async () => {
    const out = await draftReply(
      { order, personaTone: 'hiya! x', approvalUrl: link, tone: 'friendly' },
      ok, 'm',
    );
    expect(out).toContain('Jess');
    expect(out).toContain(link);
  });

  it('puts the exact link in the prompt so the model cannot invent one', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply({ order, personaTone: '', approvalUrl: link, tone: 'friendly' }, transport, 'm');
    expect(JSON.stringify(transport.mock.calls[0]![0])).toContain(link);
  });

  it('passes the seller\'s own voice through', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply(
      { order, personaTone: 'hiya! let me know what you fancy x', approvalUrl: link, tone: 'friendly' },
      transport, 'm',
    );
    expect(JSON.stringify(transport.mock.calls[0]![0])).toContain('let me know what you fancy');
  });

  it('tells the model the total as formatted money, never raw pence', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply({ order, personaTone: '', approvalUrl: link, tone: 'friendly' }, transport, 'm');
    const body = JSON.stringify(transport.mock.calls[0]![0]);
    expect(body).toContain('56.00');
    expect(body).not.toContain('5600');
  });

  it('says it is a deposit when one is set', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply(
      { order: { ...order, depositMinor: 2000, amountDueMinor: 2000 }, personaTone: '', approvalUrl: link, tone: 'friendly' },
      transport, 'm',
    );
    expect(JSON.stringify(transport.mock.calls[0]![0]).toLowerCase()).toContain('deposit');
  });

  it('carries the tone through', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply({ order, personaTone: '', approvalUrl: link, tone: 'formal' }, transport, 'm');
    expect(JSON.stringify(transport.mock.calls[0]![0]).toLowerCase()).toContain('formal');
  });

  it('rejects a reply that dropped the link', async () => {
    // A reply without the checkout link is worse than none: the seller sends
    // it, the buyer cannot pay, and nobody notices until the chase.
    const noLink: ChatTransport = async () => ({
      content: JSON.stringify({ reply: 'Hi Jess, that is all sorted!' }),
    });
    await expect(
      draftReply({ order, personaTone: '', approvalUrl: link, tone: 'friendly' }, noLink, 'm'),
    ).rejects.toMatchObject({ code: 'AI_PARSE_FAILED' });
  });

  it('rejects a reply that altered the link', async () => {
    const wrong: ChatTransport = async () => ({
      content: JSON.stringify({ reply: 'pay: https://paypal.com/checkoutnow?token=SOMETHINGELSE' }),
    });
    await expect(
      draftReply({ order, personaTone: '', approvalUrl: link, tone: 'friendly' }, wrong, 'm'),
    ).rejects.toMatchObject({ code: 'AI_PARSE_FAILED' });
  });

  it('never sets temperature', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply({ order, personaTone: '', approvalUrl: link, tone: 'friendly' }, transport, 'm');
    expect(transport.mock.calls[0]![0]).not.toHaveProperty('temperature');
  });

  it('tells the model to use UK English and keep it short', () => {
    expect(REPLY_SYSTEM).toMatch(/UK English/i);
    expect(REPLY_SYSTEM).toMatch(/\b60 words\b/);
  });
});
