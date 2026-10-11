import { afterEach, describe, expect, it, vi } from 'vitest';
import { makePayPalClient } from '../src/paypal/client.js';
import { loadEnv } from '../src/env.js';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'id', PAYPAL_CLIENT_SECRET: 'secret', PAYPAL_WEBHOOK_ID: 'wh',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'm',
  FIREBASE_PROJECT_ID: 'p', INTERNAL_TOKEN: 't',
});

afterEach(() => vi.unstubAllGlobals());

function stubFetch(handler: (url: string, init: RequestInit) => unknown) {
  const spy = vi.fn(async (url: string, init: RequestInit) => ({
    ok: true,
    status: 200,
    json: async () => handler(url, init),
    text: async () => '',
  }));
  vi.stubGlobal('fetch', spy);
  return spy;
}

describe('makePayPalClient', () => {
  it('gets a token then calls the endpoint with it', async () => {
    const spy = stubFetch((url) =>
      url.includes('/v1/oauth2/token')
        ? { access_token: 'tok-1', expires_in: 32400 }
        : { id: 'ORDER-1' },
    );

    const call = makePayPalClient(env);
    const out = await call('/v2/checkout/orders', { method: 'POST', body: { a: 1 } });

    expect(out).toEqual({ id: 'ORDER-1' });
    const second = spy.mock.calls[1]!;
    expect((second[1].headers as Record<string, string>).Authorization).toBe('Bearer tok-1');
  });

  it('reuses a cached token rather than fetching one per call', async () => {
    const spy = stubFetch((url) =>
      url.includes('/v1/oauth2/token')
        ? { access_token: 'tok-1', expires_in: 32400 }
        : { ok: true },
    );

    const call = makePayPalClient(env);
    await call('/v2/checkout/orders', { method: 'POST' });
    await call('/v2/checkout/orders', { method: 'POST' });

    const tokenCalls = spy.mock.calls.filter(([u]) => String(u).includes('/oauth2/token'));
    expect(tokenCalls).toHaveLength(1);
  });

  it('fetches a fresh token once the old one is near expiry', async () => {
    const spy = stubFetch((url) =>
      url.includes('/v1/oauth2/token')
        ? { access_token: 'tok', expires_in: 60 }
        : { ok: true },
    );

    let now = 1_000_000;
    const call = makePayPalClient(env, () => now);
    await call('/v2/checkout/orders', { method: 'POST' });
    now += 59_000; // inside the 60s safety margin
    await call('/v2/checkout/orders', { method: 'POST' });

    const tokenCalls = spy.mock.calls.filter(([u]) => String(u).includes('/oauth2/token'));
    expect(tokenCalls).toHaveLength(2);
  });

  it('sends PayPal-Request-Id when given one, for idempotency', async () => {
    const spy = stubFetch((url) =>
      url.includes('token') ? { access_token: 't', expires_in: 32400 } : { ok: true },
    );
    const call = makePayPalClient(env);
    await call('/v2/checkout/orders', { method: 'POST', requestId: 'capture-abc' });

    const headers = spy.mock.calls[1]![1].headers as Record<string, string>;
    expect(headers['PayPal-Request-Id']).toBe('capture-abc');
  });

  it('only ever talks to the sandbox host', async () => {
    const spy = stubFetch((url) =>
      url.includes('token') ? { access_token: 't', expires_in: 32400 } : { ok: true },
    );
    const call = makePayPalClient(env);
    await call('/v2/checkout/orders', { method: 'POST' });
    for (const [url] of spy.mock.calls) {
      expect(String(url)).toContain('api-m.sandbox.paypal.com');
    }
  });

  it('raises PAYPAL_UNAVAILABLE on a 5xx', async () => {
    vi.stubGlobal('fetch', vi.fn(async (url: string) => {
      if (String(url).includes('token')) {
        return { ok: true, status: 200, json: async () => ({ access_token: 't', expires_in: 32400 }), text: async () => '' };
      }
      return { ok: false, status: 503, json: async () => ({}), text: async () => 'upstream down' };
    }));

    const call = makePayPalClient(env);
    await expect(call('/v2/checkout/orders', { method: 'POST' })).rejects.toMatchObject({
      code: 'PAYPAL_UNAVAILABLE',
    });
  });

  it('raises PAYPAL_UNAVAILABLE on a 422, with PayPal\'s own detail', async () => {
    vi.stubGlobal('fetch', vi.fn(async (url: string) => {
      if (String(url).includes('token')) {
        return { ok: true, status: 200, json: async () => ({ access_token: 't', expires_in: 32400 }), text: async () => '' };
      }
      return {
        ok: false, status: 422,
        json: async () => ({ name: 'UNPROCESSABLE_ENTITY', details: [{ issue: 'AMOUNT_MISMATCH' }] }),
        text: async () => '',
      };
    }));

    const call = makePayPalClient(env);
    await expect(call('/v2/checkout/orders', { method: 'POST' })).rejects.toMatchObject({
      code: 'PAYPAL_UNAVAILABLE',
    });
  });
});
