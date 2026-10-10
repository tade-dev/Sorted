import express from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { Env } from './env.js';
import { ApiError, errorHandler } from './lib/errors.js';
import type { TokenVerifier } from './lib/auth.js';
import type { ChatTransport } from './ai/client.js';
import { catalogueRouter } from './routes/catalogue.js';
import { healthRouter } from './routes/health.js';
import { sessionRouter } from './routes/session.js';

export type AppDeps = {
  env: Env;
  db: Firestore;
  verify: TokenVerifier;
  transport: ChatTransport;
};

export function createApp(deps: AppDeps): express.Express {
  const app = express();
  app.disable('x-powered-by');

  // NOTE: the PayPal webhook route (week 4) must be mounted BEFORE this
  // JSON parser with express.raw(), because signature verification needs
  // the unparsed body.
  app.use(express.json({ limit: '1mb' }));

  app.use('/v1', healthRouter(deps.env));
  app.use('/v1', sessionRouter({ db: deps.db, verify: deps.verify }));
  app.use(
    '/v1',
    catalogueRouter({
      db: deps.db,
      verify: deps.verify,
      transport: deps.transport,
      model: deps.env.OPENAI_VISION_MODEL,
    }),
  );

  app.use((_req, _res, next) => {
    next(new ApiError(404, 'NOT_FOUND', 'Route not found.'));
  });
  app.use(errorHandler);

  return app;
}
