import { Router } from 'express';
import { z } from 'zod';
import { FieldValue } from 'firebase-admin/firestore';
import multer, { MulterError } from 'multer';
import type { Firestore } from 'firebase-admin/firestore';
import { randomUUID } from 'node:crypto';
import { ApiError } from '../lib/errors.js';
import { requireSeller, type TokenVerifier } from '../lib/auth.js';
import type { ChatTransport } from '../ai/client.js';
import { extractCatalogue } from '../ai/extract_catalogue.js';
import {
  productInputSchema,
  saveProducts,
  variantInputSchema,
} from '../domain/products.js';
import { applyDelta } from '../domain/money.js';

const saveBodySchema = z.object({ products: z.array(productInputSchema).min(1).max(20) });
const patchBodySchema = z
  .object({
    name: z.string().min(1).max(60).optional(),
    description: z.string().max(240).optional(),
    basePriceMinor: z.number().int().nonnegative().optional(),
    depositMinor: z.number().int().nonnegative().nullable().optional(),
    variants: z.array(variantInputSchema).max(12).optional(),
  })
  .superRefine((patch, ctx) => {
    if (patch.basePriceMinor === undefined || patch.variants === undefined) return;
    for (const [i, variant] of patch.variants.entries()) {
      try {
        applyDelta(patch.basePriceMinor, variant.priceDeltaMinor);
      } catch {
        ctx.addIssue({
          code: 'custom',
          path: ['variants', i, 'priceDeltaMinor'],
          message: `"${variant.label}" would make the price negative`,
        });
      }
    }
  });

const MAX_IMAGES = 5;
const MAX_BYTES = 8 * 1024 * 1024;
const ALLOWED = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/heic']);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_BYTES, files: MAX_IMAGES },
  fileFilter: (_req, file, cb) => {
    if (!ALLOWED.has(file.mimetype)) {
      cb(new ApiError(400, 'VALIDATION_FAILED', `${file.mimetype} is not an image Sorted can read.`));
      return;
    }
    cb(null, true);
  },
}).array('images', MAX_IMAGES);

export type CatalogueDeps = {
  db: Firestore;
  verify: TokenVerifier;
  transport: ChatTransport;
  model: string;
};

export function catalogueRouter(deps: CatalogueDeps): Router {
  const router = Router();

  router.post(
    '/catalogue/extract',
    requireSeller(deps.verify),
    (req, res, next) => {
      upload(req, res, (err: unknown) => {
        if (err instanceof MulterError) {
          // Multer's own messages are terse; translate the two a seller can hit.
          const message =
            err.code === 'LIMIT_FILE_SIZE'
              ? 'Each photo must be 8MB or smaller.'
              : err.code === 'LIMIT_FILE_COUNT' || err.code === 'LIMIT_UNEXPECTED_FILE'
                ? `Send at most ${MAX_IMAGES} photos at a time.`
                : 'That upload could not be read.';
          next(new ApiError(400, 'VALIDATION_FAILED', message));
          return;
        }
        if (err) { next(err); return; }
        next();
      });
    },
    async (req, res, next) => {
      const files = (req.files ?? []) as Express.Multer.File[];
      if (files.length === 0) {
        next(new ApiError(400, 'VALIDATION_FAILED', 'Attach at least one photo.'));
        return;
      }
      try {
        const extraction = await extractCatalogue(
          files.map((f) => ({ buffer: f.buffer, mime: f.mimetype })),
          deps.transport,
          deps.model,
        );
        // tempId lets the app track a candidate across edits before it has a
        // Firestore id. Nothing is written here: the seller confirms first.
        res.json({
          candidates: extraction.candidates.map((c) => ({ ...c, tempId: randomUUID() })),
        });
      } catch (err) {
        next(err);
      }
    },
  );

  router.post('/catalogue/products', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = saveBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'Those products could not be saved.', parsed.error.format()));
      return;
    }
    try {
      res.json(await saveProducts(deps.db, req.sellerId!, parsed.data.products));
    } catch (err) { next(err); }
  });

  router.patch('/catalogue/products/:productId', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = patchBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'That change is not valid.', parsed.error.format()));
      return;
    }
    const ref = deps.db.doc(`sellers/${req.sellerId}/products/${req.params.productId}`);
    try {
      const snap = await ref.get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such product.')); return; }
      await ref.update({ ...parsed.data, updatedAt: FieldValue.serverTimestamp() });
      res.json({ product: (await ref.get()).data() });
    } catch (err) { next(err); }
  });

  router.delete('/catalogue/products/:productId', requireSeller(deps.verify), async (req, res, next) => {
    const ref = deps.db.doc(`sellers/${req.sellerId}/products/${req.params.productId}`);
    try {
      const snap = await ref.get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such product.')); return; }
      // Soft delete: week 3 orders reference products by id, and a hard delete
      // would orphan a line item on an order already sent to a buyer.
      await ref.update({ active: false, updatedAt: FieldValue.serverTimestamp() });
      res.json({ ok: true });
    } catch (err) { next(err); }
  });

  return router;
}
