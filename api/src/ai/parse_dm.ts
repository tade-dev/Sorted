import { dmOrderSchema, type DmOrder } from './schemas.js';
import { generateStructured, toDataUri, type ChatTransport } from './client.js';
import { ApiError } from '../lib/errors.js';

export type CatalogueBrief = {
  id: string;
  name: string;
  basePriceMinor: number;
  variantLabels: string[];
}[];

export const DM_ORDER_SYSTEM = [
  'You read a conversation between a UK small seller and a buyer, and extract the single order the buyer is placing.',
  'The seller is the party offering goods; the buyer is the other party.',
  'Quote the buyer\'s own words in nameRaw, not a tidied-up version.',
  'A phrase like "box of 6" or "pack of 12" describes ONE item whose variant is that size. It is not a quantity of 6 or 12. Only set qty above 1 when the buyer clearly asks for several of something.',
  'Match variantLabels to the seller\'s own variant labels where you can; the catalogue is given below.',
  'Resolve relative dates ("next Saturday", "the 10th") against today\'s date, given below, and return an ISO date.',
  'If the buyer never stated a size, a quantity or a date, do not guess. Add an ambiguity with a question the seller can answer in one tap, and leave the field null or empty.',
  'If the conversation contains no order at all — a receipt, a menu, small talk, a photo of something else — return an empty lineItems array rather than inventing one.',
  'Never state a price. Prices come from the seller\'s catalogue, not from you.',
].join(' ');

export const DM_ORDER_JSON_SCHEMA: Record<string, unknown> = {
  type: 'object',
  additionalProperties: false,
  required: [
    'buyerName', 'buyerHandle', 'buyerEmail', 'channel', 'lineItems',
    'fulfilment', 'depositRequestedMinor', 'ambiguities', 'overallConfidence',
  ],
  properties: {
    buyerName: { type: ['string', 'null'] },
    buyerHandle: { type: ['string', 'null'] },
    buyerEmail: { type: ['string', 'null'] },
    channel: {
      type: 'string',
      enum: ['instagram', 'tiktok', 'whatsapp', 'other', 'unknown'],
    },
    lineItems: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['nameRaw', 'qty', 'variantLabels'],
        properties: {
          nameRaw: { type: 'string' },
          qty: { type: 'integer' },
          variantLabels: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    fulfilment: {
      type: 'object', additionalProperties: false,
      required: ['mode', 'date', 'notes'],
      properties: {
        mode: { type: 'string', enum: ['collection', 'delivery', 'unknown'] },
        date: { type: ['string', 'null'] },
        notes: { type: ['string', 'null'] },
      },
    },
    depositRequestedMinor: { type: ['integer', 'null'] },
    ambiguities: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['field', 'kind', 'question', 'options', 'blocking'],
        properties: {
          field: { type: 'string' },
          kind: {
            type: 'string',
            enum: ['missing', 'unclear', 'unknown_product', 'price_conflict', 'qty_unclear'],
          },
          question: { type: 'string' },
          options: { type: 'array', items: { type: 'string' } },
          blocking: { type: 'boolean' },
        },
      },
    },
    overallConfidence: { type: 'number' },
  },
};

function describeCatalogue(catalogue: CatalogueBrief): string {
  if (catalogue.length === 0) return 'The seller has no products in their catalogue yet.';
  return [
    "The seller's catalogue, for matching names and variant labels:",
    ...catalogue.map(
      (p) =>
        `- ${p.name}${p.variantLabels.length ? ` (${p.variantLabels.join(', ')})` : ''}`,
    ),
  ].join('\n');
}

export async function parseDm(
  input: { image?: { buffer: Buffer; mime: string }; text?: string },
  catalogue: CatalogueBrief,
  today: string,
  transport: ChatTransport,
  model: string,
): Promise<DmOrder> {
  if (!input.image && !input.text?.trim()) {
    throw new ApiError(
      400,
      'VALIDATION_FAILED',
      'Share a screenshot or paste the message — one image or text is required.',
    );
  }

  const system = [
    DM_ORDER_SYSTEM,
    `\n\nToday is ${today}.`,
    `\n\n${describeCatalogue(catalogue)}`,
  ].join('');

  return generateStructured(
    {
      schemaName: 'dm_order',
      schema: dmOrderSchema,
      jsonSchema: DM_ORDER_JSON_SCHEMA,
      system,
      ...(input.text?.trim() ? { text: input.text.trim() } : {}),
      ...(input.image
        ? { images: [toDataUri(input.image.buffer, input.image.mime)] }
        : {}),
      // No temperature: gpt-5.5 only accepts the default.
    },
    transport,
    model,
  );
}
