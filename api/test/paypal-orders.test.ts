import { describe, expect, it, vi } from 'vitest';
import { createPayPalOrder } from '../src/paypal/orders.js';
import type { PayPalFetch } from '../src/paypal/client.js';
import type { OrderDoc } from '../src/domain/orders.js';

const order = {
  id: 'order-xyz', status: 'draft',
  buyerName: 'Jess M', buyerHandle: 'jess.mcr', buyerEmail: null, channel: 'instagram',
  lineItems: [
    { id: 'li-1', productId: 'p1', variantIds: ['10-inch'], nameRaw: 'lemon drizzle', nameResolved: 'Lemon drizzle cake', qty: 1, unitPriceMinor: 4200, lineTotalMinor: 4200, matchConfidence: 1, matchMethod: 'exact' },
    { id: 'li-2', productId: 'p2', variantIds: ['box-of-6'], nameRaw: 'brownies', nameResolved: 'Brownie box', qty: 1, unitPriceMinor: 1400, lineTotalMinor: 1400, matchConfidence: 1, matchMethod: 'exact' },
  ],
  subtotalMinor: 5600, depositMinor: null, amountDueMinor: 5600, currency: 'GBP',
  fulfilment: { mode: 'collection', date: '2026-10-10', notes: null },
  ambiguities: [], paypalOrderId: null, approvalUrl: null, paypalCaptureId: null,
  paypalInvoiceId: null, draftedReply: null,
  nudge: { count: 0, lastSentAt: null, lastText: null, channel: null, snoozedUntil: null },
  sourceKind: 'screenshot', extractionModel: 'gpt-5.5', expiresAt: null,
} as unknown as OrderDoc;

const created = {
  id: 'PP-ORDER-1',
  status: 'PAYER_ACTION_REQUIRED',
  links: [
    { rel: 'self', method: 'GET', href: 'https://api.sandbox.paypal.com/v2/checkout/orders/PP-ORDER-1' },
    { rel: 'payer-action', method: 'GET', href: 'https://www.sandbox.paypal.com/checkoutnow?token=PP-ORDER-1' },
  ],
};

describe('createPayPalOrder', () => {
  it('returns the id and the approval link', async () => {
    const call: PayPalFetch = async () => created;
    const out = await createPayPalOrder(order, 'seller-a', call);
    expect(out.paypalOrderId).toBe('PP-ORDER-1');
    expect(out.approvalUrl).toBe('https://www.sandbox.paypal.com/checkoutnow?token=PP-ORDER-1');
  });

  it('reads the link from rel=payer-action, which is what PayPal sends', async () => {
    // Verified against a real sandbox order: with experience_context there is
    // no rel=approve, only payer-action.
    const call: PayPalFetch = async () => ({
      ...created,
      links: [{ rel: 'payer-action', method: 'GET', href: 'https://x/checkoutnow?token=T' }],
    });
    const out = await createPayPalOrder(order, 'seller-a', call);
    expect(out.approvalUrl).toBe('https://x/checkoutnow?token=T');
  });

  it('charges exactly the order amountDueMinor', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(order, 'seller-a', call);
    const body = call.mock.calls[0]![1].body as {
      purchase_units: { amount: { value: string; currency_code: string } }[];
    };
    expect(body.purchase_units[0]!.amount.value).toBe('56.00');
    expect(body.purchase_units[0]!.amount.currency_code).toBe('GBP');
  });

  it('charges the deposit, not the subtotal, when one is set', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(
      { ...order, depositMinor: 2000, amountDueMinor: 2000 },
      'seller-a',
      call,
    );
    const body = call.mock.calls[0]![1].body as { purchase_units: { amount: { value: string } }[] };
    expect(body.purchase_units[0]!.amount.value).toBe('20.00');
  });

  it('omits the item breakdown when a deposit means items would not add up', async () => {
    // PayPal rejects the order if item_total does not equal the sum of items,
    // and a GBP 20 deposit against GBP 56 of goods never will.
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(
      { ...order, depositMinor: 2000, amountDueMinor: 2000 },
      'seller-a',
      call,
    );
    const unit = (call.mock.calls[0]![1].body as { purchase_units: Record<string, unknown>[] })
      .purchase_units[0]!;
    expect(unit.items).toBeUndefined();
    expect((unit.amount as Record<string, unknown>).breakdown).toBeUndefined();
  });

  it('sends items whose total equals the amount when there is no deposit', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(order, 'seller-a', call);
    const unit = (call.mock.calls[0]![1].body as { purchase_units: Record<string, unknown>[] })
      .purchase_units[0]!;
    const items = unit.items as { unit_amount: { value: string }; quantity: string }[];
    const sum = items.reduce(
      (t, i) => t + Math.round(Number(i.unit_amount.value) * 100) * Number(i.quantity),
      0,
    );
    expect(sum).toBe(5600);
    const breakdown = (unit.amount as { breakdown: { item_total: { value: string } } }).breakdown;
    expect(breakdown.item_total.value).toBe('56.00');
  });

  it('carries sellerId:orderId in custom_id so webhooks need no lookup', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(order, 'seller-a', call);
    const unit = (call.mock.calls[0]![1].body as { purchase_units: { custom_id: string }[] })
      .purchase_units[0]!;
    expect(unit.custom_id).toBe('seller-a:order-xyz');
  });

  it('sends an idempotency key derived from the order', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(order, 'seller-a', call);
    expect(call.mock.calls[0]![1].requestId).toContain('order-xyz');
  });

  it('asks for GBP and a UK experience with no shipping', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(order, 'seller-a', call);
    const body = JSON.stringify(call.mock.calls[0]![1].body);
    expect(body).toContain('en-GB');
    expect(body).toContain('NO_SHIPPING');
    expect(body).toContain('PAY_NOW');
  });

  it('throws when PayPal returns no approval link', async () => {
    const call: PayPalFetch = async () => ({ id: 'X', status: 'CREATED', links: [] });
    await expect(createPayPalOrder(order, 'seller-a', call)).rejects.toMatchObject({
      code: 'PAYPAL_UNAVAILABLE',
    });
  });

  it('refuses to create an order for nothing', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await expect(
      createPayPalOrder({ ...order, amountDueMinor: 0 }, 'seller-a', call),
    ).rejects.toThrow();
    expect(call).not.toHaveBeenCalled();
  });
});
