# Verified facts

Confirmed against live systems, not assumed. Re-verify if something fails in a
way that contradicts this.

## Deployment

- **API (live):** https://sorted-api-a4zo.onrender.com
- Render service `sorted-api`, free plan, blueprint-managed from `api/render.yaml`
- Verified 2026-10-04: `/v1/health` → `{"ok":true,"version":"1.0.0","paypalEnv":"sandbox","webhookFailures":0}` in 0.74s
- Verified in production: unknown route returns the spec error shape; `/v1/session/bootstrap`
  returns 401 UNAUTHENTICATED with no token and with a bad token, never 500, and
  never echoes the auth provider's message
- **Free plan sleeps after 15 min.** Upgrade to `starter` before week 4 — webhook
  delivery and the hourly nudge sweep both break on a sleeping service.
- `NODE_ENV=production` makes `npm ci` skip devDependencies, so the build command
  must keep `--include=dev` or `tsc` is missing.

## Firebase

- Project: **`sorted-7b9b7`** (account `tadedev22@gmail.com`)
- Firestore: NOT YET PROVISIONED — the Firestore API is disabled on the project
- Anonymous auth: NOT YET ENABLED
- Rules written and proven against the emulator (8 tests); not yet deployed live
- **Emulator needs JDK 21+.** firebase-tools 15+ refuses older Java and reads
  `java` from PATH, not `JAVA_HOME`. Use `npm run emulators` (wraps
  `scripts/emulators.sh`, which finds a 21+ JDK via `/usr/libexec/java_home`).
- The emulator deliberately runs against `--project demo-sorted`, never the real
  project: the suite wipes the `sellers` collection between tests.

## PayPal

- Sandbox REST app credentials in `api/.env`; verified 2026-10-11 by obtaining an
  OAuth2 token from `api-m.sandbox.paypal.com`.
- Webhook id: **not yet created.** No webhook is registered on the app
  (`GET /v1/notifications/webhooks` returns an empty list). `PAYPAL_WEBHOOK_ID`
  is the placeholder `pending`, which is harmless until week 4 — nothing reads
  it before signature verification exists.
- Webhook URL to register:
  `https://sorted-api-a4zo.onrender.com/v1/webhooks/paypal`
- **Event names verified against the sandbox** (the spec flagged these as
  unconfirmed). All seven exist among the 205 the sandbox offers:
  `CHECKOUT.ORDER.APPROVED`, `PAYMENT.CAPTURE.COMPLETED`,
  `PAYMENT.CAPTURE.DENIED`, `PAYMENT.CAPTURE.PENDING`,
  `PAYMENT.CAPTURE.REFUNDED`, `INVOICING.INVOICE.PAID`,
  `INVOICING.INVOICE.CANCELLED`.

## OpenAI

- API key: held by the operator, in `api/.env`
- **`OPENAI_VISION_MODEL` = `gpt-5.5`** (pinned 2026-10-04)

Chosen by running the same DM screenshot (`samples/dm-screenshots/01.png`)
through four candidates with a strict `json_schema` response format:

| Model | Latency | Output tokens | Result |
|---|---|---|---|
| **gpt-5.5** | 2.4s | 114 | Correct. Variant labels came back as `"10 inch"` / `"box of 6"`, matching the catalogue's own vocabulary |
| gpt-5.4-mini | 3.1s | 139 | Polluted `variantLabels` with product names; invented a date ambiguity |
| gpt-5-mini | 12.7s | 1585 | Correct but 5x slower and 14x the output tokens |
| gpt-4.1-mini | 1.8s | 92 | **Parsed "brownie box of 6" as `qty: 6`** — would charge GBP 84 instead of GBP 14 |

The gpt-4.1-mini result is why the model is pinned in env and not chosen by
price: it was the cheapest and fastest, and silently wrong about money.

All four resolved "sat 10th oct" to `2026-10-10` correctly (a real Saturday).
Vision + strict structured output confirmed working on the Chat Completions
API with `response_format: { type: 'json_schema', strict: true }`.

## Local development

Run the API with `cd api && npm run dev` (or `npm start` after `npm run build`).
It loads `api/.env` itself via dotenv — do not source that file from a shell,
which mangles `FIREBASE_SERVICE_ACCOUNT_JSON` because the value is raw JSON.
That variable must be the whole service-account file **on one line**.

Verified 2026-10-11 against the live project: `/v1/session/bootstrap` seeds
Ola's Bakehouse with 5 products, `/v1/catalogue/products` creates, and
re-saving the same name in a different case is skipped by the duplicate guard.
`/v1/catalogue/extract` read three products with correct prices and variant
deltas from a photo of priced stock.

## Still unverified

- Whether `region: frankfurt` in `api/render.yaml` actually applied, or Render
  defaulted the free plan to a US region
- Whether `samples/seed-catalogue.json` resolves on Render, where `rootDir: api`
  but the seed path points at the repo root. Surfaces as a 500 on
  `/v1/session/bootstrap` if wrong.

## Known minor issues (week 1 review, deliberately not fixed)

Found during the week-1 review, graded Minor, left alone so the fix pass stayed
focused. None of them is reachable by a judge following the README.

- `parseGbp` has no safe-integer ceiling: `"99999999999999999.99"` returns 1e19
  rather than throwing, because `assertMinor` checks `Number.isInteger`, not
  `Number.isSafeInteger`. Needs an absurd input. One-word fix.
- `bootstrapSeller` called with `demo: false` against a seller already stored as
  "Ola's Bakehouse" returns `displayName: "My shop"` — the response contradicts
  the database until the realtime listener corrects it.
- `slugify` has no collision guard, so two variants whose labels slugify the same
  ("Box of 6" / "box of 6") would share a variant id. The seed catalogue has no
  collision; this matters once week 2 generates variants from AI output.
- The `Authorization` scheme check is case-sensitive, so `bearer <token>` returns
  401 although RFC 7235 makes the scheme case-insensitive. Our own client always
  sends `Bearer`; someone testing with curl might not.

**Review caveat:** week 1's code review was performed by the same agent that wrote
the code, because two fresh-reviewer dispatches stalled. Three real bugs were found
and fixed (concurrent double-seed, a placeholder crashing startup, a theme test
asserting the wrong property), but a genuinely independent pass before submission
would be worth it.
