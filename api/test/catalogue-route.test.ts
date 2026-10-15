import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { resolvePhotoIndex } from '../src/routes/catalogue.js';
import { loadEnv } from '../src/env.js';
import type { ChatTransport } from '../src/ai/client.js';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'p', INTERNAL_TOKEN: 't',
});

const transport: ChatTransport = async () => ({
  content: JSON.stringify({
    candidates: [
      {
        name: 'Lemon drizzle cake', description: 'Zesty.', basePriceMinor: 3200,
        variants: [{ axis: 'size', label: '8 inch', priceDeltaMinor: 0 }],
        confidence: 0.9, ambiguities: [],
      },
    ],
  }),
});

const deps = {
  env,
  db: {} as never,
  verify: async (t: string) => {
    if (t === 'good') return { uid: 'seller-a' };
    throw new Error('no');
  },
  transport,
};

const png = Buffer.from('89504e470d0a1a0a', 'hex');

describe('POST /v1/catalogue/extract', () => {
  it('returns candidates for an authenticated seller', async () => {
    const res = await request(createApp(deps))
      .post('/v1/catalogue/extract')
      .set('Authorization', 'Bearer good')
      .attach('images', png, { filename: 'cake.png', contentType: 'image/png' });

    expect(res.status).toBe(200);
    expect(res.body.candidates[0].name).toBe('Lemon drizzle cake');
    // Extraction must not write; the seller confirms first.
    expect(res.body.candidates[0].tempId).toBeTypeOf('string');
    // One photo: the product can only have come from it.
    expect(res.body.candidates[0].photoIndex).toBe(0);
  });

  it('401s without a token', async () => {
    const res = await request(createApp(deps))
      .post('/v1/catalogue/extract')
      .attach('images', png, { filename: 'c.png', contentType: 'image/png' });
    expect(res.status).toBe(401);
  });

  it('400s when no image is attached', async () => {
    const res = await request(createApp(deps))
      .post('/v1/catalogue/extract')
      .set('Authorization', 'Bearer good');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
  });

  it('400s on a sixth image rather than silently dropping it', async () => {
    const req = request(createApp(deps))
      .post('/v1/catalogue/extract')
      .set('Authorization', 'Bearer good');
    for (let i = 0; i < 6; i++) {
      req.attach('images', png, { filename: `c${i}.png`, contentType: 'image/png' });
    }
    const res = await req;
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
  });

  it('400s on a file over 8MB rather than truncating it', async () => {
    const big = Buffer.alloc(9 * 1024 * 1024, 1);
    const res = await request(createApp(deps))
      .post('/v1/catalogue/extract')
      .set('Authorization', 'Bearer good')
      .attach('images', big, { filename: 'huge.png', contentType: 'image/png' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
  });

  it('400s on a non-image masquerading as one', async () => {
    const res = await request(createApp(deps))
      .post('/v1/catalogue/extract')
      .set('Authorization', 'Bearer good')
      .attach('images', Buffer.from('%PDF-1.4'), {
        filename: 'notes.pdf', contentType: 'application/pdf',
      });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
  });

  it('passes an empty candidate list through for a photo of nothing', async () => {
    const empty: ChatTransport = async () => ({ content: JSON.stringify({ candidates: [] }) });
    const res = await request(createApp({ ...deps, transport: empty }))
      .post('/v1/catalogue/extract')
      .set('Authorization', 'Bearer good')
      .attach('images', png, { filename: 'floor.png', contentType: 'image/png' });
    expect(res.status).toBe(200);
    expect(res.body.candidates).toEqual([]);
  });
});

describe('resolvePhotoIndex', () => {
  it('keeps an in-range index', () => expect(resolvePhotoIndex(2, 3)).toBe(2));
  it('drops an out-of-range or negative index', () => {
    expect(resolvePhotoIndex(3, 3)).toBeNull();
    expect(resolvePhotoIndex(-1, 3)).toBeNull();
  });
  it('falls back to the only photo when there is one', () => expect(resolvePhotoIndex(null, 1)).toBe(0));
  it('stays null for several photos when unsure', () => expect(resolvePhotoIndex(null, 2)).toBeNull());
});
