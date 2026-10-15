import { replyDraftSchema } from './schemas.js';
import { generateStructured, type ChatTransport } from './client.js';
import { ApiError } from '../lib/errors.js';
import { formatUkDate, humaniseIsoDates } from '../domain/dates.js';
import { formatGbp } from '../domain/money.js';
import type { OrderDoc } from '../domain/orders.js';

export type ReplyTone = 'friendly' | 'short' | 'formal';

/** `checkout` asks the buyer to pay; `thank_you` thanks them once they have. */
export type ReplyMode = 'checkout' | 'thank_you';

export const THANK_YOU_SYSTEM = [
  'You write the thank-you message a UK small seller sends a buyer in a DM after the buyer has paid.',
  'Write as the seller, in their voice. A sample of how they write is given below; match it.',
  'UK English. Under 45 words. Warm, not corporate.',
  'Thank them, confirm payment is received, and name what they ordered.',
  'Do not include any link, price or total.',
  'Use no emoji unless the seller\'s own sample uses them.',
  'Do not promise a date, a time or anything else that is not in the order details given.',
  'When the order details include a date, copy it exactly. Never rewrite it as an ISO date.',
].join(' ');

export const REPLY_SYSTEM = [
  'You write the message a UK small seller sends back to a buyer in a DM, confirming their order and giving them a payment link.',
  'Write as the seller, in their voice. A sample of how they write is given below; match it.',
  'UK English. Under 60 words. Warm, not corporate.',
  'Include the payment link exactly once, exactly as given, with no words inside the URL and nothing appended to it.',
  'Do not invent a link, shorten it, or wrap it in markdown.',
  'Use no emoji unless the seller\'s own sample uses them.',
  'Do not promise a date, a time or anything else that is not in the order details given.',
  'When the order details include a date, copy it exactly. It is already written the way the buyer should read it, for example "Tue 13 Oct". Never rewrite it as an ISO date.',
  'Do not restate the itemised prices; name what they ordered and the total.',
].join(' ');

export const REPLY_JSON_SCHEMA: Record<string, unknown> = {
  type: 'object',
  additionalProperties: false,
  required: ['reply'],
  properties: { reply: { type: 'string' } },
};

const TONE_GUIDANCE: Record<ReplyTone, string> = {
  friendly: 'Tone: friendly and chatty, the way they would talk to a regular.',
  short: 'Tone: short. Two sentences at most, no small talk.',
  formal: 'Tone: formal and polite, but still a person, not a company.',
};

export async function draftReply(
  input: {
    order: OrderDoc;
    personaTone: string;
    approvalUrl: string;
    tone: ReplyTone;
    mode?: ReplyMode;
  },
  transport: ChatTransport,
  model: string,
): Promise<string> {
  const { order, approvalUrl, tone } = input;
  const thankYou = input.mode === 'thank_you';

  const items = order.lineItems
    .map((l) => `${l.qty} x ${l.nameResolved ?? l.nameRaw}`)
    .join(', ');

  const details = [
    `Buyer: ${order.buyerName ?? 'the buyer'}`,
    `They ordered: ${items}`,
    thankYou
      ? 'They have paid. The payment is in.'
      : order.depositMinor !== null
      ? `They are paying a deposit of ${formatGbp(order.amountDueMinor)} now, with the rest due on collection.`
      : `Total to pay: ${formatGbp(order.amountDueMinor)}`,
    order.fulfilment.date
      ? `${order.fulfilment.mode === 'delivery' ? 'Delivery' : 'Collection'}: ${formatUkDate(order.fulfilment.date)}`
      : '',
    order.fulfilment.notes ? `Note: ${order.fulfilment.notes}` : '',
    thankYou ? '' : `Payment link, to include verbatim: ${approvalUrl}`,
  ]
    .filter(Boolean)
    .join('\n');

  const system = [
    thankYou ? THANK_YOU_SYSTEM : REPLY_SYSTEM,
    `\n\n${TONE_GUIDANCE[tone]}`,
    input.personaTone.trim()
      ? `\n\nHow the seller writes: "${input.personaTone.trim()}"`
      : '',
    `\n\nOrder details:\n${details}`,
  ].join('');

  const { reply } = await generateStructured(
    {
      schemaName: 'reply_draft',
      schema: replyDraftSchema,
      jsonSchema: REPLY_JSON_SCHEMA,
      system,
      text: thankYou ? 'Write the thank-you message.' : 'Write the reply.',
      // No temperature: gpt-5.5 only accepts the default.
    },
    transport,
    model,
  );

  // A reply the seller pastes without the right link is worse than no reply:
  // the buyer cannot pay and nobody finds out until the chase.
  if (thankYou) {
    // A thank-you never carries a link; one appearing means the model made it up.
    if (/https?:\/\//i.test(reply)) {
      throw new ApiError(502, 'AI_PARSE_FAILED', 'Sorted could not write that thank-you message.');
    }
    return humaniseIsoDates(reply);
  }

  if (!reply.includes(approvalUrl)) {
    throw new ApiError(
      502,
      'AI_PARSE_FAILED',
      'Sorted could not write that reply correctly. The link is below — paste it into the chat yourself.',
    );
  }

  return humaniseIsoDates(reply);
}

/** Used when the model cannot write the reply. Same date wording, and the link is intact. */
export function fallbackReply(order: OrderDoc, approvalUrl: string): string {
  const items = order.lineItems
    .map((l) => `${l.qty} x ${l.nameResolved ?? l.nameRaw}`)
    .join(', ');
  const when = order.fulfilment.date
    ? ` for ${order.fulfilment.mode === 'delivery' ? 'delivery' : 'collection'} ${formatUkDate(order.fulfilment.date)}`
    : '';
  const who = order.buyerName ?? 'there';
  return `Hi ${who}! You're down for ${items}${when}. Total ${formatGbp(order.amountDueMinor)}. You can pay here: ${approvalUrl}`;
}

/** Used when the model cannot write the thank-you. No link, no amounts. */
export function fallbackThankYou(order: OrderDoc): string {
  const items = order.lineItems
    .map((l) => `${l.qty} x ${l.nameResolved ?? l.nameRaw}`)
    .join(', ');
  const when = order.fulfilment.date
    ? ` See you for ${order.fulfilment.mode === 'delivery' ? 'delivery' : 'collection'} ${formatUkDate(order.fulfilment.date)}.`
    : '';
  const who = order.buyerName ?? 'there';
  return `Thanks so much ${who}! Payment received for ${items}.${when}`;
}
