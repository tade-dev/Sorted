import { nudgeDraftSchema } from './schemas.js';
import { generateStructured, type ChatTransport } from './client.js';
import { formatUkDate, humaniseIsoDates } from '../domain/dates.js';
import { formatGbp } from '../domain/money.js';
import type { OrderDoc } from '../domain/orders.js';

/** Nudge.dc.html's three chips. */
export type NudgeTone = 'friendly' | 'gentle' | 'firm';

export const NUDGE_SYSTEM = [
  'You write a payment reminder a UK small seller sends a buyer in a DM, when a payment link has gone unpaid.',
  'Write as the seller, in their voice. A sample of how they write is given below; match it.',
  'UK English. Under 45 words. Polite and warm. Never guilt-trip, pressure, or threaten.',
  'Say what it is for and the amount, exactly as given.',
  'Include the payment link exactly once, exactly as given, with nothing appended to it. Do not invent, shorten or wrap any link.',
  'Use no emoji unless the seller\'s own sample uses them. No HTML or markdown.',
  'Do not promise a date, a time or anything else that is not in the order details given.',
  'When the order details include a date, copy it exactly. Never rewrite it as an ISO date.',
  'If this is not the first reminder, offer an easy out, for example that you are happy to hold it or cancel, just say.',
  'Set recommendChannel to manual_copy: the seller pastes this into the chat themselves.',
  'Set shouldSkip to true only if chasing would clearly be wrong from the details given; otherwise false, with skipReason null.',
].join(' ');

export const NUDGE_JSON_SCHEMA: Record<string, unknown> = {
  type: 'object',
  additionalProperties: false,
  required: ['text', 'recommendChannel', 'shouldSkip', 'skipReason'],
  properties: {
    text: { type: 'string' },
    recommendChannel: { type: 'string', enum: ['paypal_invoice', 'manual_copy'] },
    shouldSkip: { type: 'boolean' },
    skipReason: { type: ['string', 'null'] },
  },
};

const TONE_GUIDANCE: Record<NudgeTone, string> = {
  friendly: 'Tone: friendly and chatty, the way they would talk to a regular.',
  gentle: 'Tone: gentle and low-key. Assume they have just been busy.',
  firm: 'Tone: clear and direct, still polite. Ask them to pay or say if they no longer want it.',
};

export type NudgeInput = {
  order: OrderDoc;
  approvalUrl: string;
  personaTone: string;
  tone: NudgeTone;
  /** How many nudges have already gone out. */
  priorCount: number;
  /** Whole days since the link was sent. */
  daysUnpaid: number;
};

export type DraftedNudge = {
  text: string;
  /** 'ai' when the model's text passed every check, 'template' otherwise. */
  source: 'ai' | 'template';
  shouldSkip: boolean;
  skipReason: string | null;
};

function whatFor(order: OrderDoc): string {
  const items = order.lineItems.map((l) => l.nameResolved ?? l.nameRaw).join(', ');
  return order.depositMinor !== null ? `the deposit for your ${items}` : `your ${items}`;
}

function amountForms(minor: number): string[] {
  const full = formatGbp(minor);
  return full.endsWith('.00') ? [full, full.slice(0, -3)] : [full];
}

/**
 * Why a model draft cannot be pasted, or null if it can. A nudge with the
 * wrong link is worse than none: the buyer cannot pay, and the seller looks
 * careless at the exact moment they are asking for money.
 */
export function nudgeProblem(text: string, approvalUrl: string, amountMinor: number): string | null {
  if (!text.trim()) return 'empty';
  if (text.length > 500) return 'too long';
  if (/<[a-z/!][^>]*>/i.test(text)) return 'markup';
  if (text.split(approvalUrl).length - 1 !== 1) return 'link not exactly once';
  const others = text.split(approvalUrl).join(' ').match(/https?:\/\/\S+|www\.\S+/gi);
  if (others) return 'extra link';
  if (!amountForms(amountMinor).some((a) => text.includes(a))) return 'amount missing';
  return null;
}

/** Used whenever the model cannot write a nudge that passes. Same facts, plainer words. */
export function fallbackNudge(input: Omit<NudgeInput, 'personaTone' | 'daysUnpaid'>): string {
  const { order, approvalUrl, tone, priorCount } = input;
  const who = order.buyerName?.trim().split(/\s+/)[0] || 'there';
  const amount = formatGbp(order.amountDueMinor);
  const when = order.fulfilment.date
    ? ` for ${order.fulfilment.mode === 'delivery' ? 'delivery' : 'collection'} ${formatUkDate(order.fulfilment.date)}`
    : '';
  const out = priorCount > 0 ? " No rush, and if you've changed your mind just say and I'll cancel it." : '';
  const opener = tone === 'firm'
    ? `Hi ${who}, a reminder that ${whatFor(order)}${when} is still unpaid.`
    : tone === 'gentle'
      ? `Hi ${who}, no worries if you've been busy! Just checking the link came through for ${whatFor(order)}${when}.`
      : `Hi ${who}! Just checking the payment link came through for ${whatFor(order)}${when}.`;
  return `${opener} It's ${amount}, and you can pay here: ${approvalUrl}${out}`;
}

/**
 * Drafts a nudge. Never throws: a model failure, or a draft that fails the
 * checks above, falls back to the template, so the seller always has
 * something correct to paste.
 */
export async function draftNudge(
  input: NudgeInput,
  transport: ChatTransport,
  model: string,
): Promise<DraftedNudge> {
  const { order, approvalUrl, tone } = input;
  const fallback = (): DraftedNudge => ({
    text: fallbackNudge(input),
    source: 'template',
    shouldSkip: false,
    skipReason: null,
  });

  const details = [
    `Buyer: ${order.buyerName ?? 'the buyer'}`,
    `It is for: ${order.lineItems.map((l) => `${l.qty} x ${l.nameResolved ?? l.nameRaw}`).join(', ')}`,
    order.depositMinor !== null
      ? `Amount: a ${formatGbp(order.amountDueMinor)} deposit, with the rest due on ${order.fulfilment.mode === 'delivery' ? 'delivery' : 'collection'}`
      : `Amount: ${formatGbp(order.amountDueMinor)}`,
    order.fulfilment.date
      ? `${order.fulfilment.mode === 'delivery' ? 'Delivery' : 'Collection'}: ${formatUkDate(order.fulfilment.date)}`
      : '',
    `Unpaid for: ${input.daysUnpaid} day${input.daysUnpaid === 1 ? '' : 's'}`,
    `Reminders already sent: ${input.priorCount}`,
    `Payment link, to include verbatim: ${approvalUrl}`,
  ].filter(Boolean).join('\n');

  const system = [
    NUDGE_SYSTEM,
    `\n\n${TONE_GUIDANCE[tone]}`,
    input.personaTone.trim() ? `\n\nHow the seller writes: "${input.personaTone.trim()}"` : '',
    `\n\nOrder details:\n${details}`,
  ].join('');

  try {
    const drafted = await generateStructured(
      {
        schemaName: 'nudge_draft',
        schema: nudgeDraftSchema,
        jsonSchema: NUDGE_JSON_SCHEMA,
        system,
        text: 'Write the reminder.',
      },
      transport,
      model,
    );
    const text = humaniseIsoDates(drafted.text.trim());
    if (nudgeProblem(text, approvalUrl, order.amountDueMinor) !== null) {
      return { ...fallback(), shouldSkip: drafted.shouldSkip, skipReason: drafted.skipReason };
    }
    return { text, source: 'ai', shouldSkip: drafted.shouldSkip, skipReason: drafted.skipReason };
  } catch {
    return fallback();
  }
}
