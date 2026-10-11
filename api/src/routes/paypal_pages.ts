import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import { buyerPage, buyerStatusLine } from '../paypal/buyer_page.js';

const ORDER_TOKEN = /^[A-Za-z0-9]{1,40}$/;

function sendPage(res: { type: (t: string) => void; set: (k: string, v: string) => void; send: (b: string) => void }, html: string) {
  res.type('html');
  res.set('Cache-Control', 'no-store');
  res.set('X-Content-Type-Options', 'nosniff');
  res.send(html);
}

/**
 * Shop name and a coarse status for a PayPal order id.
 * Nothing else from the order is returned: no buyer, no amount, no ids.
 */
async function lookup(
  db: Firestore,
  token: string,
): Promise<{ shop: string | null; status: string | null }> {
  if (!ORDER_TOKEN.test(token)) return { shop: null, status: null };
  const found = await db.collectionGroup('orders').where('paypalOrderId', '==', token).limit(1).get();
  const doc = found.docs[0];
  if (!doc) return { shop: null, status: null };
  const sellerId = doc.ref.parent.parent?.id;
  let shop: string | null = null;
  if (sellerId) {
    const seller = await db.doc(`sellers/${sellerId}`).get();
    const name = seller.get('displayName');
    if (typeof name === 'string' && name.trim()) shop = name.trim();
  }
  const status = doc.get('status');
  return { shop, status: typeof status === 'string' ? status : null };
}

export function paypalPagesRouter(db: Firestore): Router {
  const router = Router();

  router.get('/paypal/return', async (req, res) => {
    const token = typeof req.query.token === 'string' ? req.query.token : '';
    let shop: string | null = null;
    let status: string | null = null;
    try {
      if (token) ({ shop, status } = await lookup(db, token));
    } catch (err) {
      console.error('paypal return lookup failed', err instanceof Error ? err.name : 'error');
    }
    const headline = shop
      ? `Thanks, payment sent to ${shop}.`
      : 'Thanks, payment sent.';
    sendPage(
      res,
      buyerPage({
        title: 'Payment sent',
        headline,
        detail: 'You can close this page.',
        statusLine: buyerStatusLine(status),
      }),
    );
  });

  router.get('/paypal/cancel', (_req, res) => {
    sendPage(
      res,
      buyerPage({
        title: 'Payment cancelled',
        headline: 'Payment cancelled.',
        detail: 'Nothing was charged.',
      }),
    );
  });

  return router;
}
