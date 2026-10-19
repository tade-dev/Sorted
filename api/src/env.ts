import { z } from 'zod';

const required = (name: string) => z.string().min(1, `${name} must not be empty`);

/** Where PayPal sends the buyer after checkout, when PUBLIC_BASE_URL is unset. */
export const DEFAULT_PUBLIC_BASE_URL = 'https://sorted-api-a4zo.onrender.com';

/** Seven days: the design spec's lifecycle table. */
export const DEFAULT_ORDER_EXPIRY_HOURS = 168;

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  PAYPAL_CLIENT_ID: required('PAYPAL_CLIENT_ID'),
  PAYPAL_CLIENT_SECRET: required('PAYPAL_CLIENT_SECRET'),
  PAYPAL_WEBHOOK_ID: required('PAYPAL_WEBHOOK_ID'),
  OPENAI_API_KEY: required('OPENAI_API_KEY'),
  OPENAI_VISION_MODEL: required('OPENAI_VISION_MODEL'),
  FIREBASE_PROJECT_ID: required('FIREBASE_PROJECT_ID'),
  INTERNAL_TOKEN: required('INTERNAL_TOKEN'),
  /**
   * How long a checkout link stays open unpaid before the expiry sweep closes
   * it, counted from when the link was sent. Seven days, per the lifecycle
   * table in the design spec; PayPal's own TTL for an unapproved order is not
   * documented, so Sorted keeps its own clock.
   */
  ORDER_EXPIRY_HOURS: z.preprocess(
    (v) => (typeof v === 'string' && v.trim() === '' ? undefined : v),
    z.coerce.number().int().positive().max(24 * 90).default(DEFAULT_ORDER_EXPIRY_HOURS),
  ),
});

export type Env = z.infer<typeof schema> & {
  /** Sandbox unless PAYPAL_ENV=live is set. */
  readonly PAYPAL_ENV: 'sandbox' | 'live';
  readonly PAYPAL_API_BASE: 'https://api-m.sandbox.paypal.com' | 'https://api-m.paypal.com';
  /** Origin of this API. PayPal's buyer return and cancel URLs are built from it. */
  readonly PUBLIC_BASE_URL: string;
};

function resolvePublicBaseUrl(raw: string | undefined): string {
  if (raw === undefined || raw.trim() === '') return DEFAULT_PUBLIC_BASE_URL;
  const trimmed = raw.trim().replace(/\/+$/, '');
  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    throw new Error(
      'Environment is not configured — invalid: PUBLIC_BASE_URL (must be an absolute http(s) URL).',
    );
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new Error(
      'Environment is not configured — invalid: PUBLIC_BASE_URL (must be an absolute http(s) URL).',
    );
  }
  return trimmed;
}

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = schema.safeParse(source);
  if (!parsed.success) {
    // Split "you never set this" from "you set it to something wrong". The
    // first is what an operator filling in a hosting dashboard actually hits,
    // and Zod's own wording for it ("expected string, received undefined")
    // names no fix.
    const missing: string[] = [];
    const invalid: string[] = [];

    for (const issue of parsed.error.issues) {
      const name = issue.path.join('.');
      const raw = source[name];
      if (raw === undefined || raw.trim() === '') {
        missing.push(name);
      } else {
        invalid.push(`${name} (${issue.message})`);
      }
    }

    const parts: string[] = [];
    if (missing.length > 0) parts.push(`missing or empty: ${missing.join(', ')}`);
    if (invalid.length > 0) parts.push(`invalid: ${invalid.join(', ')}`);

    throw new Error(
      `Environment is not configured — ${parts.join('; ')}. ` +
        'Every required variable in api/.env.example must be set to a non-empty value. ' +
        'Use a placeholder such as "pending" for ones you do not have yet.',
    );
  }
  const live = source.PAYPAL_ENV?.trim().toLowerCase() === 'live';
  return {
    ...parsed.data,
    PAYPAL_ENV: live ? 'live' : 'sandbox',
    PAYPAL_API_BASE: live ? 'https://api-m.paypal.com' : 'https://api-m.sandbox.paypal.com',
    PUBLIC_BASE_URL: resolvePublicBaseUrl(source.PUBLIC_BASE_URL),
  };
}
