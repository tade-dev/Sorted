import { FieldValue, type DocumentReference } from 'firebase-admin/firestore';
import type { PayPalFetch } from './client.js';
import {
  capturePayPalOrder,
  getPayPalOrder,
  paypalIssue,
  reconcileAction,
  type ReconcileAction,
} from './events.js';
import { assertTransition, type OrderStatus } from '../domain/orders.js';

/** Statuses a PayPal check can still move. */
export const OPEN_STATUSES: OrderStatus[] = ['link_sent', 'processing', 'pending'];

async function applyMove(
  ref: DocumentReference,
  orderId: string,
  from: OrderStatus,
  action: Extract<ReconcileAction, { kind: 'move' }>,
): Promise<boolean> {
  if (action.status === from) return false;
  assertTransition(from, action.status);
  const patch: Record<string, unknown> = {
    status: action.status,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (action.captureId) patch.paypalCaptureId = action.captureId;
  if (action.status === 'paid') patch.paidAt = FieldValue.serverTimestamp();
  await ref.update(patch);
  await ref.collection('paymentEvents').doc(`reconcile-${orderId}`).set({
    id: `reconcile-${orderId}`,
    eventType: 'reconcile',
    paypalResourceId: action.captureId,
    amountMinor: null,
    raw: { source: 'reconcile', status: action.status },
    signatureVerified: false,
    receivedAt: FieldValue.serverTimestamp(),
    processedAt: FieldValue.serverTimestamp(),
    processingError: null,
  });
  return true;
}

/**
 * Reads one order's state from PayPal, captures it if the buyer approved, and
 * moves the order to match. This is how paid status lands when no webhook
 * does: a seller-payee order may not notify Sorted's app. Throws on PayPal
 * errors other than already-captured and declined.
 */
export async function reconcileOrder(
  paypal: PayPalFetch,
  ref: DocumentReference,
  orderId: string,
  status: OrderStatus,
  paypalOrderId: string,
): Promise<boolean> {
  let body = await getPayPalOrder(paypal, paypalOrderId);
  let action = reconcileAction(body);
  if (action.kind === 'capture') {
    try {
      body = await capturePayPalOrder(paypal, paypalOrderId, orderId);
    } catch (err) {
      const issue = paypalIssue(err);
      if (issue === 'ORDER_ALREADY_CAPTURED') {
        body = await getPayPalOrder(paypal, paypalOrderId);
      } else if (issue === 'INSTRUMENT_DECLINED') {
        action = { kind: 'move', status: 'declined', captureId: null };
      } else {
        throw err;
      }
    }
    if (action.kind === 'capture') action = reconcileAction(body);
    if (action.kind === 'capture') action = { kind: 'leave' };
  }
  if (action.kind !== 'move') return false;
  return applyMove(ref, orderId, status, action);
}
