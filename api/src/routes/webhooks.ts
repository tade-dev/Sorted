import { Router, type Request } from 'express';
import express from 'express';
import { FieldValue, type DocumentReference, type Firestore } from 'firebase-admin/firestore';
import { ApiError } from '../lib/errors.js';
import { recordWebhookFailure } from './health.js';
import type { Env } from '../env.js';
import type { PayPalFetch } from '../paypal/client.js';
import {
  HANDLED_EVENTS,
  capturePayPalOrder,
  getPayPalOrder,
  interimFromPayPalOrder,
  parseCustomId,
  parsePayPalEvent,
  paypalIssue,
  statusForEvent,
  verifyWebhookBody,
  type PayPalEvent,
} from '../paypal/events.js';
import { assertTransition, type OrderDoc, type OrderStatus } from '../domain/orders.js';
import { isClosed } from '../domain/closing.js';

export type WebhookDeps = {
  env: Env;
  db: Firestore;
  paypal: PayPalFetch;
};

const STATUSES = new Set<OrderStatus>([
  'draft', 'link_sent', 'processing', 'pending', 'declined', 'paid', 'cancelled', 'expired',
]);

const SIGNATURE_HEADERS = [
  ['paypal-transmission-id', 'transmissionId'],
  ['paypal-transmission-time', 'transmissionTime'],
  ['paypal-cert-url', 'certUrl'],
  ['paypal-auth-algo', 'authAlgo'],
  ['paypal-transmission-sig', 'transmissionSig'],
] as const;

function signatureHeaders(req: Request): {
  headers: {
    transmissionId: string;
    transmissionTime: string;
    certUrl: string;
    authAlgo: string;
    transmissionSig: string;
  } | null;
  missing: string[];
} {
  const missing: string[] = [];
  const values: Record<string, string> = {};
  for (const [header, key] of SIGNATURE_HEADERS) {
    const value = req.get(header);
    if (!value) missing.push(header);
    else values[key] = value;
  }
  if (missing.length > 0) return { headers: null, missing };
  return {
    headers: {
      transmissionId: values.transmissionId!,
      transmissionTime: values.transmissionTime!,
      certUrl: values.certUrl!,
      authAlgo: values.authAlgo!,
      transmissionSig: values.transmissionSig!,
    },
    missing,
  };
}

function logVerifyFailure(fields: Record<string, string | number | null>): void {
  console.error(JSON.stringify({ source: 'paypal_webhook_verify', ...fields }));
}

function safeIssue(value: string | undefined): string | null {
  if (!value) return null;
  const oneLine = value.replace(/\s+/g, ' ').slice(0, 80);
  if (/bearer|secret|token/i.test(oneLine)) return 'redacted';
  return oneLine;
}

async function locateOrder(db: Firestore, event: PayPalEvent) {
  const custom = parseCustomId(event.customId);
  if (custom) {
    const ref = db.doc(`sellers/${custom.sellerId}/orders/${custom.orderId}`);
    const snap = await ref.get();
    if (snap.exists) {
      return { ref, order: snap.data() as OrderDoc, sellerId: custom.sellerId, orderId: custom.orderId };
    }
  }
  if (!event.paypalOrderId) return null;
  const found = await db
    .collectionGroup('orders')
    .where('paypalOrderId', '==', event.paypalOrderId)
    .limit(1)
    .get();
  const doc = found.docs[0];
  if (!doc) return null;
  const sellerId = doc.ref.parent.parent?.id;
  if (!sellerId) return null;
  return { ref: doc.ref, order: doc.data() as OrderDoc, sellerId, orderId: doc.id };
}

async function recordPayment(
  ref: DocumentReference,
  event: PayPalEvent,
  processingError: string | null,
  refundDue = false,
) {
  await ref.collection('paymentEvents').doc(event.id).set({
    id: event.id,
    eventType: event.eventType,
    paypalResourceId: event.resourceId,
    amountMinor: event.amountMinor,
    raw: { id: event.id, event_type: event.eventType, resourceId: event.resourceId },
    signatureVerified: true,
    receivedAt: FieldValue.serverTimestamp(),
    processedAt: FieldValue.serverTimestamp(),
    processingError,
    // Money landed on a link Sorted had already closed. The app shows it so
    // the seller refunds it; the order itself does not move.
    ...(refundDue ? { refundDue: true } : {}),
  });
}

export function webhooksRouter(deps: WebhookDeps): Router {
  const router = Router();

  router.post(
    '/webhooks/paypal',
    express.raw({ type: 'application/json', limit: '1mb' }),
    async (req, res, next) => {
      const raw = Buffer.isBuffer(req.body) ? req.body.toString('utf8') : '';
      const { headers, missing } = signatureHeaders(req);
      if (!raw || !headers) {
        recordWebhookFailure();
        logVerifyFailure({
          reason: !raw ? 'missing_body' : 'missing_headers',
          missingHeaders: missing.join(','),
          contentType: (req.get('content-type') ?? '').slice(0, 120),
          bodyBytes: Buffer.isBuffer(req.body) ? req.body.length : 0,
        });
        next(new ApiError(401, 'UNAUTHENTICATED', 'PayPal could not verify that event.'));
        return;
      }

      let verified: { verification_status?: string };
      try {
        verified = (await deps.paypal('/v1/notifications/verify-webhook-signature', {
          method: 'POST',
          rawBody: verifyWebhookBody(raw, headers, deps.env.PAYPAL_WEBHOOK_ID),
        })) as { verification_status?: string };
      } catch (err) {
        recordWebhookFailure();
        const paypalStatus = err instanceof ApiError && err.details && typeof err.details === 'object'
          ? (err.details as { status?: unknown }).status
          : undefined;
        logVerifyFailure({
          reason: 'paypal_http',
          httpStatus: typeof paypalStatus === 'number' ? paypalStatus : null,
          issue: safeIssue(paypalIssue(err)),
          bodyBytes: Buffer.byteLength(raw),
        });
        next(new ApiError(502, 'PAYPAL_UNAVAILABLE', 'PayPal could not verify that event.'));
        return;
      }

      if (verified.verification_status !== 'SUCCESS') {
        recordWebhookFailure();
        logVerifyFailure({
          reason: 'verification_status',
          verificationStatus: verified.verification_status ?? 'missing',
          bodyBytes: Buffer.byteLength(raw),
        });
        next(new ApiError(401, 'UNAUTHENTICATED', 'PayPal could not verify that event.'));
        return;
      }

      let parsedJson: unknown;
      try {
        parsedJson = JSON.parse(raw);
      } catch {
        next(new ApiError(400, 'VALIDATION_FAILED', 'That webhook body is not JSON.'));
        return;
      }
      const event = parsePayPalEvent(parsedJson);
      if (!event) {
        next(new ApiError(400, 'VALIDATION_FAILED', 'That webhook is missing an id.'));
        return;
      }

      const ledger = deps.db.doc(`webhookEvents/${event.id}`);
      try {
        const gate = await deps.db.runTransaction(async (tx) => {
          const snap = await tx.get(ledger);
          if (snap.exists && snap.get('handled') === true) return 'duplicate' as const;
          tx.set(
            ledger,
            {
              id: event.id,
              eventType: event.eventType,
              receivedAt: snap.exists ? snap.get('receivedAt') : FieldValue.serverTimestamp(),
              handled: false,
              sellerId: null,
              orderId: null,
            },
            { merge: true },
          );
          return 'process' as const;
        });
        if (gate === 'duplicate') {
          res.json({ received: true });
          return;
        }

        if (!HANDLED_EVENTS.has(event.eventType)) {
          await ledger.set({ handled: true }, { merge: true });
          res.json({ received: true });
          return;
        }

        const located = await locateOrder(deps.db, event);
        if (!located) {
          await ledger.set(
            { handled: true, processingError: 'No matching order.' },
            { merge: true },
          );
          res.json({ received: true });
          return;
        }

        const { ref, order, sellerId, orderId } = located;
        // A link replaced by an edit charges the old items, and a cancelled
        // or expired order is closed, so nothing these do may move the order.
        // Cancel and expiry put the order's own PayPal id on the superseded
        // list too; the status check also covers orders closed before that.
        // A capture here is real money and is flagged for refund.
        const superseded = Boolean(
          event.paypalOrderId && order.supersededPaypalOrderIds?.includes(event.paypalOrderId),
        );
        const closed = isClosed(order.status);
        if (superseded || closed) {
          const captured = event.eventType === 'PAYMENT.CAPTURE.COMPLETED';
          const reason = closed
            ? captured
              ? `Captured after the order was ${order.status}. Refund it in PayPal.`
              : `The order was ${order.status}. Ignored.`
            : captured
              ? 'Captured on a superseded PayPal order. Refund it in PayPal.'
              : 'PayPal order was superseded by an edit. Ignored.';
          console.warn(JSON.stringify({
            source: closed ? 'paypal_closed' : 'paypal_superseded',
            orderId, paypalOrderId: event.paypalOrderId, eventType: event.eventType,
          }));
          await recordPayment(ref, event, reason, captured);
          await ledger.set({ handled: true, sellerId, orderId, processingError: reason }, { merge: true });
          res.json({ received: true });
          return;
        }
        const status = STATUSES.has(order.status) ? order.status : null;
        let processingError: string | null = null;
        const patch: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };

        if (event.eventType === 'CHECKOUT.ORDER.APPROVED') {
          if (status && status !== 'paid' && status !== 'cancelled' && status !== 'expired') {
            const outcome = await captureOrReconcile(deps.paypal, event.paypalOrderId ?? order.paypalOrderId, orderId);
            if (outcome.captureId) patch.paypalCaptureId = outcome.captureId;
            if (status !== outcome.interim) {
              assertTransition(status, outcome.interim);
              patch.status = outcome.interim;
            }
          }
        } else if (status) {
          const target = statusForEvent(event.eventType);
          if (event.captureId) patch.paypalCaptureId = event.captureId;
          if (target && target !== status) {
            try {
              assertTransition(status, target);
              patch.status = target;
              if (target === 'paid') patch.paidAt = FieldValue.serverTimestamp();
            } catch (err) {
              if (err instanceof ApiError && err.code === 'ORDER_STATE_INVALID') {
                processingError = err.message;
              } else {
                throw err;
              }
            }
          }
        }

        await ref.update(patch);
        await recordPayment(ref, event, processingError);
        await ledger.set({ handled: true, sellerId, orderId }, { merge: true });
        res.json({ received: true });
      } catch (err) {
        next(err);
      }
    },
  );

  return router;
}

async function captureOrReconcile(
  paypal: PayPalFetch,
  paypalOrderId: string | null,
  orderId: string,
): Promise<{ interim: 'link_sent' | 'processing' | 'pending' | 'declined'; captureId: string | null }> {
  if (!paypalOrderId) return { interim: 'link_sent', captureId: null };
  try {
    const captured = await capturePayPalOrder(paypal, paypalOrderId, orderId);
    return interimFromPayPalOrder(captured);
  } catch (err) {
    const issue = paypalIssue(err);
    if (issue === 'ORDER_ALREADY_CAPTURED') {
      return interimFromPayPalOrder(await getPayPalOrder(paypal, paypalOrderId));
    }
    if (issue === 'INSTRUMENT_DECLINED') return { interim: 'declined', captureId: null };
    throw err;
  }
}
