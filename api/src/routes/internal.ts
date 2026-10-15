import { timingSafeEqual } from 'node:crypto';
import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import { ApiError } from '../lib/errors.js';
import type { Env } from '../env.js';
import type { PayPalFetch } from '../paypal/client.js';
import { paypalIssue } from '../paypal/events.js';
import { OPEN_STATUSES as OPEN, reconcileOrder } from '../paypal/reconcile.js';
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
              if (await reconcileOrder(deps.paypal, doc.ref, doc.id, status, paypalOrderId)) promoted += 1;
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
