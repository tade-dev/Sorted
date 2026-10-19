import { FieldValue, type DocumentReference } from 'firebase-admin/firestore';
import { ApiError } from '../lib/errors.js';
import type { OrderDoc, OrderStatus } from './orders.js';

/**
 * Statuses the seller can cancel from. Processing and pending are left out
 * on purpose: the buyer is mid-payment, and cancelling under them would close
 * an order whose money is already moving.
 */
export const CANCELLABLE_STATUSES: readonly OrderStatus[] = ['draft', 'link_sent', 'declined'];

/** Unpaid orders with a link out. Drafts have no link, so nothing to expire. */
export const EXPIRABLE_STATUSES: readonly OrderStatus[] = ['link_sent', 'declined'];

/** Final, like paid. Nothing PayPal sends afterwards may reopen them. */
export const CLOSED_STATUSES: readonly OrderStatus[] = ['cancelled', 'expired'];

export function isClosed(status: unknown): status is 'cancelled' | 'expired' {
  return status === 'cancelled' || status === 'expired';
}

const HOUR_MS = 60 * 60 * 1000;

/** When an unpaid link becomes expired, or null if it was never sent. */
export function expiryDueMs(linkSentAt: unknown, ttlHours: number): number | null {
  if (!linkSentAt || typeof linkSentAt !== 'object' || !('toMillis' in linkSentAt)) return null;
  const ms = (linkSentAt as { toMillis: () => number }).toMillis();
  if (typeof ms !== 'number' || Number.isNaN(ms)) return null;
  return ms + ttlHours * HOUR_MS;
}

export function expiryFromNow(nowMs: number, ttlHours: number): number {
  return nowMs + ttlHours * HOUR_MS;
}

/**
 * Closes an order as cancelled or expired, in one transaction, or does
 * nothing if it already is.
 *
 * The PayPal order is not cancelled at PayPal, because the Orders API has no
 * way to void a CREATED or APPROVED checkout order. Instead its id joins
 * `supersededPaypalOrderIds`, the same list an edit uses, which the webhook
 * already refuses: an approval on it is never captured, and a capture on it is
 * recorded with `refundDue` instead of moving the order. Sorted is the only
 * thing that captures, so in practice the buyer is never charged.
 *
 * The status check is inside the transaction, so a capture that lands between
 * the caller's read and this write is never overwritten: paid is final, and
 * the close fails with ORDER_STATE_INVALID instead.
 */
export async function closeOrder(
  ref: DocumentReference,
  to: 'cancelled' | 'expired',
  allowedFrom: readonly OrderStatus[],
): Promise<{ closed: boolean; order: OrderDoc }> {
  const orderId = ref.id;
  return ref.firestore.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new ApiError(404, 'NOT_FOUND', 'No such order.');
    const order = snap.data() as OrderDoc;
    if (order.status === to) return { closed: false, order };
    if (!allowedFrom.includes(order.status)) {
      throw new ApiError(
        409,
        'ORDER_STATE_INVALID',
        `An order that is ${order.status} cannot become ${to}.`,
      );
    }

    const paypalOrderId = order.paypalOrderId;
    const superseded = paypalOrderId
      ? [...new Set([...(order.supersededPaypalOrderIds ?? []), paypalOrderId])]
      : order.supersededPaypalOrderIds;
    tx.update(ref, {
      status: to,
      [to === 'cancelled' ? 'cancelledAt' : 'expiredAt']: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...(paypalOrderId ? { supersededPaypalOrderIds: FieldValue.arrayUnion(paypalOrderId) } : {}),
    });
    // One row per order and kind, so a retried close cannot write a second.
    const eventId = `${to === 'cancelled' ? 'cancel' : 'expire'}-${orderId}`;
    tx.set(ref.collection('paymentEvents').doc(eventId), {
      id: eventId,
      eventType: to,
      paypalResourceId: paypalOrderId ?? null,
      amountMinor: null,
      raw: { source: to === 'cancelled' ? 'seller' : 'expiry_sweep', status: to, from: order.status },
      signatureVerified: false,
      receivedAt: FieldValue.serverTimestamp(),
      processedAt: FieldValue.serverTimestamp(),
      processingError: null,
    });

    const closed: OrderDoc = {
      ...order,
      status: to,
      ...(superseded ? { supersededPaypalOrderIds: superseded } : {}),
    };
    return { closed: true, order: closed };
  });
}
