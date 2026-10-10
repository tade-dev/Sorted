import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { extractCatalogue } from '../src/ai/extract_catalogue.js';
import { makeOpenAiTransport } from '../src/ai/client.js';
import { loadEnv } from '../src/env.js';

const envFile = existsSync('.env') ? readFileSync('.env', 'utf8') : '';
const key = envFile.match(/^OPENAI_API_KEY=(.+)$/m)?.[1]?.trim();
const model = envFile.match(/^OPENAI_VISION_MODEL=(.+)$/m)?.[1]?.trim();
const ready = Boolean(key) && Boolean(model) && model !== 'pending';

// The unit tests all inject a fake transport, so nothing exercised the real
// request extractCatalogue builds. That let a body the pinned model rejects
// outright ship green: gpt-5.5 only supports the default temperature, so
// sending 0.2 made every real extraction fail with AI_PARSE_FAILED.
describe.skipIf(!ready)('extractCatalogue against the real model', () => {
  const env = loadEnv({
    NODE_ENV: 'test',
    PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
    OPENAI_API_KEY: key!, OPENAI_VISION_MODEL: model!,
    FIREBASE_PROJECT_ID: 'x', INTERNAL_TOKEN: 'x',
  });

  it('builds a request the model actually accepts', async () => {
    const image = {
      buffer: readFileSync('../samples/dm-screenshots/01.png'),
      mime: 'image/png',
    };

    const result = await extractCatalogue(
      [image],
      makeOpenAiTransport(env),
      env.OPENAI_VISION_MODEL,
    );

    // The screenshot is a chat, not stock, so zero candidates is the right
    // answer. What matters is that the call succeeded and validated.
    expect(Array.isArray(result.candidates)).toBe(true);
  }, 90_000);
});
