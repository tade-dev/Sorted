import { timingSafeEqual } from 'node:crypto';
import { Router } from 'express';
import { FieldValue, type DocumentReference, type Firestore } from 'firebase-admin/firestore';
import { ApiError } from '../lib/errors.js';
import type { Env } from '../env.js';
import type { PayPalFetch } from '../paypal/client.js';
import {
  capturePayPalOrder,
  getPayPalOrder,
  paypalIssue,
  reconcileAction,
  type ReconcileAction,
} from '../paypal/events.js';
import { assertTransition, type OrderStatus } from '../domain/orders.js';

const OPEN: OrderStatus[] = ['link_sent', 'processing', 'pending'];
const TWO_MINUTES_MS = 2 * 60 * 1000;

function authorised(provided: string, expected: string): boolean {
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

function tooRecent(linkSentAt: unknown, now: number): boolean {
  if (!linkSentAt || typeof linkSentAt !== 'object' || !('toMillis' in linkSentAt)) return false;
  const ms = (linkSentAt as { toMillis: () => number }).toMillis();
  return typeof ms === 'number' && !Number.isNaN(ms) && now - ms < TWO_MINUTES_MS;
}

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

export function internalRouter(deps: {
  env: Env;
  db: Firestore;
  paypal: PayPalFetch;
  now?: () => number;
}): Router {
  const router = Router();

  router.post('/internal/workflows/reconcile', async (req, res, next) => {
    const provided = req.get('x-internal-token') ?? '';
    if (!authorised(provided, deps.env.INTERNAL_TOKEN)) {
      next(new ApiError(401, 'UNAUTHENTICATED', 'That internal call was not authorised.'));
      return;
    }

    const now = (deps.now ?? Date.now)();
    let checked = 0;
    let promoted = 0;
    let failed = 0;

    try {
      const sellers = await deps.db.collection('sellers').get();
      for (const seller of sellers.docs) {
        for (const status of OPEN) {
          const orders = await seller.ref.collection('orders').where('status', '==', status).get();
          for (const doc of orders.docs) {
            const paypalOrderId = doc.get('paypalOrderId');
            if (typeof paypalOrderId !== 'string' || !paypalOrderId) continue;
            if (tooRecent(doc.get('linkSentAt'), now)) continue;
            checked += 1;
            try {
              let body = await getPayPalOrder(deps.paypal, paypalOrderId);
              let action = reconcileAction(body);
              if (action.kind === 'capture') {
                try {
                  body = await capturePayPalOrder(deps.paypal, paypalOrderId, doc.id);
                } catch (err) {
                  const issue = paypalIssue(err);
                  if (issue === 'ORDER_ALREADY_CAPTURED') {
                    body = await getPayPalOrder(deps.paypal, paypalOrderId);
                  } else if (issue === 'INSTRUMENT_DECLINED') {
                    action = { kind: 'move', status: 'declined', captureId: null };
                  } else {
                    throw err;
                  }
                }
                if (action.kind === 'capture') action = reconcileAction(body);
                if (action.kind === 'capture') action = { kind: 'leave' };
              }
              if (action.kind === 'move') {
                const moved = await applyMove(doc.ref, doc.id, status, action);
                if (moved) promoted += 1;
              }
            } catch (err) {
              failed += 1;
              const issue = paypalIssue(err);
              console.error(JSON.stringify({
                source: 'paypal_reconcile',
                orderId: doc.id,
                issue: issue ?? 'unknown',
              }));
            }
          }
        }
      }
      res.json({ checked, promoted, failed });
    } catch (err) {
      next(err);
    }
  });

  return router;
}
