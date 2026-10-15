import { describe, expect, it } from 'vitest';
import { DEFAULT_PUBLIC_BASE_URL, loadEnv } from '../src/env.js';

const valid = {
  NODE_ENV: 'test',
  PORT: '3000',
  PAYPAL_CLIENT_ID: 'sb-client-id',
  PAYPAL_CLIENT_SECRET: 'sb-secret',
  PAYPAL_WEBHOOK_ID: 'wh-id',
  OPENAI_API_KEY: 'sk-test',
  OPENAI_VISION_MODEL: 'gpt-test-vision',
  FIREBASE_PROJECT_ID: 'sorted-test',
  INTERNAL_TOKEN: 'internal-secret',
};

describe('loadEnv', () => {
  it('parses a complete environment', () => {
    const env = loadEnv(valid);
    expect(env.PORT).toBe(3000);
    expect(env.PAYPAL_ENV).toBe('sandbox');
  });

  it('defaults PORT to 3000 when absent', () => {
    const { PORT, ...rest } = valid;
    expect(loadEnv(rest).PORT).toBe(3000);
  });

  it('rejects a missing secret', () => {
    const { PAYPAL_CLIENT_SECRET, ...rest } = valid;
    expect(() => loadEnv(rest)).toThrow(/PAYPAL_CLIENT_SECRET/);
  });

  it('rejects an empty secret rather than deploying with blank config', () => {
    expect(() => loadEnv({ ...valid, PAYPAL_CLIENT_SECRET: '' })).toThrow(
      /PAYPAL_CLIENT_SECRET/,
    );
  });

  it('rejects an empty OpenAI key', () => {
    expect(() => loadEnv({ ...valid, OPENAI_API_KEY: '' })).toThrow(/OPENAI_API_KEY/);
  });

  it('rejects a non-numeric PORT', () => {
    expect(() => loadEnv({ ...valid, PORT: 'eighty' })).toThrow(/PORT/);
  });

  it('defaults to the sandbox PayPal environment', () => {
    expect(loadEnv(valid).PAYPAL_ENV).toBe('sandbox');
    expect(loadEnv(valid).PAYPAL_API_BASE).toBe('https://api-m.sandbox.paypal.com');
    expect(loadEnv({ ...valid, PAYPAL_ENV: 'nonsense' }).PAYPAL_ENV).toBe('sandbox');
  });

  it('switches to live PayPal only when PAYPAL_ENV=live', () => {
    const env = loadEnv({ ...valid, PAYPAL_ENV: 'live' });
    expect(env.PAYPAL_ENV).toBe('live');
    expect(env.PAYPAL_API_BASE).toBe('https://api-m.paypal.com');
  });

  it('lists every missing variable in one message, not just the first', () => {
    const { PAYPAL_WEBHOOK_ID, OPENAI_VISION_MODEL, INTERNAL_TOKEN, ...rest } = valid;
    try {
      loadEnv(rest);
      throw new Error('expected loadEnv to throw');
    } catch (err) {
      const msg = (err as Error).message;
      expect(msg).toContain('PAYPAL_WEBHOOK_ID');
      expect(msg).toContain('OPENAI_VISION_MODEL');
      expect(msg).toContain('INTERNAL_TOKEN');
    }
  });

  it('says a variable is missing rather than quoting a type error', () => {
    // "expected string, received undefined" tells an operator staring at a
    // hosting dashboard nothing about what to type.
    const { INTERNAL_TOKEN, ...rest } = valid;
    expect(() => loadEnv(rest)).toThrow(/missing or empty/);
    expect(() => loadEnv(rest)).not.toThrow(/received undefined/);
  });

  it('points at the file that lists what to set', () => {
    const { INTERNAL_TOKEN, ...rest } = valid;
    expect(() => loadEnv(rest)).toThrow(/\.env\.example/);
  });

  it('defaults the public base URL when it is absent or empty', () => {
    expect(loadEnv(valid).PUBLIC_BASE_URL).toBe(DEFAULT_PUBLIC_BASE_URL);
    expect(loadEnv({ ...valid, PUBLIC_BASE_URL: '' }).PUBLIC_BASE_URL).toBe(DEFAULT_PUBLIC_BASE_URL);
    expect(loadEnv({ ...valid, PUBLIC_BASE_URL: '   ' }).PUBLIC_BASE_URL).toBe(DEFAULT_PUBLIC_BASE_URL);
  });

  it('uses a configured public base URL without a trailing slash', () => {
    expect(loadEnv({ ...valid, PUBLIC_BASE_URL: 'https://pay.example.test/' }).PUBLIC_BASE_URL)
      .toBe('https://pay.example.test');
  });

  it('rejects a public base URL that is not an absolute http(s) URL', () => {
    expect(() => loadEnv({ ...valid, PUBLIC_BASE_URL: 'not a url' })).toThrow(/PUBLIC_BASE_URL/);
  });

  it('separates a genuinely invalid value from a missing one', () => {
    const { INTERNAL_TOKEN, ...rest } = valid;
    const msg = (() => {
      try { loadEnv({ ...rest, PORT: 'eighty' }); return ''; }
      catch (e) { return (e as Error).message; }
    })();
    expect(msg).toMatch(/missing or empty: .*INTERNAL_TOKEN/);
    expect(msg).toMatch(/invalid: .*PORT/);
  });
});
