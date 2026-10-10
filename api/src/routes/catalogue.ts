import { Router } from 'express';
import multer, { MulterError } from 'multer';
import type { Firestore } from 'firebase-admin/firestore';
import { randomUUID } from 'node:crypto';
import { ApiError } from '../lib/errors.js';
import { requireSeller, type TokenVerifier } from '../lib/auth.js';
import type { ChatTransport } from '../ai/client.js';
import { extractCatalogue } from '../ai/extract_catalogue.js';

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

  return router;
}
