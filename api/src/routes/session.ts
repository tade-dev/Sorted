import { Router } from 'express';
import { z } from 'zod';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { ApiError } from '../lib/errors.js';
import { requireSeller, type TokenVerifier } from '../lib/auth.js';
import { bootstrapSeller } from '../domain/seed.js';

const bodySchema = z.object({ demo: z.boolean().default(true) });

/**
 * What onboarding and Settings may change on the seller doc. Every field is
 * optional so each screen sends only what it owns. `personaTone` is the tone
 * sample reply drafting already reads.
 */
export const sellerPatchSchema = z
  .object({
    displayName: z.string().trim().min(1).max(60),
    personaTone: z.string().max(500),
    sells: z.array(z.string().trim().min(1).max(40)).max(8),
    channels: z.array(z.string().trim().min(1).max(40)).max(8),
    fulfilmentMode: z.enum(['collection', 'delivery', 'both']),
    /**
     * Where buyers' payments go. Empty clears it, and payments go to the
     * shared sandbox merchant again.
     */
    paypalEmail: z.union([z.string().trim().toLowerCase().email().max(127), z.literal('')]),
    /** No OAuth: attaches the seller to the shared sandbox merchant. */
    paypalConnected: z.literal(true),
    /** Finished or skipped onboarding. */
    onboarded: z.literal(true),
  })
  .partial()
  .strict();

export function sessionRouter(deps: { db: Firestore; verify: TokenVerifier }): Router {
  const router = Router();

  router.post('/session/bootstrap', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = bodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'Invalid request body.', parsed.error.format()));
      return;
    }
    try {
      const result = await bootstrapSeller(deps.db, req.sellerId!, parsed.data);
      res.json(result);
    } catch (err) {
      next(err);
    }
  });

  router.patch('/session/seller', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = sellerPatchSchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'That change is not valid.', parsed.error.format()));
      return;
    }
    const { paypalConnected, onboarded, paypalEmail, ...fields } = parsed.data;
    const update: Record<string, unknown> = { ...fields, updatedAt: FieldValue.serverTimestamp() };
    if (paypalEmail !== undefined) update.paypalEmail = paypalEmail === '' ? null : paypalEmail;
    if (paypalConnected) {
      update.paypalMerchant = 'shared_sandbox';
      update.paypalConnectedAt = FieldValue.serverTimestamp();
    }
    if (onboarded) update.onboardedAt = FieldValue.serverTimestamp();
    try {
      const ref = deps.db.doc(`sellers/${req.sellerId}`);
      if (!(await ref.get()).exists) {
        next(new ApiError(404, 'NOT_FOUND', 'Your shop is still being set up. Try again in a moment.'));
        return;
      }
      await ref.set(update, { merge: true });
      res.json({ ok: true });
    } catch (err) {
      next(err);
    }
  });

  return router;
}
