import { Router } from 'express';
import multer, { MulterError } from 'multer';
import { z } from 'zod';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
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
import { draftReply, type ReplyTone } from '../ai/draft_reply.js';
import { assertTransition, blockingAmbiguities } from '../domain/orders.js';

const MAX_BYTES = 8 * 1024 * 1024;
const ALLOWED = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/heic']);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_BYTES, files: 1 },
  fileFilter: (_req, file, cb) => {
    if (!ALLOWED.has(file.mimetype)) {
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

/** An ambiguity is answered once the field it points at has a value. */
function stillOpen(
  ambiguity: OrderDoc['ambiguities'][number],
  lines: OrderDoc['lineItems'],
): boolean {
  const match = /^lineItems\[(\d+)\]\.(\w+)$/.exec(ambiguity.field);
  if (!match) return true;
  const line = lines[Number(match[1])];
  if (!line) return true;
  if (match[2] === 'variantIds') return line.variantIds.length === 0;
  if (match[2] === 'productId') return line.productId === null;
  return true;
}

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
};

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
            ...(file ? { image: { buffer: file.buffer, mime: file.mimetype } } : {}),
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
          ambiguities: [...parsed.ambiguities, ...matched.ambiguities],
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

      const ambiguities = order.ambiguities.filter((a) => stillOpen(a, lines));

      const updated = {
        ...order,
        lineItems: lines,
        ...amounts,
        ambiguities,
        ...(patch.buyerName !== undefined ? { buyerName: patch.buyerName } : {}),
        ...(patch.buyerHandle !== undefined ? { buyerHandle: patch.buyerHandle } : {}),
        ...(patch.buyerEmail !== undefined ? { buyerEmail: patch.buyerEmail } : {}),
        ...(patch.fulfilment ? { fulfilment: { ...order.fulfilment, ...patch.fulfilment } } : {}),
      };

      await ref.update({ ...updated, updatedAt: FieldValue.serverTimestamp() });
      res.json({ order: updated });
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
      const { paypalOrderId, approvalUrl } = await createPayPalOrder(
        priced,
        sellerId,
        deps.paypal,
      );

      const sellerSnap = await deps.db.doc(`sellers/${sellerId}`).get();
      const personaTone = (sellerSnap.data()?.personaTone as string | undefined) ?? '';

      let draftedReply: string | null = null;
      try {
        draftedReply = await draftReply(
          { order: priced, personaTone, approvalUrl, tone: 'friendly' },
          deps.transport,
          deps.model,
        );
      } catch {
        // The link is the thing that matters. A failed draft must not lose it.
        draftedReply = null;
      }

      const updated: OrderDoc = {
        ...priced,
        status: 'link_sent',
        paypalOrderId,
        approvalUrl,
        draftedReply,
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
