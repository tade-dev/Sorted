import cors from 'cors';
import express from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { Env } from './env.js';
import { ApiError, errorHandler } from './lib/errors.js';
import type { TokenVerifier } from './lib/auth.js';
import type { ChatTransport } from './ai/client.js';
import type { PayPalFetch } from './paypal/client.js';
import { catalogueRouter } from './routes/catalogue.js';
import { ordersRouter } from './routes/orders.js';
import { healthRouter } from './routes/health.js';
import { sessionRouter } from './routes/session.js';

export type AppDeps = {
  env: Env;
  db: Firestore;
  verify: TokenVerifier;
  transport: ChatTransport;
  paypal: PayPalFetch;
};

export function createApp(deps: AppDeps): express.Express {
  const app = express();
  app.disable('x-powered-by');

  // The Flutter web build is served from a different origin to this API, so
  // without CORS the browser blocks every call and the hosted demo cannot
  // reach its own backend.
  //
  // Any origin is allowed on purpose. Every protected route authenticates with
  // a Firebase ID token in the Authorization header, never a cookie, so there
  // are no ambient credentials for another site to ride on and nothing to
  // gain by calling this from elsewhere.
  app.use(
    cors({
      origin: true,
      methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key'],
      maxAge: 86_400,
    }),
  );

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

  app.use(
    '/v1',
    ordersRouter({
      db: deps.db,
      verify: deps.verify,
      transport: deps.transport,
      paypal: deps.paypal,
      model: deps.env.OPENAI_VISION_MODEL,
    }),
  );

  app.use((_req, _res, next) => {
    next(new ApiError(404, 'NOT_FOUND', 'Route not found.'));
  });
  app.use(errorHandler);

  return app;
}
