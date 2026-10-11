import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { makePayPalClient } from '../src/paypal/client.js';
import { createPayPalOrder } from '../src/paypal/orders.js';
import { loadEnv } from '../src/env.js';
import type { OrderDoc } from '../src/domain/orders.js';

const envFile = existsSync('.env') ? readFileSync('.env', 'utf8') : '';
const id = envFile.match(/^PAYPAL_CLIENT_ID=(.+)$/m)?.[1]?.trim();
const secret = envFile.match(/^PAYPAL_CLIENT_SECRET=(.+)$/m)?.[1]?.trim();
const ready = Boolean(id) && Boolean(secret);

const order = {
  id: 'live-probe-order',
  lineItems: [
    { id: 'li-1', productId: 'p1', variantIds: [], nameRaw: 'x', nameResolved: 'Lemon drizzle cake (10 inch)', qty: 1, unitPriceMinor: 4200, lineTotalMinor: 4200, matchConfidence: 1, matchMethod: 'exact' },
    { id: 'li-2', productId: 'p2', variantIds: [], nameRaw: 'y', nameResolved: 'Brownie box (Box of 6)', qty: 1, unitPriceMinor: 1400, lineTotalMinor: 1400, matchConfidence: 1, matchMethod: 'exact' },
  ],
  subtotalMinor: 5600, depositMinor: null, amountDueMinor: 5600, currency: 'GBP',
} as unknown as OrderDoc;

describe.skipIf(!ready)('createPayPalOrder against the real sandbox', () => {
  const env = loadEnv({
    NODE_ENV: 'test',
    PAYPAL_CLIENT_ID: id!, PAYPAL_CLIENT_SECRET: secret!, PAYPAL_WEBHOOK_ID: 'x',
    OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'm',
    FIREBASE_PROJECT_ID: 'x', INTERNAL_TOKEN: 'x',
  });

  it('builds a body PayPal accepts, and returns a usable checkout link', async () => {
    const unique = { ...order, id: `live-probe-${Date.now()}` };
    const out = await createPayPalOrder(unique, 'seller-live', makePayPalClient(env));

    expect(out.paypalOrderId).toMatch(/^[A-Z0-9]+$/);
    expect(out.approvalUrl).toContain('checkoutnow?token=');
    expect(out.approvalUrl).toContain(out.paypalOrderId);
  }, 60_000);

  it('is accepted with a deposit, where the items would not add up', async () => {
    const deposit = {
      ...order,
      id: `live-probe-dep-${Date.now()}`,
      depositMinor: 2000,
      amountDueMinor: 2000,
    };
    const out = await createPayPalOrder(deposit, 'seller-live', makePayPalClient(env));
    expect(out.approvalUrl).toContain('checkoutnow?token=');
  }, 60_000);
});
