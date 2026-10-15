import { createHmac, timingSafeEqual } from 'node:crypto';
import type { Timestamp } from 'firebase-admin/firestore';
import type { OrderDoc } from './orders.js';
import { formatGbp } from './money.js';
import { escapeHtml } from '../paypal/buyer_page.js';

const ID = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * The buyer's invoice is a public link, so it carries a signature instead of
 * a stored token: nothing new is written to Firestore, and a guessed seller
 * or order id alone never opens one.
 */
export function invoiceSignature(secret: string, sellerId: string, orderId: string): string {
  return createHmac('sha256', secret)
    .update(`invoice:${sellerId}:${orderId}`)
    .digest('base64url')
    .slice(0, 32);
}

export function verifyInvoiceSignature(
  secret: string,
  sellerId: string,
  orderId: string,
  signature: string,
): boolean {
  if (!ID.test(sellerId) || !ID.test(orderId)) return false;
  const expected = Buffer.from(invoiceSignature(secret, sellerId, orderId));
  const given = Buffer.from(signature);
  return given.length === expected.length && timingSafeEqual(given, expected);
}

export function invoiceUrl(baseUrl: string, secret: string, sellerId: string, orderId: string): string {
  return `${baseUrl}/v1/invoice/${sellerId}/${orderId}/${invoiceSignature(secret, sellerId, orderId)}`;
}

/** Short, stable reference the buyer can quote: INV- plus the order id's start. */
export function invoiceNumber(orderId: string): string {
  return `INV-${orderId.slice(0, 8).toUpperCase()}`;
}

const londonDate = (d: Date) =>
  d.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Europe/London' });

export type InvoiceOrder = Pick<
  OrderDoc,
  'id' | 'buyerName' | 'buyerHandle' | 'lineItems' | 'subtotalMinor' | 'depositMinor' | 'amountDueMinor' | 'paypalCaptureId'
> & { paidAt?: Timestamp | null };

export function invoicePage(opts: { shop: string | null; order: InvoiceOrder }): string {
  const { order } = opts;
  const shop = opts.shop ?? 'Your seller';
  const buyer = order.buyerName ?? order.buyerHandle ?? null;
  const paid = order.paidAt ? londonDate(order.paidAt.toDate()) : null;
  const rows = order.lineItems
    .map(
      (l) => `<tr><td>${escapeHtml(l.nameResolved ?? l.nameRaw)}</td><td class="n">${l.qty}</td><td class="n">${escapeHtml(formatGbp(l.lineTotalMinor))}</td></tr>`,
    )
    .join('\n');
  const deposit =
    order.depositMinor != null && order.depositMinor !== order.subtotalMinor
      ? `<tr><td colspan="2">Subtotal</td><td class="n">${escapeHtml(formatGbp(order.subtotalMinor))}</td></tr>
<tr><td colspan="2">Deposit paid now</td><td class="n">${escapeHtml(formatGbp(order.depositMinor))}</td></tr>`
      : '';
  const meta = [
    `<p>${escapeHtml(invoiceNumber(order.id))}</p>`,
    paid ? `<p>Paid ${escapeHtml(paid)} with PayPal</p>` : '<p>Paid with PayPal</p>',
    buyer ? `<p>For ${escapeHtml(buyer)}</p>` : '',
    order.paypalCaptureId ? `<p>PayPal reference ${escapeHtml(order.paypalCaptureId)}</p>` : '',
  ].join('\n  ');
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<meta name="robots" content="noindex">
<title>Invoice from ${escapeHtml(shop)}</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@700&amp;family=Plus+Jakarta+Sans:wght@400;600&amp;display=swap">
<style>
  body { margin: 0; background: #F5F7FA; color: #001C64; font-family: "Plus Jakarta Sans", sans-serif; }
  main { max-width: 28rem; margin: 0 auto; padding: 4.5rem 1.5rem 3rem; }
  .mark { margin: 0 0 1.5rem; font-weight: 600; font-size: 0.875rem; letter-spacing: 0.04em; color: #0070E0; }
  h1 { margin: 0; font-family: "Bricolage Grotesque", sans-serif; font-weight: 700; font-size: 1.75rem; letter-spacing: -0.03em; line-height: 1.25; }
  p { margin: 0.25rem 0 0; color: #515A6B; font-size: 1rem; line-height: 1.5; }
  .meta { margin-top: 1rem; }
  table { width: 100%; margin-top: 1.5rem; border-collapse: collapse; font-size: 1rem; }
  td { padding: 0.5rem 0; border-bottom: 1px solid #DCE2EA; vertical-align: top; }
  td.n { text-align: right; padding-left: 1rem; white-space: nowrap; }
  tr.total td { border-bottom: 0; font-weight: 600; padding-top: 0.75rem; }
  button { margin-top: 2rem; font: inherit; font-weight: 600; color: #0070E0; background: none; border: 0; padding: 0; cursor: pointer; }
  @media print { body { background: #fff; } main { padding-top: 1.5rem; } button { display: none; } }
</style>
</head>
<body>
<main>
  <p class="mark">Sorted</p>
  <h1>Invoice from ${escapeHtml(shop)}</h1>
  <div class="meta">
  ${meta}
  </div>
  <table>
<tr><td><p>Item</p></td><td class="n"><p>Qty</p></td><td class="n"><p>Amount</p></td></tr>
${rows}
${deposit}
<tr class="total"><td colspan="2">Total paid</td><td class="n">${escapeHtml(formatGbp(order.amountDueMinor))}</td></tr>
  </table>
  <button type="button" onclick="window.print()">Save as PDF</button>
</main>
</body>
</html>
`;
}
