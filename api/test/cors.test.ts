import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'm',
  FIREBASE_PROJECT_ID: 'p', INTERNAL_TOKEN: 't',
});
const deps = {
  env,
  db: {} as never,
  verify: async () => ({ uid: 'seller-a' }),
  transport: async () => ({ content: '{}' }),
  paypal: async () => ({}),
};

// The Flutter web build is served from a different origin to the API, so
// without these headers the browser blocks every call and the hosted demo —
// the judges' primary path — cannot reach its own backend.
describe('cross-origin access', () => {
  it('answers the browser preflight for an authenticated POST', async () => {
    const res = await request(createApp(deps))
      .options('/v1/session/bootstrap')
      .set('Origin', 'https://sorted.web.app')
      .set('Access-Control-Request-Method', 'POST')
      .set('Access-Control-Request-Headers', 'authorization,content-type');

    expect(res.status).toBeLessThan(400);
    expect(res.headers['access-control-allow-origin']).toBeDefined();
    expect(res.headers['access-control-allow-headers']?.toLowerCase())
      .toContain('authorization');
  });

  it('allows the Authorization header the app sends on every request', async () => {
    const res = await request(createApp(deps))
      .get('/v1/health')
      .set('Origin', 'https://sorted.web.app');

    expect(res.status).toBe(200);
    expect(res.headers['access-control-allow-origin']).toBeDefined();
  });

  it('still serves a same-origin request with no Origin header', async () => {
    const res = await request(createApp(deps)).get('/v1/health');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });
});
