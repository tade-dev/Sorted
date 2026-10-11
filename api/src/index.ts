// Loads api/.env before loadEnv() reads process.env, so the service runs
// locally with nothing exported by hand. Values containing JSON or quotes
// survive this; sourcing the file from a shell mangles them. On Render the
// file is absent and the dashboard's variables are already in the
// environment, so this is a no-op there.
import 'dotenv/config';

import { createApp } from './app.js';
import { loadEnv } from './env.js';
import { adminTokenVerifier, initFirebase } from './firebase.js';
import { makeOpenAiTransport } from './ai/client.js';
import { makePayPalClient } from './paypal/client.js';

// Firestore's gRPC layer creates its client lazily in the background, so a
// credential failure surfaces as an unhandled rejection outside any request's
// promise chain. Node's default is to kill the process, which on a hosted
// instance means a crash loop and 502s for anyone using the app. Log it loudly
// and keep serving: the request that triggered it still gets its 500.
process.on('unhandledRejection', (reason) => {
  console.error('unhandled rejection (service kept alive):', reason);
});

const env = loadEnv();
const { db, auth } = initFirebase(env);

createApp({
  env,
  db,
  verify: adminTokenVerifier(auth),
  transport: makeOpenAiTransport(env),
  paypal: makePayPalClient(env),
}).listen(env.PORT, () => {
  console.log(`sorted api listening on :${env.PORT} (${env.PAYPAL_ENV})`);
});
