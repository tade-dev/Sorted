import { Router } from 'express';
import { z } from 'zod';
import { FieldValue } from 'firebase-admin/firestore';
import multer, { MulterError } from 'multer';
import type { Firestore } from 'firebase-admin/firestore';
import { randomUUID } from 'node:crypto';
import { looksLikeUpload, visionMime } from '../lib/image_type.js';
import { ApiError } from '../lib/errors.js';
import { requireSeller, type TokenVerifier } from '../lib/auth.js';
import type { ChatTransport } from '../ai/client.js';
import { extractCatalogue } from '../ai/extract_catalogue.js';
import {
  productInputSchema,
  saveProducts,
  uniqueSlugs,
  variantInputSchema,
} from '../domain/products.js';
import { applyDelta } from '../domain/money.js';

const saveBodySchema = z.object({ products: z.array(productInputSchema).min(1).max(20) });
const patchBodySchema = z.object({
  name: z.string().min(1).max(60).optional(),
  description: z.string().max(240).optional(),
  basePriceMinor: z.number().int().nonnegative().optional(),
  depositMinor: z.number().int().nonnegative().nullable().optional(),
  variants: z.array(variantInputSchema).max(12).optional(),
  photoUrl: z.string().url().max(2048).nullable().optional(),
  /** False when the seller has sold out. Missing on older products means true. */
  inStock: z.boolean().optional(),
});

/**
 * Gives edited variants the stored shape (id, active). A label that already
 * existed keeps its id, so lines on open orders still point at it; new labels
 * get a slug that does not clash with any id kept.
 */
export function variantsWithIds(
  input: { axis: string; label: string; priceDeltaMinor: number }[],
  stored: { id: string; label: string }[],
): { id: string; axis: string; label: string; priceDeltaMinor: number; active: true }[] {
  const key = (label: string) => label.trim().toLowerCase();
  const byLabel = new Map(stored.map((v) => [key(v.label), v.id]));
  const used = new Set<string>();
  const kept = input.map((v) => {
    const id = byLabel.get(key(v.label));
    if (id && !used.has(id)) { used.add(id); return id; }
    return null;
  });
  const fresh = uniqueSlugs(input.map((v) => v.label));
  return input.map((v, i) => {
    let id = kept[i];
    if (!id) {
      const base = fresh[i]!;
      let candidate = base;
      let n = 1;
      while (used.has(candidate)) { n += 1; candidate = `${base}-${n}`; }
      id = candidate;
      used.add(id);
    }
    return { id, axis: v.axis, label: v.label.trim(), priceDeltaMinor: v.priceDeltaMinor, active: true as const };
  });
}

/**
 * A photo URL must be a Firebase Storage download link to this seller's own
 * folder for this product, so a client cannot point a product at any image
 * on the web or at another seller's upload.
 */
export function isOwnPhotoUrl(url: string, sellerId: string, productId: string): boolean {
  let parsed: URL;
  try { parsed = new URL(url); } catch { return false; }
  if (parsed.protocol !== 'https:' || parsed.hostname !== 'firebasestorage.googleapis.com') return false;
  const match = /^\/v0\/b\/[^/]+\/o\/(.+)$/.exec(parsed.pathname);
  if (!match) return false;
  const object = decodeURIComponent(match[1]!);
  return object.startsWith(`sellers/${sellerId}/products/${productId}/`) && !object.includes('..');
}

const MAX_IMAGES = 5;
const MAX_BYTES = 8 * 1024 * 1024;

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_BYTES, files: MAX_IMAGES },
  fileFilter: (_req, file, cb) => {
    if (!looksLikeUpload(file.mimetype)) {
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
          files.map((f) => ({ buffer: f.buffer, mime: visionMime(f.buffer) })),
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
    const photoUrl = parsed.data.photoUrl;
    if (photoUrl && !isOwnPhotoUrl(photoUrl, req.sellerId!, String(req.params.productId))) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'That photo link is not one Sorted uploaded.'));
      return;
    }
    const ref = deps.db.doc(`sellers/${req.sellerId}/products/${req.params.productId}`);
    try {
      const snap = await ref.get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such product.')); return; }

      // Validate the patch MERGED OVER the stored product, not on its own.
      // Sending only basePriceMinor used to skip the check entirely, so a
      // price could be dropped below a stored variant's discount and persist
      // an effective negative price that week 3 would total.
      const stored = snap.data() as {
        basePriceMinor: number;
        variants?: { id: string; label: string; priceDeltaMinor: number }[];
      };
      const effectiveBase = parsed.data.basePriceMinor ?? stored.basePriceMinor;
      const effectiveVariants = parsed.data.variants ?? stored.variants ?? [];
      for (const variant of effectiveVariants) {
        try {
          applyDelta(effectiveBase, variant.priceDeltaMinor);
        } catch {
          next(
            new ApiError(
              400,
              'VALIDATION_FAILED',
              `"${variant.label}" would make the price negative.`,
            ),
          );
          return;
        }
      }

      // Raw input variants have no id or active flag; stored that way they
      // could never be chosen on an order again.
      const { variants, ...rest } = parsed.data;
      const update: Record<string, unknown> = { ...rest };
      if (variants) update.variants = variantsWithIds(variants, stored.variants ?? []);
      if (rest.name !== undefined) update.name = rest.name.trim();
      await ref.update({ ...update, updatedAt: FieldValue.serverTimestamp() });
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
