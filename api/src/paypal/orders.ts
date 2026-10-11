import { ApiError } from '../lib/errors.js';
import { DEFAULT_PUBLIC_BASE_URL } from '../env.js';
import { toPayPalValue } from '../domain/money.js';
import type { OrderDoc } from '../domain/orders.js';
import type { PayPalFetch } from './client.js';

type CreatedOrder = {
  id: string;
  status: string;
  links?: { rel: string; href: string; method: string }[];
};

/**
 * Creates the order the buyer will approve.
 *
 * Shapes verified against a real sandbox order (docs/verified-facts.md):
 * with payment_source.paypal.experience_context the response status is
 * PAYER_ACTION_REQUIRED and the approval link is rel="payer-action" — there
 * is no rel="approve".
 */
export async function createPayPalOrder(
  order: OrderDoc,
  sellerId: string,
  call: PayPalFetch,
  publicBaseUrl: string = DEFAULT_PUBLIC_BASE_URL,
): Promise<{ paypalOrderId: string; approvalUrl: string }> {
  if (order.amountDueMinor <= 0) {
    throw new ApiError(
      400,
      'VALIDATION_FAILED',
      'There is nothing to charge for on this order.',
    );
  }

  const value = toPayPalValue(order.amountDueMinor);
  const takingDeposit = order.depositMinor !== null;
  const base = publicBaseUrl.replace(/\/+$/, '') || DEFAULT_PUBLIC_BASE_URL;

  // PayPal rejects the order unless item_total equals the sum of items, and a
  // deposit never equals the goods. Send the itemised breakdown only when the
  // buyer is paying for the whole order.
  const items = order.lineItems.map((line) => ({
    name: (line.nameResolved ?? line.nameRaw).slice(0, 127),
    quantity: String(line.qty),
    unit_amount: { currency_code: 'GBP', value: toPayPalValue(line.unitPriceMinor) },
  }));

  const purchaseUnit: Record<string, unknown> = {
    reference_id: order.id,
    custom_id: `${sellerId}:${order.id}`,
    amount: takingDeposit
      ? { currency_code: 'GBP', value }
      : {
          currency_code: 'GBP',
          value,
          breakdown: { item_total: { currency_code: 'GBP', value } },
        },
    ...(takingDeposit ? {} : { items }),
    ...(takingDeposit
      ? { description: `Deposit for order ${order.id.slice(0, 8)}` }
      : {}),
  };

  const created = (await call('/v2/checkout/orders', {
    method: 'POST',
    requestId: `create-${order.id}`,
    body: {
      intent: 'CAPTURE',
      purchase_units: [purchaseUnit],
      payment_source: {
        paypal: {
          experience_context: {
            brand_name: 'Sorted',
            locale: 'en-GB',
            user_action: 'PAY_NOW',
            shipping_preference: 'NO_SHIPPING',
            return_url: `${base}/v1/paypal/return`,
            cancel_url: `${base}/v1/paypal/cancel`,
          },
        },
      },
    },
  })) as CreatedOrder;

  const approval = created.links?.find((l) => l.rel === 'payer-action')?.href;
  if (!created.id || !approval) {
    throw new ApiError(
      502,
      'PAYPAL_UNAVAILABLE',
      'PayPal created the order but returned no checkout link. Try again.',
      { status: created.status },
    );
  }

  return { paypalOrderId: created.id, approvalUrl: approval };
}
