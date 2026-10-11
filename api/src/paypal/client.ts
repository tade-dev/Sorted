import type { Env } from '../env.js';
import { ApiError } from '../lib/errors.js';

export type PayPalFetch = (
  path: string,
  init: { method: string; body?: unknown; requestId?: string },
) => Promise<unknown>;

/** Refresh this long before the token actually expires. */
const SAFETY_MARGIN_MS = 60_000;

export function makePayPalClient(env: Env, now: () => number = Date.now): PayPalFetch {
  let token: string | null = null;
  let expiresAtMs = 0;

  async function getToken(): Promise<string> {
    if (token && now() < expiresAtMs - SAFETY_MARGIN_MS) return token;

    const credentials = Buffer.from(
      `${env.PAYPAL_CLIENT_ID}:${env.PAYPAL_CLIENT_SECRET}`,
    ).toString('base64');

    const res = await fetch(`${env.PAYPAL_API_BASE}/v1/oauth2/token`, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${credentials}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'grant_type=client_credentials',
    });

    if (!res.ok) {
      throw new ApiError(502, 'PAYPAL_UNAVAILABLE', 'Could not authenticate with PayPal.');
    }

    const json = (await res.json()) as { access_token: string; expires_in: number };
    token = json.access_token;
    expiresAtMs = now() + json.expires_in * 1000;
    return token;
  }

  return async (path, init) => {
    const bearer = await getToken();

    const res = await fetch(`${env.PAYPAL_API_BASE}${path}`, {
      method: init.method,
      headers: {
        Authorization: `Bearer ${bearer}`,
        'Content-Type': 'application/json',
        ...(init.requestId ? { 'PayPal-Request-Id': init.requestId } : {}),
      },
      ...(init.body === undefined ? {} : { body: JSON.stringify(init.body) }),
    });

    if (!res.ok) {
      // Surface PayPal's own issue code where there is one: AMOUNT_MISMATCH
      // and friends say far more than "502".
      let detail = '';
      try {
        const body = (await res.json()) as {
          name?: string;
          details?: { issue?: string; description?: string }[];
        };
        detail = body.details?.[0]?.issue ?? body.name ?? '';
      } catch {
        detail = await res.text().catch(() => '');
      }
      throw new ApiError(
        502,
        'PAYPAL_UNAVAILABLE',
        `PayPal rejected that request${detail ? ` (${detail})` : ''}. Nothing was charged.`,
        { status: res.status, detail },
      );
    }

    return res.json();
  };
}
