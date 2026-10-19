import { Router } from 'express';
import multer, { MulterError } from 'multer';
import { z } from 'zod';
import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { looksLikeUpload, visionMime } from '../lib/image_type.js';
import { ApiError } from '../lib/errors.js';
import { requireSeller, type TokenVerifier } from '../lib/auth.js';
import type { ChatTransport } from '../ai/client.js';
import { parseDm, type CatalogueBrief } from '../ai/parse_dm.js';
import { matchLineItems, type StoredProduct } from '../domain/match_catalogue.js';
import {
  computeAmounts,
  createDraftOrder,
  loadProducts,
  type OrderDoc,
} from '../domain/orders.js';
import { sumMinor, multiplyMinor, applyDelta } from '../domain/money.js';
import { createPayPalOrder } from '../paypal/orders.js';
import type { PayPalFetch } from '../paypal/client.js';
import { OPEN_STATUSES, reconcileOrder } from '../paypal/reconcile.js';
import { getPayPalOrder, reconcileAction } from '../paypal/events.js';
import { draftReply, fallbackReply, fallbackThankYou, type ReplyTone } from '../ai/draft_reply.js';
import { assertTransition, blockingAmbiguities } from '../domain/orders.js';
import { invoiceNumber, invoiceUrl } from '../domain/invoice.js';
import {
  CANCELLABLE_STATUSES,
  closeOrder,
  expiryFromNow,
  isClosed,
} from '../domain/closing.js';
import { DEFAULT_ORDER_EXPIRY_HOURS } from '../env.js';
import {
  applyBlockingPolicy,
  stillOpen,
  withoutSettledVariantQuestions,
  type AmbiguityPatch,
} from '../domain/ambiguities.js';

const MAX_BYTES = 8 * 1024 * 1024;

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_BYTES, files: 1 },
  fileFilter: (_req, file, cb) => {
    if (!looksLikeUpload(file.mimetype)) {
      cb(new ApiError(400, 'VALIDATION_FAILED', `${file.mimetype} is not an image Sorted can read.`));
      return;
    }
    cb(null, true);
  },
}).single('image');

const resolveBodySchema = z.object({
  buyerName: z.string().max(80).nullable().optional(),
  buyerHandle: z.string().max(80).nullable().optional(),
  buyerEmail: z.string().email().nullable().optional(),
  depositMinor: z.number().int().nonnegative().nullable().optional(),
  fulfilment: z
    .object({
      mode: z.enum(['collection', 'delivery', 'unknown']).optional(),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
      notes: z.string().max(300).nullable().optional(),
    })
    .optional(),
  lineItems: z
    .array(
      z.object({
        id: z.string().min(1),
        variantIds: z.array(z.string()).optional(),
        qty: z.number().int().min(1).max(999).optional(),
        productId: z.string().nullable().optional(),
      }),
    )
    .optional(),
  // Spec field: the seller has answered these, including "no deposit" and
  // free-text questions that are not a line, a name, or a date.
  resolvedAmbiguities: z.array(z.string().min(1)).optional(),
});

function toBrief(products: StoredProduct[]): CatalogueBrief {
  return products.map((p) => ({
    id: p.id,
    name: p.name,
    basePriceMinor: p.basePriceMinor,
    variantLabels: p.variants.filter((v) => v.active).map((v) => v.label),
  }));
}

/** Recomputes a line's price from the catalogue after the seller edits it. */
function repriceLine(
  line: OrderDoc['lineItems'][number],
  products: StoredProduct[],
): OrderDoc['lineItems'][number] {
  const product = products.find((p) => p.id === line.productId);
  if (!product) return { ...line, unitPriceMinor: 0, lineTotalMinor: 0 };

  const chosen = product.variants.filter(
    (v) => v.active && line.variantIds.includes(v.id),
  );
  const unitPriceMinor = chosen.reduce(
    (price, v) => applyDelta(price, v.priceDeltaMinor),
    product.basePriceMinor,
  );
  return {
    ...line,
    nameResolved: product.name,
    unitPriceMinor,
    lineTotalMinor: multiplyMinor(unitPriceMinor, line.qty),
  };
}

/**
 * Best effort: looks up a PayPal order the seller just replaced and logs its
 * state. A COMPLETED one means the buyer already paid on the old link and the
 * seller needs to refund it. Never throws, so PayPal cannot block an edit.
 */
export async function checkSupersededPayPalOrder(
  paypal: PayPalFetch,
  paypalOrderId: string,
  orderId: string,
): Promise<string | null> {
  try {
    const body = (await paypal(`/v2/checkout/orders/${encodeURIComponent(paypalOrderId)}`, { method: 'GET' })) as {
      status?: string;
    };
    const status = typeof body?.status === 'string' ? body.status : null;
    console.info(JSON.stringify({ source: 'paypal_superseded', orderId, paypalOrderId, status }));
    return status;
  } catch (err) {
    console.error(JSON.stringify({
      source: 'paypal_superseded',
      orderId,
      paypalOrderId,
      error: err instanceof Error ? err.message.slice(0, 160) : 'error',
    }));
    return null;
  }
}

const editBodySchema = z
  .object({
    /** The full new list of lines. Lines with an id keep it; new ones get one. */
    lineItems: z
      .array(
        z.object({
          id: z.string().min(1).optional(),
          productId: z.string().min(1),
          variantIds: z.array(z.string()).max(12).default([]),
          qty: z.number().int().min(1).max(999),
        }),
      )
      .min(1)
      .max(30)
      .optional(),
    note: z.string().trim().max(300).nullable().optional(),
  })
  .strict();

/**
 * Statuses an order can still be edited in. Paid, cancelled and expired are
 * final; processing and pending mean the buyer is mid-payment on the old
 * amount, so changing it under them is refused too.
 */
export const EDITABLE_STATUSES: ReadonlyArray<OrderDoc['status']> = ['draft', 'link_sent', 'declined'];

const confirmBodySchema = z.object({
  depositMinor: z.number().int().nonnegative().nullable().optional(),
});
const regenerateBodySchema = z.object({
  tone: z.enum(['friendly', 'short', 'formal']).default('friendly'),
});

export type OrdersDeps = {
  db: Firestore;
  paypal: PayPalFetch;
  verify: TokenVerifier;
  transport: ChatTransport;
  model: string;
  publicBaseUrl: string;
  /** Signs buyer invoice links. Optional so older callers keep working. */
  invoiceSecret?: string;
  /** Hours an unpaid link stays open. Defaults to the env default. */
  orderExpiryHours?: number;
  now?: () => number;
};

/** Why an order the seller asked to cancel cannot be, in their words. */
function cannotCancel(status: OrderDoc['status']): ApiError {
  switch (status) {
    case 'paid':
      return new ApiError(
        409,
        'ORDER_STATE_INVALID',
        'That order is already paid, so Sorted cannot cancel it. Refund it in PayPal instead.',
      );
    case 'processing':
    case 'pending':
      return new ApiError(
        409,
        'ORDER_STATE_INVALID',
        'The buyer is paying for this right now. Wait for PayPal to finish, then try again.',
      );
    case 'expired':
      return new ApiError(409, 'ORDER_STATE_INVALID', 'That order has already expired.');
    default:
      return new ApiError(409, 'ORDER_STATE_INVALID', `An order that is ${status} cannot be cancelled.`);
  }
}

export function ordersRouter(deps: OrdersDeps): Router {
  const router = Router();

  router.post(
    '/orders/draft',
    requireSeller(deps.verify),
    (req, res, next) => {
      upload(req, res, (err: unknown) => {
        if (err instanceof MulterError) {
          next(
            new ApiError(
              400,
              'VALIDATION_FAILED',
              err.code === 'LIMIT_FILE_SIZE'
                ? 'That screenshot must be 8MB or smaller.'
                : 'That upload could not be read.',
            ),
          );
          return;
        }
        if (err) { next(err); return; }
        next();
      });
    },
    async (req, res, next) => {
      const sellerId = req.sellerId!;
      const file = req.file;
      const text = typeof req.body?.text === 'string' ? req.body.text : undefined;

      try {
        const products = await loadProducts(deps.db, sellerId);
        const today = new Date().toISOString().slice(0, 10);

        const parsed = await parseDm(
          {
            ...(file ? { image: { buffer: file.buffer, mime: visionMime(file.buffer) } } : {}),
            ...(text ? { text } : {}),
          },
          toBrief(products),
          today,
          deps.transport,
          deps.model,
        );

        if (parsed.lineItems.length === 0) {
          // Writing an order here would put a wrong checkout link one tap away.
          res.json({
            order: null,
            reason:
              'Sorted could not find an order in that. Try a screenshot of the conversation where the buyer says what they want.',
          });
          return;
        }

        const matched = matchLineItems(parsed.lineItems, products);

        const order = await createDraftOrder(deps.db, sellerId, {
          buyerName: parsed.buyerName,
          buyerHandle: parsed.buyerHandle,
          buyerEmail: parsed.buyerEmail,
          channel: parsed.channel,
          lines: matched.lines,
          ambiguities: withoutSettledVariantQuestions(
            [...parsed.ambiguities, ...matched.ambiguities],
            matched.lines,
            products,
          ),
          fulfilment: parsed.fulfilment,
          depositMinor: parsed.depositRequestedMinor,
          sourceKind: file ? 'screenshot' : 'text',
          extractionModel: deps.model,
        });

        res.json({ order });
      } catch (err) {
        next(err);
      }
    },
  );

  router.post('/orders/:orderId/resolve', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = resolveBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'That change is not valid.', parsed.error.format()));
      return;
    }

    const ref = deps.db.doc(`sellers/${req.sellerId}/orders/${req.params.orderId}`);
    try {
      const snap = await ref.get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such order.')); return; }

      const order = snap.data() as OrderDoc;
      if (order.status !== 'draft') {
        next(new ApiError(409, 'ORDER_STATE_INVALID', 'That order has already been sent.'));
        return;
      }

      const products = await loadProducts(deps.db, req.sellerId!);
      const patch = parsed.data;

      let lines = order.lineItems;
      if (patch.lineItems) {
        lines = lines.map((line) => {
          const edit = patch.lineItems!.find((e) => e.id === line.id);
          if (!edit) return line;
          return repriceLine(
            {
              ...line,
              ...(edit.variantIds ? { variantIds: edit.variantIds } : {}),
              ...(edit.qty ? { qty: edit.qty } : {}),
              ...(edit.productId !== undefined ? { productId: edit.productId } : {}),
            },
            products,
          );
        });
      }

      const subtotal = sumMinor(lines.map((l) => l.lineTotalMinor));
      const amounts = computeAmounts(
        subtotal,
        patch.depositMinor === undefined ? order.depositMinor : patch.depositMinor,
      );
      const fulfilment = patch.fulfilment
        ? {
            mode: patch.fulfilment.mode ?? order.fulfilment.mode,
            date:
              patch.fulfilment.date !== undefined
                ? patch.fulfilment.date
                : order.fulfilment.date,
            notes:
              patch.fulfilment.notes !== undefined
                ? patch.fulfilment.notes
                : order.fulfilment.notes,
          }
        : order.fulfilment;
      const buyerName = patch.buyerName !== undefined ? patch.buyerName : order.buyerName;
      const buyerHandle = patch.buyerHandle !== undefined ? patch.buyerHandle : order.buyerHandle;
      const buyerEmail = patch.buyerEmail !== undefined ? patch.buyerEmail : order.buyerEmail;

      const ambiguityPatch: AmbiguityPatch = {};
      if (patch.lineItems) {
        ambiguityPatch.lineItems = patch.lineItems.map((edit) => {
          const item: { id: string; qty?: number } = { id: edit.id };
          if (edit.qty !== undefined) item.qty = edit.qty;
          return item;
        });
      }
      if (patch.depositMinor !== undefined) ambiguityPatch.depositMinor = patch.depositMinor;
      if (patch.resolvedAmbiguities) {
        ambiguityPatch.resolvedAmbiguities = patch.resolvedAmbiguities;
      }

      const ambiguities = order.ambiguities
        .filter((a) =>
          stillOpen(
            a,
            {
              lineItems: lines,
              buyerName,
              buyerHandle,
              buyerEmail,
              fulfilment,
              depositMinor: amounts.depositMinor,
            },
            ambiguityPatch,
          ),
        )
        .map(applyBlockingPolicy);

      const updated = {
        ...order,
        lineItems: lines,
        ...amounts,
        ambiguities,
        buyerName,
        buyerHandle,
        buyerEmail,
        fulfilment,
      };

      await ref.update({ ...updated, updatedAt: FieldValue.serverTimestamp() });
      res.json({ order: updated });
    } catch (err) {
      next(err);
    }
  });

  router.post('/orders/:orderId/edit', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = editBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'That change is not valid.', parsed.error.format()));
      return;
    }
    const ref = deps.db.doc(`sellers/${req.sellerId}/orders/${req.params.orderId}`);
    try {
      const products = await loadProducts(deps.db, req.sellerId!);
      // A transaction so a capture webhook landing mid-edit cannot be
      // overwritten: if the order turns paid, the retry sees it and refuses.
      const updated = await deps.db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) throw new ApiError(404, 'NOT_FOUND', 'No such order.');
        const order = snap.data() as OrderDoc;
        if (order.status === 'paid') {
          throw new ApiError(409, 'ORDER_STATE_INVALID', 'This order is paid, so it can no longer be edited.');
        }
        if (!EDITABLE_STATUSES.includes(order.status)) {
          throw new ApiError(409, 'ORDER_STATE_INVALID', `An order that is ${order.status} cannot be edited.`);
        }

        const patch = parsed.data;
        let lines = order.lineItems;
        let ambiguities = order.ambiguities;
        if (patch.lineItems) {
          lines = patch.lineItems.map((edit, i) => {
            const product = products.find((p) => p.id === edit.productId);
            if (!product) {
              throw new ApiError(400, 'VALIDATION_FAILED', 'One of those products is no longer in your catalogue.');
            }
            const live = new Set(product.variants.filter((v) => v.active).map((v) => v.id));
            if (edit.variantIds.some((id) => !live.has(id))) {
              throw new ApiError(400, 'VALIDATION_FAILED', `That option is not available for ${product.name}.`);
            }
            const existing = edit.id ? order.lineItems.find((l) => l.id === edit.id) : undefined;
            return repriceLine(
              {
                id: existing?.id ?? `line-${Date.now().toString(36)}-${i}`,
                productId: product.id,
                variantIds: edit.variantIds,
                nameRaw: existing?.nameRaw ?? product.name,
                nameResolved: product.name,
                qty: edit.qty,
                unitPriceMinor: 0,
                lineTotalMinor: 0,
                matchConfidence: 1,
                matchMethod: 'exact',
              },
              products,
            );
          });
          // Line questions are indexed by position, and the seller has just
          // chosen every line explicitly, so none of them still apply.
          ambiguities = ambiguities.filter((a) => !a.field.startsWith('lineItems'));
        }

        const subtotal = sumMinor(lines.map((l) => l.lineTotalMinor));
        // A deposit larger than the new total is dropped rather than refused:
        // the seller removed items, and charging more than the goods is wrong.
        const deposit =
          order.depositMinor !== null && order.depositMinor > subtotal ? null : order.depositMinor;
        const amounts = computeAmounts(subtotal, deposit);
        const fulfilment =
          patch.note !== undefined
            ? { ...order.fulfilment, notes: patch.note === '' ? null : patch.note }
            : order.fulfilment;

        const amountChanged =
          amounts.amountDueMinor !== order.amountDueMinor || patch.lineItems !== undefined;
        // A sent link charges the old amount, so a changed order goes back to
        // draft and the seller creates a fresh link. The old PayPal order is
        // no longer referenced, so a late approval on it is not captured.
        const reopen = order.status !== 'draft' && amountChanged;

        const edited: OrderDoc = {
          ...order,
          lineItems: lines,
          ...amounts,
          ambiguities,
          fulfilment,
          ...(reopen
            ? { status: 'draft' as const, paypalOrderId: null, approvalUrl: null, draftedReply: null }
            : {}),
        };
        // PayPal cannot cancel a CREATED or APPROVED checkout order, so the
        // old id is recorded as superseded and the webhook refuses it.
        const superseded = reopen && order.paypalOrderId ? order.paypalOrderId : null;
        tx.update(ref, {
          ...edited,
          ...(superseded
            ? { supersededPaypalOrderIds: FieldValue.arrayUnion(superseded) }
            : {}),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { edited, superseded };
      });
      if (updated.superseded) {
        await checkSupersededPayPalOrder(deps.paypal, updated.superseded, String(req.params.orderId));
      }
      res.json({ order: updated.edited });
    } catch (err) {
      next(err);
    }
  });

  router.post('/orders/:orderId/confirm', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = confirmBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'That request is not valid.', parsed.error.format()));
      return;
    }

    const sellerId = req.sellerId!;
    const ref = deps.db.doc(`sellers/${sellerId}/orders/${req.params.orderId}`);

    try {
      const snap = await ref.get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such order.')); return; }

      const order = snap.data() as OrderDoc;
      assertTransition(order.status, 'link_sent');

      const open = blockingAmbiguities(order.ambiguities);
      if (open.length > 0) {
        next(
          new ApiError(
            409,
            'ORDER_STATE_INVALID',
            open[0]!.question,
            { unresolved: open.map((a) => a.field) },
          ),
        );
        return;
      }

      const amounts = computeAmounts(
        order.subtotalMinor,
        parsed.data.depositMinor === undefined ? order.depositMinor : parsed.data.depositMinor,
      );
      const priced: OrderDoc = { ...order, ...amounts };

      // Nothing is written until PayPal has accepted the order, so a rejection
      // leaves the seller's draft exactly as it was to retry.
      const sellerSnap = await deps.db.doc(`sellers/${sellerId}`).get();
      const rawPayee = sellerSnap.data()?.paypalEmail;
      const payeeEmail = typeof rawPayee === 'string' && rawPayee.includes('@') ? rawPayee : null;

      const { paypalOrderId, approvalUrl } = await createPayPalOrder(
        priced,
        sellerId,
        deps.paypal,
        deps.publicBaseUrl,
        payeeEmail,
      );

      const personaTone = (sellerSnap.data()?.personaTone as string | undefined) ?? '';

      let draftedReply: string;
      try {
        draftedReply = await draftReply(
          { order: priced, personaTone, approvalUrl, tone: 'friendly' },
          deps.transport,
          deps.model,
        );
      } catch {
        // The link is the thing that matters. A failed draft must not lose it.
        draftedReply = fallbackReply(priced, approvalUrl);
      }

      const updated: OrderDoc = {
        ...priced,
        status: 'link_sent',
        paypalOrderId,
        approvalUrl,
        draftedReply,
        paypalPayee: payeeEmail ?? 'shared_sandbox',
        // The expiry sweep counts from linkSentAt; this is the same moment,
        // stored so the app and the Devpost write-up can show it.
        expiresAt: Timestamp.fromMillis(
          expiryFromNow(
            (deps.now ?? Date.now)(),
            deps.orderExpiryHours ?? DEFAULT_ORDER_EXPIRY_HOURS,
          ),
        ),
      };

      await ref.update({
        ...updated,
        linkSentAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      res.json({ order: updated });
    } catch (err) {
      next(err);
    }
  });

  router.post('/orders/:orderId/reply/regenerate', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = regenerateBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'That tone is not one Sorted knows.'));
      return;
    }

    const sellerId = req.sellerId!;
    const ref = deps.db.doc(`sellers/${sellerId}/orders/${req.params.orderId}`);

    try {
      const snap = await ref.get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such order.')); return; }

      const order = snap.data() as OrderDoc;
      if (isClosed(order.status)) {
        next(new ApiError(409, 'ORDER_STATE_INVALID', `That order is ${order.status}, so its link no longer takes payment.`));
        return;
      }
      if (!order.approvalUrl) {
        next(new ApiError(409, 'ORDER_STATE_INVALID', 'That order has no payment link yet.'));
        return;
      }

      const sellerSnap = await deps.db.doc(`sellers/${sellerId}`).get();
      const draftedReply = await draftReply(
        {
          order,
          personaTone: (sellerSnap.data()?.personaTone as string | undefined) ?? '',
          approvalUrl: order.approvalUrl,
          tone: parsed.data.tone as ReplyTone,
        },
        deps.transport,
        deps.model,
      );

      await ref.update({ draftedReply, updatedAt: FieldValue.serverTimestamp() });
      res.json({ draftedReply });
    } catch (err) {
      next(err);
    }
  });

  // Paid.dc.html "Copy thank-you message". Written fresh on each tap and not
  // stored: it is only ever copied, never shown.
  router.post('/orders/:orderId/thank-you', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = regenerateBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'That tone is not one Sorted knows.'));
      return;
    }
    const sellerId = req.sellerId!;
    try {
      const snap = await deps.db.doc(`sellers/${sellerId}/orders/${req.params.orderId}`).get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such order.')); return; }
      const order = snap.data() as OrderDoc;
      if (order.status !== 'paid') {
        next(new ApiError(409, 'ORDER_STATE_INVALID', 'That order has not been paid yet.'));
        return;
      }
      const sellerSnap = await deps.db.doc(`sellers/${sellerId}`).get();
      let message: string;
      try {
        message = await draftReply(
          {
            order,
            personaTone: (sellerSnap.data()?.personaTone as string | undefined) ?? '',
            approvalUrl: '',
            tone: parsed.data.tone as ReplyTone,
            mode: 'thank_you',
          },
          deps.transport,
          deps.model,
        );
      } catch {
        message = fallbackThankYou(order);
      }
      res.json({ message });
    } catch (err) {
      next(err);
    }
  });

  // The buyer-facing invoice link for a paid order, for the seller to share.
  router.get('/orders/:orderId/invoice', requireSeller(deps.verify), async (req, res, next) => {
    const orderId = String(req.params.orderId);
    try {
      if (!deps.invoiceSecret) {
        next(new ApiError(404, 'NOT_FOUND', 'Invoices are not set up on this server.'));
        return;
      }
      const snap = await deps.db.doc(`sellers/${req.sellerId}/orders/${orderId}`).get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such order.')); return; }
      if (snap.get('status') !== 'paid') {
        next(new ApiError(409, 'ORDER_STATE_INVALID', 'That order has not been paid yet.'));
        return;
      }
      res.json({
        url: invoiceUrl(deps.publicBaseUrl, deps.invoiceSecret, req.sellerId!, orderId),
        number: invoiceNumber(orderId),
      });
    } catch (err) {
      next(err);
    }
  });

  // The app calls this when the seller opens an open order. A payment to the
  // seller's own PayPal may never webhook Sorted, so this asks PayPal itself.
  router.post('/orders/:orderId/refresh', requireSeller(deps.verify), async (req, res, next) => {
    const orderId = String(req.params.orderId);
    const ref = deps.db.doc(`sellers/${req.sellerId}/orders/${orderId}`);
    try {
      const snap = await ref.get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such order.')); return; }
      const order = snap.data() as OrderDoc;
      let changed = false;
      if (OPEN_STATUSES.includes(order.status) && order.paypalOrderId) {
        changed = await reconcileOrder(deps.paypal, ref, orderId, order.status, order.paypalOrderId);
      }
      const status = changed ? ((await ref.get()).get('status') as string) : order.status;
      res.json({ status, changed });
    } catch (err) {
      next(err);
    }
  });

  // Seller cancels an unpaid order. Asking twice is fine: an order that is
  // already cancelled comes back as it is.
  router.post('/orders/:orderId/cancel', requireSeller(deps.verify), async (req, res, next) => {
    const orderId = String(req.params.orderId);
    const ref = deps.db.doc(`sellers/${req.sellerId}/orders/${orderId}`);
    try {
      const snap = await ref.get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such order.')); return; }
      const order = snap.data() as OrderDoc;
      if (order.status === 'cancelled') { res.json({ order }); return; }
      if (!CANCELLABLE_STATUSES.includes(order.status)) { next(cannotCancel(order.status)); return; }

      // A sent link may already be paid with no webhook yet. Ask PayPal first,
      // so a payment that landed is marked paid rather than cancelled over.
      // If PayPal cannot be asked, nothing is cancelled: guessing wrong here
      // closes an order the buyer has paid for. An approval that was never
      // captured is not money yet, so it does not block the cancel; the
      // superseded id means Sorted will not capture it afterwards either.
      if (order.status !== 'draft' && order.paypalOrderId) {
        let action: ReturnType<typeof reconcileAction>;
        try {
          action = reconcileAction(await getPayPalOrder(deps.paypal, order.paypalOrderId));
        } catch {
          next(new ApiError(
            502,
            'PAYPAL_UNAVAILABLE',
            'Sorted could not check this order with PayPal, so it was not cancelled. Try again in a moment.',
          ));
          return;
        }
        if (action.kind === 'move' && action.status !== 'declined') {
          try {
            await reconcileOrder(deps.paypal, ref, orderId, order.status, order.paypalOrderId);
          } catch {
            // The refusal below stands either way; the sweep will catch up.
          }
          next(cannotCancel(action.status));
          return;
        }
      }

      const { order: closed } = await closeOrder(ref, 'cancelled', CANCELLABLE_STATUSES);
      res.json({ order: closed });
    } catch (err) {
      next(err);
    }
  });

  router.get('/orders', requireSeller(deps.verify), async (req, res, next) => {
    try {
      const snap = await deps.db
        .collection(`sellers/${req.sellerId}/orders`)
        .orderBy('createdAt', 'desc')
        .limit(50)
        .get();
      res.json({ orders: snap.docs.map((d) => d.data()), nextCursor: null });
    } catch (err) {
      next(err);
    }
  });

  return router;
}
