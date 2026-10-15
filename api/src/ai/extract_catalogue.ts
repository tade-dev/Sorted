import {
  catalogueExtractionSchema,
  type CatalogueExtraction,
} from './schemas.js';
import { generateStructured, toDataUri, type ChatTransport } from './client.js';

export const CATALOGUE_SYSTEM = [
  'You extract product listings for a UK small seller\'s catalogue from photos of their stock.',
  'Prices are GBP, returned as integer pence (a GBP 32.00 cake is 3200).',
  'State only what you can see or read in the image.',
  'If no price is visible for a product, set basePriceMinor to null and add an ambiguity asking the seller for it.',
  'Never invent prices, sizes or flavours. A guess that looks right is worse than a question.',
  'Variants are the choices a buyer makes: size, colour, flavour. priceDeltaMinor is the difference from the base price, and may be negative.',
  'If the photo shows no sellable products at all, return an empty candidates array.',
  'Write descriptions in UK English, under 240 characters, as the seller would.',
  'Photos are numbered from 0 in the order given. Set photoIndex to the number of the photo the product is shown most clearly in, or null if unsure.',
].join(' ');

export const CATALOGUE_JSON_SCHEMA: Record<string, unknown> = {
  type: 'object',
  additionalProperties: false,
  required: ['candidates'],
  properties: {
    candidates: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'description', 'basePriceMinor', 'variants', 'confidence', 'ambiguities', 'photoIndex'],
        properties: {
          name: { type: 'string' },
          description: { type: 'string' },
          basePriceMinor: { type: ['integer', 'null'] },
          variants: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['axis', 'label', 'priceDeltaMinor'],
              properties: {
                axis: { type: 'string', enum: ['size', 'colour', 'flavour', 'other'] },
                label: { type: 'string' },
                priceDeltaMinor: { type: 'integer' },
              },
            },
          },
          confidence: { type: 'number' },
          photoIndex: { type: ['integer', 'null'] },
          ambiguities: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
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
        },
      },
    },
  },
};

export async function extractCatalogue(
  images: { buffer: Buffer; mime: string }[],
  transport: ChatTransport,
  model: string,
): Promise<CatalogueExtraction> {
  return generateStructured(
    {
      schemaName: 'catalogue_extraction',
      schema: catalogueExtractionSchema,
      jsonSchema: CATALOGUE_JSON_SCHEMA,
      system: CATALOGUE_SYSTEM,
      images: images.map((i) => toDataUri(i.buffer, i.mime)),
      // No temperature: gpt-5.5 only accepts the default. The spec's 0.2 for
      // extraction is not expressible on this model, and the determinism it
      // was reaching for is carried by the strict json_schema instead.
    },
    transport,
    model,
  );
}
