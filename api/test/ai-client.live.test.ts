import { readFileSync, existsSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { generateStructured, makeOpenAiTransport, toDataUri } from '../src/ai/client.js';
import { loadEnv } from '../src/env.js';

const envFile = existsSync('.env') ? readFileSync('.env', 'utf8') : '';
const key = envFile.match(/^OPENAI_API_KEY=(.+)$/m)?.[1]?.trim();
const model = envFile.match(/^OPENAI_VISION_MODEL=(.+)$/m)?.[1]?.trim();
const ready = Boolean(key) && Boolean(model) && model !== 'pending';

describe.skipIf(!ready)('generateStructured against the real model', () => {
  const env = loadEnv({
    NODE_ENV: 'test',
    PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
    OPENAI_API_KEY: key!, OPENAI_VISION_MODEL: model!,
    FIREBASE_PROJECT_ID: 'x', INTERNAL_TOKEN: 'x',
  });

  const schema = z.object({
    buyerName: z.string().nullable(),
    items: z.array(z.object({ nameRaw: z.string(), qty: z.number().int() })),
  });

  it('reads the canonical Jess screenshot into schema-valid JSON', async () => {
    const img = toDataUri(
      readFileSync('../samples/dm-screenshots/01.png'),
      'image/png',
    );

    const result = await generateStructured(
      {
        schemaName: 'probe',
        schema,
        jsonSchema: {
          type: 'object', additionalProperties: false,
          required: ['buyerName', 'items'],
          properties: {
            buyerName: { type: ['string', 'null'] },
            items: {
              type: 'array',
              items: {
                type: 'object', additionalProperties: false,
                required: ['nameRaw', 'qty'],
                properties: { nameRaw: { type: 'string' }, qty: { type: 'integer' } },
              },
            },
          },
        },
        system:
          'Extract what the buyer ordered from this chat screenshot. Quote their own words in nameRaw. "box of 6" describes one box, not a quantity of six.',
        images: [img],
      },
      makeOpenAiTransport(env),
      env.OPENAI_VISION_MODEL,
    );

    expect(result.buyerName).toMatch(/Jess/);
    expect(result.items).toHaveLength(2);
    // The gpt-4.1-mini failure this pinning was chosen to avoid: reading
    // "brownie box of 6" as qty 6 would bill GBP 84 instead of GBP 14.
    for (const item of result.items) expect(item.qty).toBe(1);
  }, 60_000);
});
