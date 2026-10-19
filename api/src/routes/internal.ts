import { timingSafeEqual } from 'node:crypto';
import { Router, type RequestHandler } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import { ApiError } from '../lib/errors.js';
import type { Env } from '../env.js';
import type { PayPalFetch } from '../paypal/client.js';
import { paypalIssue } from '../paypal/events.js';
import { OPEN_STATUSES as OPEN, reconcileOrder } from '../paypal/reconcile.js';
import { EXPIRABLE_STATUSES, closeOrder, expiryDueMs } from '../domain/closing.js';
import { DEFAULT_ORDER_EXPIRY_HOURS } from '../env.js';
import type { OrderStatus } from '../domain/orders.js';
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

  const internalOnly: RequestHandler = (req, _res, next) => {
    const provided = req.get('x-internal-token') ?? '';
    if (!authorised(provided, deps.env.INTERNAL_TOKEN)) {
      next(new ApiError(401, 'UNAUTHENTICATED', 'That internal call was not authorised.'));
      return;
    }
    next();
  };

  router.post('/internal/workflows/reconcile', internalOnly, async (_req, res, next) => {

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

  // Closes unpaid links that have been out longer than ORDER_EXPIRY_HOURS.
  // Meant to run hourly beside the nudge sweep (see render.yaml). Each order
  // is checked with PayPal first, so a payment whose webhook never landed is
  // marked paid instead of expired; if PayPal cannot be asked, the order is
  // left for the next run rather than expired on a guess.
  router.post('/internal/workflows/expire-sweep', internalOnly, async (_req, res, next) => {
    const now = (deps.now ?? Date.now)();
    const ttlHours = deps.env.ORDER_EXPIRY_HOURS ?? DEFAULT_ORDER_EXPIRY_HOURS;
    let scanned = 0;
    let expired = 0;
    let kept = 0;
    let failed = 0;

    try {
      const sellers = await deps.db.collection('sellers').get();
      for (const seller of sellers.docs) {
        for (const status of EXPIRABLE_STATUSES) {
          const orders = await seller.ref.collection('orders').where('status', '==', status).get();
          for (const doc of orders.docs) {
            const due = expiryDueMs(doc.get('linkSentAt'), ttlHours);
            if (due === null || now < due) continue;
            scanned += 1;

            const paypalOrderId = doc.get('paypalOrderId');
            if (typeof paypalOrderId === 'string' && paypalOrderId) {
              try {
                if (await reconcileOrder(deps.paypal, doc.ref, doc.id, status, paypalOrderId)) {
                  const after = (await doc.ref.get()).get('status') as OrderStatus;
                  if (!EXPIRABLE_STATUSES.includes(after)) { kept += 1; continue; }
                }
              } catch (err) {
                failed += 1;
                console.error(JSON.stringify({
                  source: 'order_expiry',
                  orderId: doc.id,
                  issue: paypalIssue(err) ?? 'unknown',
                }));
                continue;
              }
            }

            try {
              const { closed } = await closeOrder(doc.ref, 'expired', EXPIRABLE_STATUSES);
              if (closed) expired += 1;
            } catch (err) {
              if (err instanceof ApiError && err.code === 'ORDER_STATE_INVALID') {
                // Moved under us, most likely to paid. Paid wins.
                kept += 1;
              } else {
                throw err;
              }
            }
          }
        }
      }
      res.json({ scanned, expired, kept, failed });
    } catch (err) {
      next(err);
    }
  });

  return router;
}
