import { replyDraftSchema } from './schemas.js';
import { generateStructured, type ChatTransport } from './client.js';
import { ApiError } from '../lib/errors.js';
import { formatGbp } from '../domain/money.js';
import type { OrderDoc } from '../domain/orders.js';

export type ReplyTone = 'friendly' | 'short' | 'formal';

export const REPLY_SYSTEM = [
  'You write the message a UK small seller sends back to a buyer in a DM, confirming their order and giving them a payment link.',
  'Write as the seller, in their voice. A sample of how they write is given below; match it.',
  'UK English. Under 60 words. Warm, not corporate.',
  'Include the payment link exactly once, exactly as given, with no words inside the URL and nothing appended to it.',
  'Do not invent a link, shorten it, or wrap it in markdown.',
  'Use no emoji unless the seller\'s own sample uses them.',
  'Do not promise a date, a time or anything else that is not in the order details given.',
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
  },
  transport: ChatTransport,
  model: string,
): Promise<string> {
  const { order, approvalUrl, tone } = input;

  const items = order.lineItems
    .map((l) => `${l.qty} x ${l.nameResolved ?? l.nameRaw}`)
    .join(', ');

  const details = [
    `Buyer: ${order.buyerName ?? 'the buyer'}`,
    `They ordered: ${items}`,
    order.depositMinor !== null
      ? `They are paying a deposit of ${formatGbp(order.amountDueMinor)} now, with the rest due on collection.`
      : `Total to pay: ${formatGbp(order.amountDueMinor)}`,
    order.fulfilment.date
      ? `${order.fulfilment.mode === 'delivery' ? 'Delivery' : 'Collection'}: ${order.fulfilment.date}`
      : '',
    order.fulfilment.notes ? `Note: ${order.fulfilment.notes}` : '',
    `Payment link, to include verbatim: ${approvalUrl}`,
  ]
    .filter(Boolean)
    .join('\n');

  const system = [
    REPLY_SYSTEM,
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
      text: 'Write the reply.',
      // No temperature: gpt-5.5 only accepts the default.
    },
    transport,
    model,
  );

  // A reply the seller pastes without the right link is worse than no reply:
  // the buyer cannot pay and nobody finds out until the chase.
  if (!reply.includes(approvalUrl)) {
    throw new ApiError(
      502,
      'AI_PARSE_FAILED',
      'Sorted could not write that reply correctly. The link is below — paste it into the chat yourself.',
    );
  }

  return reply;
}
