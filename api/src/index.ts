import { createApp } from './app.js';
import { loadEnv } from './env.js';
import { adminTokenVerifier, initFirebase } from './firebase.js';
import { makeOpenAiTransport } from './ai/client.js';

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
}).listen(env.PORT, () => {
  console.log(`sorted api listening on :${env.PORT} (${env.PAYPAL_ENV})`);
});
