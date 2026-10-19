import { describe, expect, it, vi } from 'vitest';
import { NUDGE_SYSTEM, draftNudge, fallbackNudge, nudgeProblem } from '../src/ai/draft_nudge.js';
import type { ChatTransport } from '../src/ai/client.js';
import type { OrderDoc } from '../src/domain/orders.js';

const order = {
  id: 'o1', buyerName: 'Priya K',
  lineItems: [
    { nameResolved: 'Celebration cake', variantIds: [], qty: 1, unitPriceMinor: 5500, lineTotalMinor: 5500 },
  ],
  subtotalMinor: 5500, amountDueMinor: 2000, depositMinor: 2000,
  fulfilment: { mode: 'collection', date: '2026-10-17', notes: null },
} as unknown as OrderDoc;

const link = 'https://www.sandbox.paypal.com/checkoutnow?token=9QA1';

function said(text: string, extra: Record<string, unknown> = {}): ChatTransport {
  return async () => ({
    content: JSON.stringify({ text, recommendChannel: 'manual_copy', shouldSkip: false, skipReason: null, ...extra }),
  });
}

const input = { order, approvalUrl: link, personaTone: 'hiya! x', tone: 'friendly' as const, priorCount: 0, daysUnpaid: 2 };

describe('nudgeProblem', () => {
  it('passes a reminder with the link once and the amount', () => {
    expect(nudgeProblem(`Hi Priya! The £20 deposit link: ${link}`, link, 2000)).toBeNull();
    expect(nudgeProblem(`Hi Priya! The £20.00 deposit link: ${link}`, link, 2000)).toBeNull();
  });

  it.each([
    ['', 'empty'],
    [`£20, pay here: ${link} or ${link}`, 'link not exactly once'],
    ['£20, pay here: https://paypal.example/other', 'link not exactly once'],
    [`£20 ${link} and www.example.com`, 'extra link'],
    [`<b>£20</b> ${link}`, 'markup'],
    [`Pay here: ${link}`, 'amount missing'],
    [`£20 ${link} ${'x'.repeat(500)}`, 'too long'],
  ])('refuses %j (%s)', (text, problem) => {
    expect(nudgeProblem(text, link, 2000)).toBe(problem);
  });
});

describe('fallbackNudge', () => {
  it('names the buyer, what it is for, the amount and the link', () => {
    expect(fallbackNudge(input)).toBe(
      `Hi Priya! Just checking the payment link came through for the deposit for your Celebration cake for collection Sat 17 Oct. It's £20.00, and you can pay here: ${link}`,
    );
  });

  it('offers an out on a second reminder', () => {
    expect(fallbackNudge({ ...input, priorCount: 1 })).toContain("if you've changed your mind just say and I'll cancel it");
  });

  it('changes its opening with the tone', () => {
    expect(fallbackNudge({ ...input, tone: 'firm' })).toMatch(/^Hi Priya, a reminder that/);
    expect(fallbackNudge({ ...input, tone: 'gentle' })).toMatch(/no worries if you've been busy/);
  });

  it('passes its own checks, whatever the tone', () => {
    for (const tone of ['friendly', 'gentle', 'firm'] as const) {
      for (const priorCount of [0, 1]) {
        expect(nudgeProblem(fallbackNudge({ ...input, tone, priorCount }), link, 2000)).toBeNull();
      }
    }
  });
});

describe('draftNudge', () => {
  it("uses the model's reminder when it passes", async () => {
    const out = await draftNudge(input, said(`Hiya Priya! Your £20 deposit link for Sat 17 Oct: ${link} x`), 'm');
    expect(out).toEqual({
      text: `Hiya Priya! Your £20 deposit link for Sat 17 Oct: ${link} x`,
      source: 'ai', shouldSkip: false, skipReason: null,
    });
  });

  it('tells the model the facts, the link, the tone and the guardrails', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ text: `£20 ${link}`, recommendChannel: 'manual_copy', shouldSkip: false, skipReason: null }),
    });
    await draftNudge({ ...input, tone: 'gentle', priorCount: 1 }, transport, 'm');
    const body = JSON.stringify(transport.mock.calls[0]![0]);
    expect(body).toContain(link);
    expect(body).toContain('£20.00 deposit');
    expect(body).toContain('Sat 17 Oct');
    expect(body).toContain('Reminders already sent: 1');
    expect(body).toContain('gentle');
    expect(body).toContain('hiya! x');
    expect(NUDGE_SYSTEM).toMatch(/Never guilt-trip/);
    expect(NUDGE_SYSTEM).toMatch(/Under 45 words/);
  });

  it('turns an ISO date the model echoed into the UK form', async () => {
    const out = await draftNudge(input, said(`£20 for 2026-10-17: ${link}`), 'm');
    expect(out.text).toBe(`£20 for Sat 17 Oct: ${link}`);
  });

  it('falls back to the template when the model mangles the link', async () => {
    const out = await draftNudge(input, said('£20, pay here: https://paypal.example/made-up'), 'm');
    expect(out.source).toBe('template');
    expect(out.text).toBe(fallbackNudge(input));
  });

  it('falls back to the template when the model is down', async () => {
    const down: ChatTransport = async () => { throw new Error('503'); };
    const out = await draftNudge(input, down, 'm');
    expect(out).toEqual({ text: fallbackNudge(input), source: 'template', shouldSkip: false, skipReason: null });
  });

  it('passes on a model that would rather not chase', async () => {
    const out = await draftNudge(input, said('', { shouldSkip: true, skipReason: 'They said they would pay Friday.' }), 'm');
    expect(out.shouldSkip).toBe(true);
    expect(out.skipReason).toBe('They said they would pay Friday.');
    // Still something correct to paste if the seller asks anyway.
    expect(out.text).toBe(fallbackNudge(input));
  });
});
