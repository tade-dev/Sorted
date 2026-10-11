import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { parseDm, type CatalogueBrief } from '../src/ai/parse_dm.js';
import { makeOpenAiTransport } from '../src/ai/client.js';
import { loadEnv } from '../src/env.js';

const envFile = existsSync('.env') ? readFileSync('.env', 'utf8') : '';
const key = envFile.match(/^OPENAI_API_KEY=(.+)$/m)?.[1]?.trim();
const model = envFile.match(/^OPENAI_VISION_MODEL=(.+)$/m)?.[1]?.trim();
const ready = Boolean(key) && Boolean(model) && model !== 'pending';

const catalogue: CatalogueBrief = [
  { id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200, variantLabels: ['8 inch', '10 inch'] },
  { id: 'p2', name: 'Brownie box', basePriceMinor: 1400, variantLabels: ['Box of 6', 'Box of 12'] },
];

describe.skipIf(!ready)('parseDm against the real model', () => {
  // Vitest still runs this callback when the suite is skipped, and loadEnv
  // throws on an empty key. Leave before that so `vitest run` stays quiet
  // on a machine with no .env.
  if (!ready) return;

  const env = loadEnv({
    NODE_ENV: 'test',
    PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
    OPENAI_API_KEY: key!, OPENAI_VISION_MODEL: model!,
    FIREBASE_PROJECT_ID: 'x', INTERNAL_TOKEN: 'x',
  });

  it('reads the canonical Jess screenshot correctly', async () => {
    const out = await parseDm(
      {
        image: {
          buffer: readFileSync('../samples/dm-screenshots/01.png'),
          mime: 'image/png',
        },
      },
      catalogue,
      '2026-10-04',
      makeOpenAiTransport(env),
      env.OPENAI_VISION_MODEL,
    );

    expect(out.buyerName).toMatch(/Jess/);
    expect(out.lineItems).toHaveLength(2);
    // "box of 6" is one box. Reading it as six would bill GBP 84 for GBP 14
    // of brownies — the exact error that drove the model choice.
    for (const item of out.lineItems) expect(item.qty).toBe(1);
    // "sat 10th oct" against a 2026-10-04 today is Saturday 10 October.
    expect(out.fulfilment.date).toBe('2026-10-10');
    expect(out.fulfilment.mode).toBe('collection');
  }, 90_000);
});
