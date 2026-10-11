# Share A DM, Get An Order — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A seller pastes or uploads a DM screenshot, sees what the AI read, fixes anything it could not work out, and gets a real PayPal checkout link plus a ready-to-send reply.

**Architecture:** The same `generateStructured()` seam Plan 2 built, with a second prompt and the `dmOrderSchema` that already exists. The model says *what* was ordered; `match_catalogue.ts` resolves it to real products and `money.ts` computes every price, so no number a buyer pays ever comes from an LLM. PayPal Orders v2 is called directly over REST — the agent toolkit is for week 5's nudge loop, where tool-calling is the point.

**Tech Stack:** Node 22 + TypeScript, Express 5, Zod 4, OpenAI `gpt-5.5`, PayPal Orders v2 (sandbox), Vitest + Supertest, Firebase Admin; Flutter 3.47.2, Riverpod 3, GoRouter, freezed.

**Spec:** `docs/superpowers/specs/2026-10-02-sorted-design.md` — §3 (endpoints 7-11), §4 (PayPal sequence), §5.2 and §5.3 (DM parse, reply drafting), §6 (screens).

**Design:** `docs/design/screens/Reading.dc.html`, `Draft.dc.html`, `Reply.dc.html`. `ShareSheet.dc.html` is illustrative — it is the OS share sheet, not a screen to build.

**Verified facts this plan depends on:** `docs/verified-facts.md` records a real sandbox order. Two spec guesses were wrong and the plan uses the verified values: the created status is **`PAYER_ACTION_REQUIRED`** (not `CREATED`), and the approval link is **`links[rel="payer-action"]`** (not `approve`).

**Prior art to reuse:** `money.ts`, `generateStructured()`, `dmOrderSchema`, `ApiError`/`errorHandler`, `requireSeller`, `SortedColors`/`SortedShape`, `PrimaryButton`/`SelectableChip`/`WarningCard`, `formatGbp`/`parseGbpInput`, `describeApiError`. Read them before writing anything.

## Global Constraints

- **Money is always an integer in minor units (pence) plus `currency: 'GBP'`.** No floats. All arithmetic through `api/src/domain/money.ts`.
- **No price a buyer pays ever comes from the LLM.** The model identifies items; the catalogue supplies prices; `money.ts` totals them.
- **The amount sent to PayPal must equal the order's stored `amountDueMinor`,** rendered with `toPayPalValue`.
- `amount.breakdown.item_total` must equal the sum of `items[]` or PayPal rejects the order.
- Every route under `/v1`; every error exactly `{ error: { code, message, details? } }`.
- All client Firestore writes denied; writes go only through the API.
- `custom_id` on the purchase unit is `"<sellerId>:<orderId>"`, so webhook handling in week 4 needs no lookup table.
- Every PayPal create call sends `PayPal-Request-Id` for idempotency.
- Model id from `env.OPENAI_VISION_MODEL`. **Never set `temperature`** — `gpt-5.5` rejects any non-default value.
- Timestamps are Firestore `Timestamp` at rest, ISO-8601 over the API.
- UK English in all copy. "PayPal" must not appear in the product name, logo or app title.
- No widget hardcodes a hex value.
- Run the emulator with `npm run emulators`; restart it if hooks start timing out.

## Review Focus

Five failure modes the spec implies but does not spell out. Each gets a test in the task that owns it.

1. **A screenshot that is not a DM at all** — a receipt, a selfie, a menu. The parser must return zero line items and the app must say so, rather than inventing an order a seller might send to a buyer. *(Tasks 1 and 9)*
2. **An item the catalogue does not have.** "gluten free carrot cake" must become an `unknown_product` ambiguity with no price, never a silently dropped line or a £0 one. *(Task 2)*
3. **Confirming while blocking ambiguities remain.** The spec disables the button; the API must refuse too, or a link goes to a buyer with a guessed size and a price the seller never agreed. *(Task 6)*
4. **PayPal rejecting the create call** — amount mismatch, 422, or a 5xx. The order must stay `draft` with its data intact and the seller must be told, not left with a half-created order and no link. *(Task 6)*
5. **The total disagreeing with what PayPal charges.** Whatever the seller sees on the Draft screen must be the exact amount on the checkout page, including when a deposit is set. *(Tasks 3 and 6)*

---

## File Structure

| File | Responsibility |
|---|---|
| `api/src/ai/parse_dm.ts` | Prompt, JSON schema and call for DM → structured order. |
| `api/src/domain/match_catalogue.ts` | Resolve the model's line items to real products, variants and prices. |
| `api/src/domain/orders.ts` | Order document shape, totals, state transitions, Firestore writes. |
| `api/src/paypal/client.ts` | OAuth2 token caching and the authenticated fetch wrapper. |
| `api/src/paypal/orders.ts` | `createPayPalOrder` — request shape and approval-link extraction. |
| `api/src/ai/draft_reply.ts` | Prompt and call for the seller-tone reply. |
| `api/src/routes/orders.ts` | `POST /orders/draft`, `/resolve`, `/confirm`, `/reply/regenerate`, `GET /orders`. |
| `app/lib/models/order.dart`, `line_item.dart` | freezed models for the order and its lines. |
| `app/lib/data/orders_repository.dart` | Firestore order stream + API writes. |
| `app/lib/providers/orders_providers.dart` | Draft controller and the live order stream. |
| `app/lib/features/order/intake_screen.dart` | Paste text or upload a screenshot. The web path, and the mobile fallback. |
| `app/lib/features/order/reading_screen.dart` | The ticking checklist while the model works. |
| `app/lib/features/order/draft_screen.dart` | Line items, ambiguity chips, total, Create link. |
| `app/lib/features/order/reply_screen.dart` | The drafted reply, tone chips, copy button. |

---

### Task 1: DM to a structured order

**Files:**
- Create: `api/src/ai/parse_dm.ts`
- Test: `api/test/parse-dm.test.ts`, `api/test/parse-dm.live.test.ts`

**Interfaces:**
- Consumes: `dmOrderSchema`, `DmOrder` from `src/ai/schemas.ts`; `generateStructured`, `toDataUri`, `ChatTransport` from `src/ai/client.ts`.
- Produces, from `src/ai/parse_dm.ts`:
  - `DM_ORDER_SYSTEM: string`, `DM_ORDER_JSON_SCHEMA: Record<string, unknown>`
  - `type CatalogueBrief = { id: string; name: string; basePriceMinor: number; variantLabels: string[] }[]`
  - `parseDm(input: { image?: { buffer: Buffer; mime: string }; text?: string }, catalogue: CatalogueBrief, today: string, transport: ChatTransport, model: string): Promise<DmOrder>`

- [ ] **Step 1: Write the failing test**

Create `api/test/parse-dm.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { DM_ORDER_SYSTEM, parseDm, type CatalogueBrief } from '../src/ai/parse_dm.js';
import type { ChatTransport } from '../src/ai/client.js';

const catalogue: CatalogueBrief = [
  { id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200, variantLabels: ['8 inch', '10 inch'] },
  { id: 'p2', name: 'Brownie box', basePriceMinor: 1400, variantLabels: ['Box of 6', 'Box of 12'] },
];

const jess = {
  buyerName: 'Jess M', buyerHandle: 'jess.mcr', buyerEmail: null, channel: 'instagram',
  lineItems: [
    { nameRaw: 'lemon drizzle cake, the 10 inch one', qty: 1, variantLabels: ['10 inch'] },
    { nameRaw: 'brownie box of 6', qty: 1, variantLabels: ['Box of 6'] },
  ],
  fulfilment: { mode: 'collection', date: '2026-10-10', notes: "for her mum's birthday" },
  depositRequestedMinor: null, ambiguities: [], overallConfidence: 0.95,
};

const transportReturning = (payload: unknown): ChatTransport =>
  async () => ({ content: JSON.stringify(payload) });

describe('parseDm', () => {
  it('parses a screenshot into a structured order', async () => {
    const out = await parseDm(
      { image: { buffer: Buffer.from('x'), mime: 'image/png' } },
      catalogue, '2026-10-04', transportReturning(jess), 'm',
    );
    expect(out.buyerName).toBe('Jess M');
    expect(out.lineItems).toHaveLength(2);
    expect(out.fulfilment.date).toBe('2026-10-10');
  });

  it('parses pasted text with no image', async () => {
    const out = await parseDm(
      { text: 'can I get a 10 inch lemon drizzle for sat?' },
      catalogue, '2026-10-04', transportReturning(jess), 'm',
    );
    expect(out.lineItems).toHaveLength(2);
  });

  it('returns no line items for a screenshot that is not an order', async () => {
    // A receipt, a selfie, a menu. Inventing an order here would put a wrong
    // checkout link in front of a buyer.
    const empty = { ...jess, buyerName: null, buyerHandle: null, lineItems: [], overallConfidence: 0.1 };
    const out = await parseDm(
      { image: { buffer: Buffer.from('x'), mime: 'image/png' } },
      catalogue, '2026-10-04', transportReturning(empty), 'm',
    );
    expect(out.lineItems).toEqual([]);
  });

  it('rejects a call with neither an image nor text', async () => {
    await expect(
      parseDm({}, catalogue, '2026-10-04', transportReturning(jess), 'm'),
    ).rejects.toThrow(/image or text/i);
  });

  it('puts the catalogue in the prompt so the model can name real variants', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({ content: JSON.stringify(jess) });
    await parseDm({ text: 'hi' }, catalogue, '2026-10-04', transport, 'm');
    const body = JSON.stringify(transport.mock.calls[0]![0]);
    expect(body).toContain('Lemon drizzle cake');
    expect(body).toContain('10 inch');
  });

  it("tells the model today's date so relative dates resolve", async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({ content: JSON.stringify(jess) });
    await parseDm({ text: 'next saturday please' }, catalogue, '2026-10-04', transport, 'm');
    expect(JSON.stringify(transport.mock.calls[0]![0])).toContain('2026-10-04');
  });

  it('never sets temperature, which the pinned model rejects', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({ content: JSON.stringify(jess) });
    await parseDm({ text: 'hi' }, catalogue, '2026-10-04', transport, 'm');
    expect(transport.mock.calls[0]![0]).not.toHaveProperty('temperature');
  });

  it('instructs the model not to guess a size', () => {
    expect(DM_ORDER_SYSTEM).toMatch(/do not guess/i);
  });

  it('instructs the model that "box of 6" is one box, not six', () => {
    // gpt-4.1-mini got this wrong and would have billed GBP 84 instead of 14.
    expect(DM_ORDER_SYSTEM).toMatch(/box of 6/i);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd api && npx vitest run test/parse-dm.test.ts
```

Expected: FAIL — cannot resolve `../src/ai/parse_dm.js`.

- [ ] **Step 3: Write `api/src/ai/parse_dm.ts`**

```ts
import { dmOrderSchema, type DmOrder } from './schemas.js';
import { generateStructured, toDataUri, type ChatTransport } from './client.js';
import { ApiError } from '../lib/errors.js';

export type CatalogueBrief = {
  id: string;
  name: string;
  basePriceMinor: number;
  variantLabels: string[];
}[];

export const DM_ORDER_SYSTEM = [
  'You read a conversation between a UK small seller and a buyer, and extract the single order the buyer is placing.',
  'The seller is the party offering goods; the buyer is the other party.',
  'Quote the buyer\'s own words in nameRaw, not a tidied-up version.',
  'A phrase like "box of 6" or "pack of 12" describes ONE item whose variant is that size. It is not a quantity of 6 or 12. Only set qty above 1 when the buyer clearly asks for several of something.',
  'Match variantLabels to the seller\'s own variant labels where you can; the catalogue is given below.',
  'Resolve relative dates ("next Saturday", "the 10th") against today\'s date, given below, and return an ISO date.',
  'If the buyer never stated a size, a quantity or a date, do not guess. Add an ambiguity with a question the seller can answer in one tap, and leave the field null or empty.',
  'If the conversation contains no order at all — a receipt, a menu, small talk, a photo of something else — return an empty lineItems array rather than inventing one.',
  'Never state a price. Prices come from the seller\'s catalogue, not from you.',
].join(' ');

export const DM_ORDER_JSON_SCHEMA: Record<string, unknown> = {
  type: 'object',
  additionalProperties: false,
  required: [
    'buyerName', 'buyerHandle', 'buyerEmail', 'channel', 'lineItems',
    'fulfilment', 'depositRequestedMinor', 'ambiguities', 'overallConfidence',
  ],
  properties: {
    buyerName: { type: ['string', 'null'] },
    buyerHandle: { type: ['string', 'null'] },
    buyerEmail: { type: ['string', 'null'] },
    channel: {
      type: 'string',
      enum: ['instagram', 'tiktok', 'whatsapp', 'other', 'unknown'],
    },
    lineItems: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['nameRaw', 'qty', 'variantLabels'],
        properties: {
          nameRaw: { type: 'string' },
          qty: { type: 'integer' },
          variantLabels: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    fulfilment: {
      type: 'object', additionalProperties: false,
      required: ['mode', 'date', 'notes'],
      properties: {
        mode: { type: 'string', enum: ['collection', 'delivery', 'unknown'] },
        date: { type: ['string', 'null'] },
        notes: { type: ['string', 'null'] },
      },
    },
    depositRequestedMinor: { type: ['integer', 'null'] },
    ambiguities: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['field', 'kind', 'question', 'options', 'blocking'],
        properties: {
          field: { type: 'string' },
          kind: {
            type: 'string',
            enum: ['missing', 'unclear', 'unknown_product', 'price_conflict', 'qty_unclear'],
          },
          question: { type: 'string' },
          options: { type: 'array', items: { type: 'string' } },
          blocking: { type: 'boolean' },
        },
      },
    },
    overallConfidence: { type: 'number' },
  },
};

function describeCatalogue(catalogue: CatalogueBrief): string {
  if (catalogue.length === 0) return 'The seller has no products in their catalogue yet.';
  return [
    "The seller's catalogue, for matching names and variant labels:",
    ...catalogue.map(
      (p) =>
        `- ${p.name}${p.variantLabels.length ? ` (${p.variantLabels.join(', ')})` : ''}`,
    ),
  ].join('\n');
}

export async function parseDm(
  input: { image?: { buffer: Buffer; mime: string }; text?: string },
  catalogue: CatalogueBrief,
  today: string,
  transport: ChatTransport,
  model: string,
): Promise<DmOrder> {
  if (!input.image && !input.text?.trim()) {
    throw new ApiError(
      400,
      'VALIDATION_FAILED',
      'Share a screenshot or paste the message — one image or text is required.',
    );
  }

  const system = [
    DM_ORDER_SYSTEM,
    `\n\nToday is ${today}.`,
    `\n\n${describeCatalogue(catalogue)}`,
  ].join('');

  return generateStructured(
    {
      schemaName: 'dm_order',
      schema: dmOrderSchema,
      jsonSchema: DM_ORDER_JSON_SCHEMA,
      system,
      ...(input.text?.trim() ? { text: input.text.trim() } : {}),
      ...(input.image
        ? { images: [toDataUri(input.image.buffer, input.image.mime)] }
        : {}),
      // No temperature: gpt-5.5 only accepts the default.
    },
    transport,
    model,
  );
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
cd api && npx vitest run test/parse-dm.test.ts
```

Expected: PASS, 9 tests.

- [ ] **Step 5: Write the live test**

Create `api/test/parse-dm.live.test.ts`. The unit tests all inject a fake transport, which is how Plan 2 shipped a request body the model rejected outright.

```ts
import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { parseDm, type CatalogueBrief } from '../src/ai/parse_dm.js';
import { makeOpenAiTransport } from '../src/ai/client.js';
import { loadEnv } from '../src/env.js';

const envFile = existsSync('.env') ? readFileSync('.env', 'utf8') : '';
const key = envFile.match(/^OPENAI_API_KEY=(.+)$/m)?.[1]?.trim();
const model = envFile.match(/^OPENAI_VISION_MODEL=(.+)$/m)?.[1]?.trim();
const ready = Boolean(key) && Boolean(model) && model !== 'pending';

const catalogue: CatalogueBrief = [
  { id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200, variantLabels: ['8 inch', '10 inch'] },
  { id: 'p2', name: 'Brownie box', basePriceMinor: 1400, variantLabels: ['Box of 6', 'Box of 12'] },
];

describe.skipIf(!ready)('parseDm against the real model', () => {
  const env = loadEnv({
    NODE_ENV: 'test',
    PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
    OPENAI_API_KEY: key!, OPENAI_VISION_MODEL: model!,
    FIREBASE_PROJECT_ID: 'x', INTERNAL_TOKEN: 'x',
  });

  it('reads the canonical Jess screenshot correctly', async () => {
    const out = await parseDm(
      {
        image: {
          buffer: readFileSync('../samples/dm-screenshots/01.png'),
          mime: 'image/png',
        },
      },
      catalogue,
      '2026-10-04',
      makeOpenAiTransport(env),
      env.OPENAI_VISION_MODEL,
    );

    expect(out.buyerName).toMatch(/Jess/);
    expect(out.lineItems).toHaveLength(2);
    // "box of 6" is one box. Reading it as six would bill GBP 84 for GBP 14
    // of brownies — the exact error that drove the model choice.
    for (const item of out.lineItems) expect(item.qty).toBe(1);
    // "sat 10th oct" against a 2026-10-04 today is Saturday 10 October.
    expect(out.fulfilment.date).toBe('2026-10-10');
    expect(out.fulfilment.mode).toBe('collection');
  }, 90_000);
});
```

- [ ] **Step 6: Run the live test**

```bash
cd api && npx vitest run test/parse-dm.live.test.ts
```

Expected: PASS, 1 test (skipped without a key). If the date assertion fails, check the system prompt is actually receiving `today`.

- [ ] **Step 7: Commit**

```bash
cd /Users/bstar/Documents/development/apps/flutter/sorted
git add api/src/ai/parse_dm.ts api/test/parse-dm.test.ts api/test/parse-dm.live.test.ts
git commit -m "feat(api): parse a DM screenshot into a structured order

The catalogue and today's date go into the prompt so the model can cite
real variant labels and resolve relative dates. It is told explicitly
that 'box of 6' is one box, not six, and never to state a price.

A conversation with no order returns an empty lineItems array rather
than an invented one. The live test pins the quantity and date
behaviour against the real model, because every unit test injects a
fake transport and that is how Plan 2 shipped a body the model
rejected."
```

---

### Task 2: Matching line items to the catalogue

Covers Review Focus item 2. This is where prices come from, so it is where a wrong number would reach a buyer.

**Files:**
- Create: `api/src/domain/match_catalogue.ts`
- Test: `api/test/match-catalogue.test.ts`

**Interfaces:**
- Consumes: `applyDelta`, `multiplyMinor`, `sumMinor`, `assertMinor` from `src/domain/money.ts`; `DmOrder`, `Ambiguity` from `src/ai/schemas.ts`.
- Produces, from `src/domain/match_catalogue.ts`:
  - `type StoredVariant = { id: string; axis: string; label: string; priceDeltaMinor: number; active: boolean }`
  - `type StoredProduct = { id: string; name: string; basePriceMinor: number; depositMinor: number | null; variants: StoredVariant[]; active: boolean }`
  - `type MatchedLine = { id: string; productId: string | null; variantIds: string[]; nameRaw: string; nameResolved: string | null; qty: number; unitPriceMinor: number; lineTotalMinor: number; matchConfidence: number; matchMethod: 'exact' | 'fuzzy' | 'unmatched' }`
  - `matchLineItems(items: DmOrder['lineItems'], products: StoredProduct[]): { lines: MatchedLine[]; ambiguities: Ambiguity[]; subtotalMinor: number }`
  - `normalise(s: string): string`

- [ ] **Step 1: Write the failing test**

Create `api/test/match-catalogue.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { matchLineItems, normalise, type StoredProduct } from '../src/domain/match_catalogue.js';

const lemon: StoredProduct = {
  id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200, depositMinor: null, active: true,
  variants: [
    { id: '8-inch', axis: 'size', label: '8 inch', priceDeltaMinor: 0, active: true },
    { id: '10-inch', axis: 'size', label: '10 inch', priceDeltaMinor: 1000, active: true },
  ],
};
const brownies: StoredProduct = {
  id: 'p2', name: 'Brownie box', basePriceMinor: 1400, depositMinor: null, active: true,
  variants: [
    { id: 'box-of-6', axis: 'size', label: 'Box of 6', priceDeltaMinor: 0, active: true },
    { id: 'box-of-12', axis: 'size', label: 'Box of 12', priceDeltaMinor: 1200, active: true },
  ],
};
const catalogue = [lemon, brownies];

describe('normalise', () => {
  it('ignores case, punctuation and extra space', () => {
    expect(normalise('  Lemon-Drizzle  CAKE! ')).toBe(normalise('lemon drizzle cake'));
  });
});

describe('matchLineItems', () => {
  it('reproduces the £56 Jess order the design screens show', () => {
    const { lines, subtotalMinor, ambiguities } = matchLineItems(
      [
        { nameRaw: 'lemon drizzle cake, the 10 inch one', qty: 1, variantLabels: ['10 inch'] },
        { nameRaw: 'brownie box of 6', qty: 1, variantLabels: ['Box of 6'] },
      ],
      catalogue,
    );
    expect(lines[0]!.unitPriceMinor).toBe(4200);
    expect(lines[1]!.unitPriceMinor).toBe(1400);
    expect(subtotalMinor).toBe(5600);
    expect(ambiguities).toEqual([]);
  });

  it('multiplies by quantity', () => {
    const { lines, subtotalMinor } = matchLineItems(
      [{ nameRaw: 'brownie box', qty: 3, variantLabels: ['Box of 6'] }],
      catalogue,
    );
    expect(lines[0]!.lineTotalMinor).toBe(4200);
    expect(subtotalMinor).toBe(4200);
  });

  it('matches a product by a loose name', () => {
    const { lines } = matchLineItems(
      [{ nameRaw: 'the lemon drizzle', qty: 1, variantLabels: ['8 inch'] }],
      catalogue,
    );
    expect(lines[0]!.productId).toBe('p1');
    expect(lines[0]!.nameResolved).toBe('Lemon drizzle cake');
  });

  it('flags a product the catalogue does not have, with no price', () => {
    // "gluten free carrot cake" must not be silently dropped, and must not be
    // priced at zero and sent to a buyer.
    const { lines, ambiguities, subtotalMinor } = matchLineItems(
      [{ nameRaw: 'gluten free carrot cake', qty: 1, variantLabels: [] }],
      catalogue,
    );
    expect(lines[0]!.productId).toBeNull();
    expect(lines[0]!.matchMethod).toBe('unmatched');
    expect(lines[0]!.unitPriceMinor).toBe(0);
    expect(subtotalMinor).toBe(0);
    expect(ambiguities[0]!.kind).toBe('unknown_product');
    expect(ambiguities[0]!.blocking).toBe(true);
  });

  it('asks which size when the product has a choice and the buyer did not say', () => {
    const { lines, ambiguities } = matchLineItems(
      [{ nameRaw: 'a lemon drizzle cake', qty: 1, variantLabels: [] }],
      catalogue,
    );
    expect(lines[0]!.productId).toBe('p1');
    expect(ambiguities[0]!.kind).toBe('missing');
    expect(ambiguities[0]!.blocking).toBe(true);
    expect(ambiguities[0]!.options).toEqual(['8 inch', '10 inch']);
    expect(ambiguities[0]!.field).toBe('lineItems[0].variantIds');
  });

  it('does not ask when the product has only one variant', () => {
    const single: StoredProduct = { ...lemon, variants: [lemon.variants[0]!] };
    const { lines, ambiguities } = matchLineItems(
      [{ nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: [] }],
      [single],
    );
    expect(lines[0]!.unitPriceMinor).toBe(3200);
    expect(ambiguities).toEqual([]);
  });

  it('matches a variant label loosely', () => {
    const { lines } = matchLineItems(
      [{ nameRaw: 'brownies', qty: 1, variantLabels: ['box of 6'] }],
      catalogue,
    );
    expect(lines[0]!.variantIds).toEqual(['box-of-6']);
  });

  it('ignores an inactive product', () => {
    const { lines, ambiguities } = matchLineItems(
      [{ nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: ['8 inch'] }],
      [{ ...lemon, active: false }],
    );
    expect(lines[0]!.matchMethod).toBe('unmatched');
    expect(ambiguities[0]!.kind).toBe('unknown_product');
  });

  it('ignores an inactive variant when offering options', () => {
    const withDead: StoredProduct = {
      ...lemon,
      variants: [lemon.variants[0]!, { ...lemon.variants[1]!, active: false }],
    };
    const { lines, ambiguities } = matchLineItems(
      [{ nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: [] }],
      [withDead],
    );
    expect(lines[0]!.unitPriceMinor).toBe(3200);
    expect(ambiguities).toEqual([]);
  });

  it('gives every line a stable id, so the app can address one', () => {
    const { lines } = matchLineItems(
      [
        { nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: ['8 inch'] },
        { nameRaw: 'brownie box', qty: 1, variantLabels: ['Box of 6'] },
      ],
      catalogue,
    );
    expect(new Set(lines.map((l) => l.id)).size).toBe(2);
  });

  it('returns a zero subtotal for no items rather than throwing', () => {
    expect(matchLineItems([], catalogue).subtotalMinor).toBe(0);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd api && npx vitest run test/match-catalogue.test.ts
```

Expected: FAIL — cannot resolve `../src/domain/match_catalogue.js`.

- [ ] **Step 3: Write `api/src/domain/match_catalogue.ts`**

```ts
import type { Ambiguity, DmOrder } from '../ai/schemas.js';
import { applyDelta, multiplyMinor, sumMinor } from './money.js';

export type StoredVariant = {
  id: string;
  axis: string;
  label: string;
  priceDeltaMinor: number;
  active: boolean;
};

export type StoredProduct = {
  id: string;
  name: string;
  basePriceMinor: number;
  depositMinor: number | null;
  variants: StoredVariant[];
  active: boolean;
};

export type MatchedLine = {
  id: string;
  productId: string | null;
  variantIds: string[];
  nameRaw: string;
  nameResolved: string | null;
  qty: number;
  unitPriceMinor: number;
  lineTotalMinor: number;
  matchConfidence: number;
  matchMethod: 'exact' | 'fuzzy' | 'unmatched';
};

export function normalise(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/** Share of the catalogue name's words that appear in what the buyer wrote. */
function overlap(buyerWords: Set<string>, candidate: string): number {
  const words = normalise(candidate).split(' ').filter(Boolean);
  if (words.length === 0) return 0;
  const hits = words.filter((w) => buyerWords.has(w)).length;
  return hits / words.length;
}

const MATCH_THRESHOLD = 0.6;

function findProduct(
  nameRaw: string,
  products: StoredProduct[],
): { product: StoredProduct; method: 'exact' | 'fuzzy'; confidence: number } | null {
  const live = products.filter((p) => p.active);
  const normalised = normalise(nameRaw);

  const exact = live.find((p) => normalise(p.name) === normalised);
  if (exact) return { product: exact, method: 'exact', confidence: 1 };

  const buyerWords = new Set(normalised.split(' ').filter(Boolean));
  let best: { product: StoredProduct; confidence: number } | null = null;
  for (const product of live) {
    const score = overlap(buyerWords, product.name);
    if (score >= MATCH_THRESHOLD && (!best || score > best.confidence)) {
      best = { product, confidence: score };
    }
  }
  return best ? { product: best.product, method: 'fuzzy', confidence: best.confidence } : null;
}

function findVariants(labels: string[], product: StoredProduct): StoredVariant[] {
  const live = product.variants.filter((v) => v.active);
  const found: StoredVariant[] = [];
  for (const label of labels) {
    const want = normalise(label);
    const hit =
      live.find((v) => normalise(v.label) === want) ??
      live.find((v) => normalise(v.label).includes(want) || want.includes(normalise(v.label)));
    if (hit && !found.some((f) => f.id === hit.id)) found.push(hit);
  }
  return found;
}

/**
 * Resolves what the model read into real products, variants and prices.
 *
 * Every number here comes from the stored catalogue and money.ts. The model
 * contributes names and quantities only — it is never asked for a price, and
 * anything it could not be matched to becomes a blocking ambiguity rather than
 * a silent zero.
 */
export function matchLineItems(
  items: DmOrder['lineItems'],
  products: StoredProduct[],
): { lines: MatchedLine[]; ambiguities: Ambiguity[]; subtotalMinor: number } {
  const lines: MatchedLine[] = [];
  const ambiguities: Ambiguity[] = [];

  items.forEach((item, index) => {
    const id = `li-${index + 1}`;
    const match = findProduct(item.nameRaw, products);

    if (!match) {
      lines.push({
        id, productId: null, variantIds: [], nameRaw: item.nameRaw,
        nameResolved: null, qty: item.qty, unitPriceMinor: 0, lineTotalMinor: 0,
        matchConfidence: 0, matchMethod: 'unmatched',
      });
      ambiguities.push({
        field: `lineItems[${index}].productId`,
        kind: 'unknown_product',
        question: `"${item.nameRaw}" is not in your catalogue. Which product is it?`,
        options: products.filter((p) => p.active).map((p) => p.name),
        blocking: true,
      });
      return;
    }

    const { product, method, confidence } = match;
    const chosen = findVariants(item.variantLabels, product);
    const liveVariants = product.variants.filter((v) => v.active);

    if (chosen.length === 0 && liveVariants.length > 1) {
      // The buyer did not say which, and it genuinely changes the price.
      ambiguities.push({
        field: `lineItems[${index}].variantIds`,
        kind: 'missing',
        question: `Which ${liveVariants[0]!.axis} did they want for the ${product.name}?`,
        options: liveVariants.map((v) => v.label),
        blocking: true,
      });
    }

    const effective = chosen.length > 0 ? chosen : liveVariants.length === 1 ? liveVariants : [];
    const unitPriceMinor = effective.reduce(
      (price, v) => applyDelta(price, v.priceDeltaMinor),
      product.basePriceMinor,
    );

    lines.push({
      id,
      productId: product.id,
      variantIds: effective.map((v) => v.id),
      nameRaw: item.nameRaw,
      nameResolved: product.name,
      qty: item.qty,
      unitPriceMinor,
      lineTotalMinor: multiplyMinor(unitPriceMinor, item.qty),
      matchConfidence: confidence,
      matchMethod: method,
    });
  });

  return {
    lines,
    ambiguities,
    subtotalMinor: sumMinor(lines.map((l) => l.lineTotalMinor)),
  };
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
cd api && npx vitest run test/match-catalogue.test.ts
```

Expected: PASS, 12 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/bstar/Documents/development/apps/flutter/sorted
git add api/src/domain/match_catalogue.ts api/test/match-catalogue.test.ts
git commit -m "feat(api): match DM line items to the catalogue

Every price here comes from the stored catalogue and money.ts; the
model contributes names and quantities only. A product the catalogue
does not have becomes a blocking unknown_product ambiguity with no
price, rather than a dropped line or a GBP 0 one a buyer could order.

A product with more than one live variant and no stated choice asks the
seller which, because the answer changes what the buyer pays. A product
with one variant does not ask."
```

---

### Task 3: The order document

Covers Review Focus item 5 — the total the seller sees must be the amount PayPal charges.

**Files:**
- Create: `api/src/domain/orders.ts`
- Test: `api/test/orders-domain.test.ts`

**Interfaces:**
- Consumes: `MatchedLine`, `StoredProduct` from `src/domain/match_catalogue.ts`; `sumMinor`, `assertMinor` from `src/domain/money.ts`; `DmOrder`, `Ambiguity` from `src/ai/schemas.ts`.
- Produces, from `src/domain/orders.ts`:
  - `type OrderStatus = 'draft' | 'link_sent' | 'paid' | 'cancelled' | 'expired'`
  - `type OrderDoc` — the full Firestore shape
  - `computeAmounts(subtotalMinor: number, depositMinor: number | null): { subtotalMinor: number; depositMinor: number | null; amountDueMinor: number }`
  - `blockingAmbiguities(ambiguities: Ambiguity[]): Ambiguity[]`
  - `assertTransition(from: OrderStatus, to: OrderStatus): void`
  - `createDraftOrder(db: Firestore, sellerId: string, input: {...}): Promise<OrderDoc>`
  - `loadProducts(db: Firestore, sellerId: string): Promise<StoredProduct[]>`

- [ ] **Step 1: Write the failing test**

Create `api/test/orders-domain.test.ts`:

```ts
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import {
  assertTransition,
  blockingAmbiguities,
  computeAmounts,
  createDraftOrder,
  loadProducts,
} from '../src/domain/orders.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

let db: Firestore;
beforeAll(() => {
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-orders-test' });
  db = getFirestore();
});
beforeEach(async () => {
  const s = await db.collection('sellers').listDocuments();
  await Promise.all(s.map((d) => db.recursiveDelete(d)));
});

describe('computeAmounts', () => {
  it('charges the subtotal when there is no deposit', () => {
    expect(computeAmounts(5600, null)).toEqual({
      subtotalMinor: 5600, depositMinor: null, amountDueMinor: 5600,
    });
  });

  it('charges the deposit when one is set', () => {
    // The Draft screen shows the deposit; PayPal must charge exactly that.
    expect(computeAmounts(5500, 2000).amountDueMinor).toBe(2000);
  });

  it('refuses a deposit larger than the order', () => {
    expect(() => computeAmounts(1000, 2000)).toThrow(/deposit/i);
  });

  it('allows a deposit equal to the whole order', () => {
    expect(computeAmounts(2000, 2000).amountDueMinor).toBe(2000);
  });

  it('refuses a fractional amount', () => {
    expect(() => computeAmounts(10.5, null)).toThrow();
  });
});

describe('blockingAmbiguities', () => {
  it('returns only the unresolved blocking ones', () => {
    const out = blockingAmbiguities([
      { field: 'a', kind: 'missing', question: 'q', options: [], blocking: true },
      { field: 'b', kind: 'unclear', question: 'q', options: [], blocking: false },
    ]);
    expect(out).toHaveLength(1);
    expect(out[0]!.field).toBe('a');
  });
});

describe('assertTransition', () => {
  it('allows draft to link_sent', () => {
    expect(() => assertTransition('draft', 'link_sent')).not.toThrow();
  });

  it('refuses link_sent back to draft', () => {
    expect(() => assertTransition('link_sent', 'draft')).toThrow(/ORDER_STATE_INVALID|cannot/i);
  });

  it('refuses paid to anything else', () => {
    expect(() => assertTransition('paid', 'cancelled')).toThrow();
  });

  it('allows draft to cancelled', () => {
    expect(() => assertTransition('draft', 'cancelled')).not.toThrow();
  });
});

describe('loadProducts', () => {
  it('returns only active products', async () => {
    const col = db.collection('sellers/s1/products');
    await col.doc('a').set({ id: 'a', name: 'Live', basePriceMinor: 100, depositMinor: null, variants: [], active: true });
    await col.doc('b').set({ id: 'b', name: 'Dead', basePriceMinor: 100, depositMinor: null, variants: [], active: false });

    const products = await loadProducts(db, 's1');
    expect(products.map((p) => p.name)).toEqual(['Live']);
  });
});

describe('createDraftOrder', () => {
  const base = {
    buyerName: 'Jess M', buyerHandle: 'jess.mcr', buyerEmail: null,
    channel: 'instagram' as const,
    lines: [
      { id: 'li-1', productId: 'p1', variantIds: ['10-inch'], nameRaw: 'lemon drizzle', nameResolved: 'Lemon drizzle cake', qty: 1, unitPriceMinor: 4200, lineTotalMinor: 4200, matchConfidence: 1, matchMethod: 'exact' as const },
      { id: 'li-2', productId: 'p2', variantIds: ['box-of-6'], nameRaw: 'brownies', nameResolved: 'Brownie box', qty: 1, unitPriceMinor: 1400, lineTotalMinor: 1400, matchConfidence: 1, matchMethod: 'exact' as const },
    ],
    ambiguities: [],
    fulfilment: { mode: 'collection' as const, date: '2026-10-10', notes: null },
    depositMinor: null,
    sourceKind: 'screenshot' as const,
    extractionModel: 'gpt-5.5',
  };

  it('writes a draft with the computed total', async () => {
    const order = await createDraftOrder(db, 's1', base);
    expect(order.status).toBe('draft');
    expect(order.subtotalMinor).toBe(5600);
    expect(order.amountDueMinor).toBe(5600);
    expect(order.currency).toBe('GBP');

    const stored = await db.doc(`sellers/s1/orders/${order.id}`).get();
    expect(stored.exists).toBe(true);
    expect(stored.data()!.subtotalMinor).toBe(5600);
  });

  it('sets an expiry seven days out', async () => {
    const order = await createDraftOrder(db, 's1', base);
    expect(order.expiresAt).not.toBeNull();
  });

  it('stores a deposit as the amount due', async () => {
    const order = await createDraftOrder(db, 's1', { ...base, depositMinor: 2000 });
    expect(order.subtotalMinor).toBe(5600);
    expect(order.amountDueMinor).toBe(2000);
  });

  it('keeps ambiguities so the app can ask about them', async () => {
    const order = await createDraftOrder(db, 's1', {
      ...base,
      ambiguities: [{ field: 'lineItems[0].variantIds', kind: 'missing', question: 'Which size?', options: ['8 inch'], blocking: true }],
    });
    expect(order.ambiguities).toHaveLength(1);
  });

  it('has no PayPal fields until it is confirmed', async () => {
    const order = await createDraftOrder(db, 's1', base);
    expect(order.paypalOrderId).toBeNull();
    expect(order.approvalUrl).toBeNull();
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd api && npx vitest run test/orders-domain.test.ts
```

Expected: FAIL — cannot resolve `../src/domain/orders.js`.

- [ ] **Step 3: Write `api/src/domain/orders.ts`**

```ts
import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import type { Ambiguity } from '../ai/schemas.js';
import { ApiError } from '../lib/errors.js';
import { assertMinor, sumMinor } from './money.js';
import type { MatchedLine, StoredProduct } from './match_catalogue.js';

export type OrderStatus = 'draft' | 'link_sent' | 'paid' | 'cancelled' | 'expired';

export type OrderDoc = {
  id: string;
  status: OrderStatus;
  buyerName: string | null;
  buyerHandle: string | null;
  buyerEmail: string | null;
  channel: string;
  lineItems: MatchedLine[];
  subtotalMinor: number;
  depositMinor: number | null;
  amountDueMinor: number;
  currency: 'GBP';
  fulfilment: { mode: string; date: string | null; notes: string | null };
  ambiguities: Ambiguity[];
  paypalOrderId: string | null;
  approvalUrl: string | null;
  paypalCaptureId: string | null;
  paypalInvoiceId: string | null;
  draftedReply: string | null;
  nudge: { count: number; lastSentAt: Timestamp | null; lastText: string | null; channel: string | null; snoozedUntil: Timestamp | null };
  sourceKind: 'screenshot' | 'text';
  extractionModel: string;
  expiresAt: Timestamp | null;
};

const ORDER_LIFETIME_DAYS = 7;

/**
 * The amount PayPal will charge.
 *
 * Whatever the Draft screen shows must be exactly what the buyer pays, so this
 * is the single place the two are reconciled: a deposit replaces the subtotal
 * as the amount due, and a deposit larger than the order is a mistake worth
 * refusing rather than quietly charging more than the goods cost.
 */
export function computeAmounts(
  subtotalMinor: number,
  depositMinor: number | null,
): { subtotalMinor: number; depositMinor: number | null; amountDueMinor: number } {
  assertMinor(subtotalMinor);
  if (depositMinor === null) {
    return { subtotalMinor, depositMinor: null, amountDueMinor: subtotalMinor };
  }
  assertMinor(depositMinor);
  if (depositMinor > subtotalMinor) {
    throw new ApiError(
      400,
      'VALIDATION_FAILED',
      'The deposit cannot be more than the order total.',
    );
  }
  return { subtotalMinor, depositMinor, amountDueMinor: depositMinor };
}

export function blockingAmbiguities(ambiguities: Ambiguity[]): Ambiguity[] {
  return ambiguities.filter((a) => a.blocking && !(a as { resolved?: boolean }).resolved);
}

const ALLOWED: Record<OrderStatus, OrderStatus[]> = {
  draft: ['link_sent', 'cancelled'],
  link_sent: ['paid', 'cancelled', 'expired'],
  paid: [],
  cancelled: [],
  expired: [],
};

export function assertTransition(from: OrderStatus, to: OrderStatus): void {
  if (!ALLOWED[from].includes(to)) {
    throw new ApiError(
      409,
      'ORDER_STATE_INVALID',
      `An order that is ${from} cannot become ${to}.`,
    );
  }
}

export async function loadProducts(
  db: Firestore,
  sellerId: string,
): Promise<StoredProduct[]> {
  const snap = await db
    .collection(`sellers/${sellerId}/products`)
    .where('active', '==', true)
    .get();
  return snap.docs.map((d) => {
    const data = d.data();
    return {
      id: d.id,
      name: data.name as string,
      basePriceMinor: data.basePriceMinor as number,
      depositMinor: (data.depositMinor ?? null) as number | null,
      variants: (data.variants ?? []) as StoredProduct['variants'],
      active: true,
    };
  });
}

export async function createDraftOrder(
  db: Firestore,
  sellerId: string,
  input: {
    buyerName: string | null;
    buyerHandle: string | null;
    buyerEmail: string | null;
    channel: string;
    lines: MatchedLine[];
    ambiguities: Ambiguity[];
    fulfilment: { mode: string; date: string | null; notes: string | null };
    depositMinor: number | null;
    sourceKind: 'screenshot' | 'text';
    extractionModel: string;
  },
): Promise<OrderDoc> {
  const subtotal = sumMinor(input.lines.map((l) => l.lineTotalMinor));
  const amounts = computeAmounts(subtotal, input.depositMinor);

  const ref = db.collection(`sellers/${sellerId}/orders`).doc();
  const expiresAt = Timestamp.fromMillis(
    Date.now() + ORDER_LIFETIME_DAYS * 24 * 60 * 60 * 1000,
  );

  const order: OrderDoc = {
    id: ref.id,
    status: 'draft',
    buyerName: input.buyerName,
    buyerHandle: input.buyerHandle,
    buyerEmail: input.buyerEmail,
    channel: input.channel,
    lineItems: input.lines,
    ...amounts,
    currency: 'GBP',
    fulfilment: input.fulfilment,
    ambiguities: input.ambiguities,
    paypalOrderId: null,
    approvalUrl: null,
    paypalCaptureId: null,
    paypalInvoiceId: null,
    draftedReply: null,
    nudge: { count: 0, lastSentAt: null, lastText: null, channel: null, snoozedUntil: null },
    sourceKind: input.sourceKind,
    extractionModel: input.extractionModel,
    expiresAt,
  };

  await ref.set({
    ...order,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    linkSentAt: null,
    paidAt: null,
  });

  return order;
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
cd api && npx vitest run test/orders-domain.test.ts
```

Expected: PASS, 15 tests. The emulator must be running.

- [ ] **Step 5: Commit**

```bash
cd /Users/bstar/Documents/development/apps/flutter/sorted
git add api/src/domain/orders.ts api/test/orders-domain.test.ts
git commit -m "feat(api): the order document, totals and state transitions

computeAmounts is the single place the seller's total and PayPal's
charge are reconciled: a deposit replaces the subtotal as the amount
due, and a deposit larger than the order is refused rather than
quietly charging more than the goods cost.

assertTransition makes paid terminal and stops link_sent sliding back
to draft, so an order with a live checkout link cannot be edited
underneath the buyer."
```

---

### Task 4: The draft and resolve routes

**Files:**
- Create: `api/src/routes/orders.ts`
- Modify: `api/src/app.ts` (mount the router)
- Test: `api/test/orders-route.test.ts`

**Interfaces:**
- Consumes: `parseDm`, `CatalogueBrief` from `src/ai/parse_dm.ts`; `matchLineItems` from `src/domain/match_catalogue.ts`; `createDraftOrder`, `loadProducts`, `computeAmounts`, `assertTransition` from `src/domain/orders.ts`; `requireSeller`, `TokenVerifier`; `ChatTransport`; `ApiError`.
- Produces: `ordersRouter(deps: { db: Firestore; verify: TokenVerifier; transport: ChatTransport; model: string }): Router`, mounted at `/v1`.

- [ ] **Step 1: Write the failing test**

Create `api/test/orders-route.test.ts`:

```ts
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';
import type { ChatTransport } from '../src/ai/client.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-orders-route-test', INTERNAL_TOKEN: 't',
});

let db: Firestore;
beforeAll(() => {
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-orders-route-test' });
  db = getFirestore();
});

const jess = {
  buyerName: 'Jess M', buyerHandle: 'jess.mcr', buyerEmail: null, channel: 'instagram',
  lineItems: [
    { nameRaw: 'lemon drizzle cake 10 inch', qty: 1, variantLabels: ['10 inch'] },
    { nameRaw: 'brownie box of 6', qty: 1, variantLabels: ['Box of 6'] },
  ],
  fulfilment: { mode: 'collection', date: '2026-10-10', notes: null },
  depositRequestedMinor: null, ambiguities: [], overallConfidence: 0.95,
};

function appWith(payload: unknown) {
  const transport: ChatTransport = async () => ({ content: JSON.stringify(payload) });
  return createApp({
    env, db, transport,
    verify: async (t: string) => {
      if (t === 'good') return { uid: 'seller-a' };
      throw new Error('no');
    },
  });
}

beforeEach(async () => {
  const sellers = await db.collection('sellers').listDocuments();
  await Promise.all(sellers.map((s) => db.recursiveDelete(s)));

  const col = db.collection('sellers/seller-a/products');
  await col.doc('p1').set({
    id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200, depositMinor: null, active: true,
    variants: [
      { id: '8-inch', axis: 'size', label: '8 inch', priceDeltaMinor: 0, active: true },
      { id: '10-inch', axis: 'size', label: '10 inch', priceDeltaMinor: 1000, active: true },
    ],
  });
  await col.doc('p2').set({
    id: 'p2', name: 'Brownie box', basePriceMinor: 1400, depositMinor: null, active: true,
    variants: [{ id: 'box-of-6', axis: 'size', label: 'Box of 6', priceDeltaMinor: 0, active: true }],
  });
});

const png = Buffer.from('89504e470d0a1a0a', 'hex');

describe('POST /v1/orders/draft', () => {
  it('turns a screenshot into a priced draft', async () => {
    const res = await request(appWith(jess))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .attach('image', png, { filename: 'dm.png', contentType: 'image/png' });

    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('draft');
    expect(res.body.order.subtotalMinor).toBe(5600);
    expect(res.body.order.buyerName).toBe('Jess M');
    expect(res.body.order.sourceKind).toBe('screenshot');
  });

  it('accepts pasted text, which is the web path', async () => {
    const res = await request(appWith(jess))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .field('text', 'can I get a 10 inch lemon drizzle and a box of 6 brownies');

    expect(res.status).toBe(200);
    expect(res.body.order.sourceKind).toBe('text');
    expect(res.body.order.subtotalMinor).toBe(5600);
  });

  it('400s with neither image nor text', async () => {
    const res = await request(appWith(jess))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
  });

  it('401s without a token', async () => {
    const res = await request(appWith(jess))
      .post('/v1/orders/draft')
      .field('text', 'hello');
    expect(res.status).toBe(401);
  });

  it('writes no order when the conversation contains none', async () => {
    const empty = { ...jess, lineItems: [], buyerName: null };
    const res = await request(appWith(empty))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .field('text', 'a photo of a cat');

    expect(res.status).toBe(200);
    expect(res.body.order).toBeNull();
    expect(res.body.reason).toMatch(/no order/i);
    const orders = await db.collection('sellers/seller-a/orders').get();
    expect(orders.size).toBe(0);
  });

  it('carries an unknown product through as a blocking ambiguity', async () => {
    const odd = {
      ...jess,
      lineItems: [{ nameRaw: 'gluten free carrot cake', qty: 1, variantLabels: [] }],
    };
    const res = await request(appWith(odd))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .field('text', 'carrot cake please');

    expect(res.status).toBe(200);
    expect(res.body.order.ambiguities[0].kind).toBe('unknown_product');
    expect(res.body.order.subtotalMinor).toBe(0);
  });
});

describe('POST /v1/orders/:orderId/resolve', () => {
  async function draft() {
    const res = await request(appWith(jess))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .field('text', 'order please');
    return res.body.order.id as string;
  }

  it('sets a variant and reprices the line', async () => {
    const id = await draft();
    const res = await request(appWith(jess))
      .post(`/v1/orders/${id}/resolve`)
      .set('Authorization', 'Bearer good')
      .send({ lineItems: [{ id: 'li-1', variantIds: ['8-inch'] }] });

    expect(res.status).toBe(200);
    const line = res.body.order.lineItems.find((l: { id: string }) => l.id === 'li-1');
    expect(line.unitPriceMinor).toBe(3200);
    expect(res.body.order.subtotalMinor).toBe(4600);
  });

  it('changes a quantity and reprices', async () => {
    const id = await draft();
    const res = await request(appWith(jess))
      .post(`/v1/orders/${id}/resolve`)
      .set('Authorization', 'Bearer good')
      .send({ lineItems: [{ id: 'li-2', qty: 3 }] });

    expect(res.body.order.subtotalMinor).toBe(4200 + 4200);
  });

  it('sets a deposit as the amount due', async () => {
    const id = await draft();
    const res = await request(appWith(jess))
      .post(`/v1/orders/${id}/resolve`)
      .set('Authorization', 'Bearer good')
      .send({ depositMinor: 2000 });

    expect(res.body.order.subtotalMinor).toBe(5600);
    expect(res.body.order.amountDueMinor).toBe(2000);
  });

  it('400s on a deposit bigger than the order', async () => {
    const id = await draft();
    const res = await request(appWith(jess))
      .post(`/v1/orders/${id}/resolve`)
      .set('Authorization', 'Bearer good')
      .send({ depositMinor: 999999 });
    expect(res.status).toBe(400);
  });

  it('clears the ambiguity once the variant is chosen', async () => {
    const vague = {
      ...jess,
      lineItems: [{ nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: [] }],
    };
    const created = await request(appWith(vague))
      .post('/v1/orders/draft')
      .set('Authorization', 'Bearer good')
      .field('text', 'a lemon drizzle');
    expect(created.body.order.ambiguities).toHaveLength(1);

    const res = await request(appWith(vague))
      .post(`/v1/orders/${created.body.order.id}/resolve`)
      .set('Authorization', 'Bearer good')
      .send({ lineItems: [{ id: 'li-1', variantIds: ['10-inch'] }] });

    expect(res.body.order.ambiguities).toHaveLength(0);
    expect(res.body.order.subtotalMinor).toBe(4200);
  });

  it('404s for an order that does not exist', async () => {
    const res = await request(appWith(jess))
      .post('/v1/orders/nope/resolve')
      .set('Authorization', 'Bearer good')
      .send({ depositMinor: null });
    expect(res.status).toBe(404);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd api && npx vitest run test/orders-route.test.ts
```

Expected: FAIL — the routes do not exist.

- [ ] **Step 3: Write `api/src/routes/orders.ts`**

```ts
import { Router } from 'express';
import multer, { MulterError } from 'multer';
import { z } from 'zod';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { ApiError } from '../lib/errors.js';
import { requireSeller, type TokenVerifier } from '../lib/auth.js';
import type { ChatTransport } from '../ai/client.js';
import { parseDm, type CatalogueBrief } from '../ai/parse_dm.js';
import { matchLineItems, type StoredProduct } from '../domain/match_catalogue.js';
import {
  computeAmounts,
  createDraftOrder,
  loadProducts,
  type OrderDoc,
} from '../domain/orders.js';
import { sumMinor, multiplyMinor, applyDelta } from '../domain/money.js';

const MAX_BYTES = 8 * 1024 * 1024;
const ALLOWED = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/heic']);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_BYTES, files: 1 },
  fileFilter: (_req, file, cb) => {
    if (!ALLOWED.has(file.mimetype)) {
      cb(new ApiError(400, 'VALIDATION_FAILED', `${file.mimetype} is not an image Sorted can read.`));
      return;
    }
    cb(null, true);
  },
}).single('image');

const resolveBodySchema = z.object({
  buyerName: z.string().max(80).nullable().optional(),
  buyerHandle: z.string().max(80).nullable().optional(),
  buyerEmail: z.string().email().nullable().optional(),
  depositMinor: z.number().int().nonnegative().nullable().optional(),
  fulfilment: z
    .object({
      mode: z.enum(['collection', 'delivery', 'unknown']).optional(),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
      notes: z.string().max(300).nullable().optional(),
    })
    .optional(),
  lineItems: z
    .array(
      z.object({
        id: z.string().min(1),
        variantIds: z.array(z.string()).optional(),
        qty: z.number().int().min(1).max(999).optional(),
        productId: z.string().nullable().optional(),
      }),
    )
    .optional(),
});

function toBrief(products: StoredProduct[]): CatalogueBrief {
  return products.map((p) => ({
    id: p.id,
    name: p.name,
    basePriceMinor: p.basePriceMinor,
    variantLabels: p.variants.filter((v) => v.active).map((v) => v.label),
  }));
}

/** Recomputes a line's price from the catalogue after the seller edits it. */
function repriceLine(
  line: OrderDoc['lineItems'][number],
  products: StoredProduct[],
): OrderDoc['lineItems'][number] {
  const product = products.find((p) => p.id === line.productId);
  if (!product) return { ...line, unitPriceMinor: 0, lineTotalMinor: 0 };

  const chosen = product.variants.filter(
    (v) => v.active && line.variantIds.includes(v.id),
  );
  const unitPriceMinor = chosen.reduce(
    (price, v) => applyDelta(price, v.priceDeltaMinor),
    product.basePriceMinor,
  );
  return {
    ...line,
    nameResolved: product.name,
    unitPriceMinor,
    lineTotalMinor: multiplyMinor(unitPriceMinor, line.qty),
  };
}

/** An ambiguity is answered once the field it points at has a value. */
function stillOpen(
  ambiguity: OrderDoc['ambiguities'][number],
  lines: OrderDoc['lineItems'],
): boolean {
  const match = /^lineItems\[(\d+)\]\.(\w+)$/.exec(ambiguity.field);
  if (!match) return true;
  const line = lines[Number(match[1])];
  if (!line) return true;
  if (match[2] === 'variantIds') return line.variantIds.length === 0;
  if (match[2] === 'productId') return line.productId === null;
  return true;
}

export type OrdersDeps = {
  db: Firestore;
  verify: TokenVerifier;
  transport: ChatTransport;
  model: string;
};

export function ordersRouter(deps: OrdersDeps): Router {
  const router = Router();

  router.post(
    '/orders/draft',
    requireSeller(deps.verify),
    (req, res, next) => {
      upload(req, res, (err: unknown) => {
        if (err instanceof MulterError) {
          next(
            new ApiError(
              400,
              'VALIDATION_FAILED',
              err.code === 'LIMIT_FILE_SIZE'
                ? 'That screenshot must be 8MB or smaller.'
                : 'That upload could not be read.',
            ),
          );
          return;
        }
        if (err) { next(err); return; }
        next();
      });
    },
    async (req, res, next) => {
      const sellerId = req.sellerId!;
      const file = req.file;
      const text = typeof req.body?.text === 'string' ? req.body.text : undefined;

      try {
        const products = await loadProducts(deps.db, sellerId);
        const today = new Date().toISOString().slice(0, 10);

        const parsed = await parseDm(
          {
            ...(file ? { image: { buffer: file.buffer, mime: file.mimetype } } : {}),
            ...(text ? { text } : {}),
          },
          toBrief(products),
          today,
          deps.transport,
          deps.model,
        );

        if (parsed.lineItems.length === 0) {
          // Writing an order here would put a wrong checkout link one tap away.
          res.json({
            order: null,
            reason:
              'Sorted could not find an order in that. Try a screenshot of the conversation where the buyer says what they want.',
          });
          return;
        }

        const matched = matchLineItems(parsed.lineItems, products);

        const order = await createDraftOrder(deps.db, sellerId, {
          buyerName: parsed.buyerName,
          buyerHandle: parsed.buyerHandle,
          buyerEmail: parsed.buyerEmail,
          channel: parsed.channel,
          lines: matched.lines,
          ambiguities: [...parsed.ambiguities, ...matched.ambiguities],
          fulfilment: parsed.fulfilment,
          depositMinor: parsed.depositRequestedMinor,
          sourceKind: file ? 'screenshot' : 'text',
          extractionModel: deps.model,
        });

        res.json({ order });
      } catch (err) {
        next(err);
      }
    },
  );

  router.post('/orders/:orderId/resolve', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = resolveBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'That change is not valid.', parsed.error.format()));
      return;
    }

    const ref = deps.db.doc(`sellers/${req.sellerId}/orders/${req.params.orderId}`);
    try {
      const snap = await ref.get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such order.')); return; }

      const order = snap.data() as OrderDoc;
      if (order.status !== 'draft') {
        next(new ApiError(409, 'ORDER_STATE_INVALID', 'That order has already been sent.'));
        return;
      }

      const products = await loadProducts(deps.db, req.sellerId!);
      const patch = parsed.data;

      let lines = order.lineItems;
      if (patch.lineItems) {
        lines = lines.map((line) => {
          const edit = patch.lineItems!.find((e) => e.id === line.id);
          if (!edit) return line;
          return repriceLine(
            {
              ...line,
              ...(edit.variantIds ? { variantIds: edit.variantIds } : {}),
              ...(edit.qty ? { qty: edit.qty } : {}),
              ...(edit.productId !== undefined ? { productId: edit.productId } : {}),
            },
            products,
          );
        });
      }

      const subtotal = sumMinor(lines.map((l) => l.lineTotalMinor));
      const amounts = computeAmounts(
        subtotal,
        patch.depositMinor === undefined ? order.depositMinor : patch.depositMinor,
      );

      const ambiguities = order.ambiguities.filter((a) => stillOpen(a, lines));

      const updated = {
        ...order,
        lineItems: lines,
        ...amounts,
        ambiguities,
        ...(patch.buyerName !== undefined ? { buyerName: patch.buyerName } : {}),
        ...(patch.buyerHandle !== undefined ? { buyerHandle: patch.buyerHandle } : {}),
        ...(patch.buyerEmail !== undefined ? { buyerEmail: patch.buyerEmail } : {}),
        ...(patch.fulfilment ? { fulfilment: { ...order.fulfilment, ...patch.fulfilment } } : {}),
      };

      await ref.update({ ...updated, updatedAt: FieldValue.serverTimestamp() });
      res.json({ order: updated });
    } catch (err) {
      next(err);
    }
  });

  return router;
}
```

- [ ] **Step 4: Mount it in `api/src/app.ts`**

After the catalogue router:

```ts
import { ordersRouter } from './routes/orders.js';
```

```ts
  app.use(
    '/v1',
    ordersRouter({
      db: deps.db,
      verify: deps.verify,
      transport: deps.transport,
      model: deps.env.OPENAI_VISION_MODEL,
    }),
  );
```

- [ ] **Step 5: Run it to verify it passes**

```bash
cd api && npx vitest run test/orders-route.test.ts
```

Expected: PASS, 13 tests.

- [ ] **Step 6: Run the whole suite and typecheck**

```bash
cd api && npm test && npm run typecheck
```

Expected: everything green.

- [ ] **Step 7: Commit**

```bash
cd /Users/bstar/Documents/development/apps/flutter/sorted
git add api/src api/test
git commit -m "feat(api): draft an order from a DM, and let the seller fix it

POST /orders/draft takes a screenshot or pasted text, prices it from
the catalogue and stores a draft. A conversation with no order in it
returns order: null and writes nothing, because a wrong order one tap
from a checkout link is worse than no order.

POST /orders/:id/resolve reprices from the catalogue on every edit
rather than trusting numbers from the client, clears an ambiguity once
the field it points at has a value, and refuses to touch an order that
has already been sent."
```

---

### Task 5: The PayPal client and order creation

Every shape here was verified against a real sandbox order — see `docs/verified-facts.md`. Do not substitute remembered values.

**Files:**
- Create: `api/src/paypal/client.ts`, `api/src/paypal/orders.ts`
- Test: `api/test/paypal-client.test.ts`, `api/test/paypal-orders.test.ts`, `api/test/paypal-orders.live.test.ts`

**Interfaces:**
- Consumes: `Env` from `src/env.ts`; `toPayPalValue` from `src/domain/money.ts`; `OrderDoc` from `src/domain/orders.ts`; `ApiError`.
- Produces:
  - `type PayPalFetch = (path: string, init: { method: string; body?: unknown; requestId?: string }) => Promise<unknown>` from `src/paypal/client.ts`
  - `makePayPalClient(env: Env, now?: () => number): PayPalFetch`
  - `createPayPalOrder(order: OrderDoc, sellerId: string, call: PayPalFetch): Promise<{ paypalOrderId: string; approvalUrl: string }>` from `src/paypal/orders.ts`

- [ ] **Step 1: Write the failing client test**

Create `api/test/paypal-client.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from 'vitest';
import { makePayPalClient } from '../src/paypal/client.js';
import { loadEnv } from '../src/env.js';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'id', PAYPAL_CLIENT_SECRET: 'secret', PAYPAL_WEBHOOK_ID: 'wh',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'm',
  FIREBASE_PROJECT_ID: 'p', INTERNAL_TOKEN: 't',
});

afterEach(() => vi.unstubAllGlobals());

function stubFetch(handler: (url: string, init: RequestInit) => unknown) {
  const spy = vi.fn(async (url: string, init: RequestInit) => ({
    ok: true,
    status: 200,
    json: async () => handler(url, init),
    text: async () => '',
  }));
  vi.stubGlobal('fetch', spy);
  return spy;
}

describe('makePayPalClient', () => {
  it('gets a token then calls the endpoint with it', async () => {
    const spy = stubFetch((url) =>
      url.includes('/v1/oauth2/token')
        ? { access_token: 'tok-1', expires_in: 32400 }
        : { id: 'ORDER-1' },
    );

    const call = makePayPalClient(env);
    const out = await call('/v2/checkout/orders', { method: 'POST', body: { a: 1 } });

    expect(out).toEqual({ id: 'ORDER-1' });
    const second = spy.mock.calls[1]!;
    expect((second[1].headers as Record<string, string>).Authorization).toBe('Bearer tok-1');
  });

  it('reuses a cached token rather than fetching one per call', async () => {
    const spy = stubFetch((url) =>
      url.includes('/v1/oauth2/token')
        ? { access_token: 'tok-1', expires_in: 32400 }
        : { ok: true },
    );

    const call = makePayPalClient(env);
    await call('/v2/checkout/orders', { method: 'POST' });
    await call('/v2/checkout/orders', { method: 'POST' });

    const tokenCalls = spy.mock.calls.filter(([u]) => String(u).includes('/oauth2/token'));
    expect(tokenCalls).toHaveLength(1);
  });

  it('fetches a fresh token once the old one is near expiry', async () => {
    const spy = stubFetch((url) =>
      url.includes('/v1/oauth2/token')
        ? { access_token: 'tok', expires_in: 60 }
        : { ok: true },
    );

    let now = 1_000_000;
    const call = makePayPalClient(env, () => now);
    await call('/v2/checkout/orders', { method: 'POST' });
    now += 59_000; // inside the 60s safety margin
    await call('/v2/checkout/orders', { method: 'POST' });

    const tokenCalls = spy.mock.calls.filter(([u]) => String(u).includes('/oauth2/token'));
    expect(tokenCalls).toHaveLength(2);
  });

  it('sends PayPal-Request-Id when given one, for idempotency', async () => {
    const spy = stubFetch((url) =>
      url.includes('token') ? { access_token: 't', expires_in: 32400 } : { ok: true },
    );
    const call = makePayPalClient(env);
    await call('/v2/checkout/orders', { method: 'POST', requestId: 'capture-abc' });

    const headers = spy.mock.calls[1]![1].headers as Record<string, string>;
    expect(headers['PayPal-Request-Id']).toBe('capture-abc');
  });

  it('only ever talks to the sandbox host', async () => {
    const spy = stubFetch((url) =>
      url.includes('token') ? { access_token: 't', expires_in: 32400 } : { ok: true },
    );
    const call = makePayPalClient(env);
    await call('/v2/checkout/orders', { method: 'POST' });
    for (const [url] of spy.mock.calls) {
      expect(String(url)).toContain('api-m.sandbox.paypal.com');
    }
  });

  it('raises PAYPAL_UNAVAILABLE on a 5xx', async () => {
    vi.stubGlobal('fetch', vi.fn(async (url: string) => {
      if (String(url).includes('token')) {
        return { ok: true, status: 200, json: async () => ({ access_token: 't', expires_in: 32400 }), text: async () => '' };
      }
      return { ok: false, status: 503, json: async () => ({}), text: async () => 'upstream down' };
    }));

    const call = makePayPalClient(env);
    await expect(call('/v2/checkout/orders', { method: 'POST' })).rejects.toMatchObject({
      code: 'PAYPAL_UNAVAILABLE',
    });
  });

  it('raises PAYPAL_UNAVAILABLE on a 422, with PayPal\'s own detail', async () => {
    vi.stubGlobal('fetch', vi.fn(async (url: string) => {
      if (String(url).includes('token')) {
        return { ok: true, status: 200, json: async () => ({ access_token: 't', expires_in: 32400 }), text: async () => '' };
      }
      return {
        ok: false, status: 422,
        json: async () => ({ name: 'UNPROCESSABLE_ENTITY', details: [{ issue: 'AMOUNT_MISMATCH' }] }),
        text: async () => '',
      };
    }));

    const call = makePayPalClient(env);
    await expect(call('/v2/checkout/orders', { method: 'POST' })).rejects.toMatchObject({
      code: 'PAYPAL_UNAVAILABLE',
    });
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd api && npx vitest run test/paypal-client.test.ts
```

Expected: FAIL — cannot resolve `../src/paypal/client.js`.

- [ ] **Step 3: Write `api/src/paypal/client.ts`**

```ts
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
```

- [ ] **Step 4: Run it to verify it passes**

```bash
cd api && npx vitest run test/paypal-client.test.ts
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Write the failing order-creation test**

Create `api/test/paypal-orders.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { createPayPalOrder } from '../src/paypal/orders.js';
import type { PayPalFetch } from '../src/paypal/client.js';
import type { OrderDoc } from '../src/domain/orders.js';

const order = {
  id: 'order-xyz', status: 'draft',
  buyerName: 'Jess M', buyerHandle: 'jess.mcr', buyerEmail: null, channel: 'instagram',
  lineItems: [
    { id: 'li-1', productId: 'p1', variantIds: ['10-inch'], nameRaw: 'lemon drizzle', nameResolved: 'Lemon drizzle cake', qty: 1, unitPriceMinor: 4200, lineTotalMinor: 4200, matchConfidence: 1, matchMethod: 'exact' },
    { id: 'li-2', productId: 'p2', variantIds: ['box-of-6'], nameRaw: 'brownies', nameResolved: 'Brownie box', qty: 1, unitPriceMinor: 1400, lineTotalMinor: 1400, matchConfidence: 1, matchMethod: 'exact' },
  ],
  subtotalMinor: 5600, depositMinor: null, amountDueMinor: 5600, currency: 'GBP',
  fulfilment: { mode: 'collection', date: '2026-10-10', notes: null },
  ambiguities: [], paypalOrderId: null, approvalUrl: null, paypalCaptureId: null,
  paypalInvoiceId: null, draftedReply: null,
  nudge: { count: 0, lastSentAt: null, lastText: null, channel: null, snoozedUntil: null },
  sourceKind: 'screenshot', extractionModel: 'gpt-5.5', expiresAt: null,
} as unknown as OrderDoc;

const created = {
  id: 'PP-ORDER-1',
  status: 'PAYER_ACTION_REQUIRED',
  links: [
    { rel: 'self', method: 'GET', href: 'https://api.sandbox.paypal.com/v2/checkout/orders/PP-ORDER-1' },
    { rel: 'payer-action', method: 'GET', href: 'https://www.sandbox.paypal.com/checkoutnow?token=PP-ORDER-1' },
  ],
};

describe('createPayPalOrder', () => {
  it('returns the id and the approval link', async () => {
    const call: PayPalFetch = async () => created;
    const out = await createPayPalOrder(order, 'seller-a', call);
    expect(out.paypalOrderId).toBe('PP-ORDER-1');
    expect(out.approvalUrl).toBe('https://www.sandbox.paypal.com/checkoutnow?token=PP-ORDER-1');
  });

  it('reads the link from rel=payer-action, which is what PayPal sends', async () => {
    // Verified against a real sandbox order: with experience_context there is
    // no rel=approve, only payer-action.
    const call: PayPalFetch = async () => ({
      ...created,
      links: [{ rel: 'payer-action', method: 'GET', href: 'https://x/checkoutnow?token=T' }],
    });
    const out = await createPayPalOrder(order, 'seller-a', call);
    expect(out.approvalUrl).toBe('https://x/checkoutnow?token=T');
  });

  it('charges exactly the order amountDueMinor', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(order, 'seller-a', call);
    const body = call.mock.calls[0]![1].body as {
      purchase_units: { amount: { value: string; currency_code: string } }[];
    };
    expect(body.purchase_units[0]!.amount.value).toBe('56.00');
    expect(body.purchase_units[0]!.amount.currency_code).toBe('GBP');
  });

  it('charges the deposit, not the subtotal, when one is set', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(
      { ...order, depositMinor: 2000, amountDueMinor: 2000 },
      'seller-a',
      call,
    );
    const body = call.mock.calls[0]![1].body as { purchase_units: { amount: { value: string } }[] };
    expect(body.purchase_units[0]!.amount.value).toBe('20.00');
  });

  it('omits the item breakdown when a deposit means items would not add up', async () => {
    // PayPal rejects the order if item_total does not equal the sum of items,
    // and a GBP 20 deposit against GBP 56 of goods never will.
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(
      { ...order, depositMinor: 2000, amountDueMinor: 2000 },
      'seller-a',
      call,
    );
    const unit = (call.mock.calls[0]![1].body as { purchase_units: Record<string, unknown>[] })
      .purchase_units[0]!;
    expect(unit.items).toBeUndefined();
    expect((unit.amount as Record<string, unknown>).breakdown).toBeUndefined();
  });

  it('sends items whose total equals the amount when there is no deposit', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(order, 'seller-a', call);
    const unit = (call.mock.calls[0]![1].body as { purchase_units: Record<string, unknown>[] })
      .purchase_units[0]!;
    const items = unit.items as { unit_amount: { value: string }; quantity: string }[];
    const sum = items.reduce(
      (t, i) => t + Math.round(Number(i.unit_amount.value) * 100) * Number(i.quantity),
      0,
    );
    expect(sum).toBe(5600);
    const breakdown = (unit.amount as { breakdown: { item_total: { value: string } } }).breakdown;
    expect(breakdown.item_total.value).toBe('56.00');
  });

  it('carries sellerId:orderId in custom_id so webhooks need no lookup', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(order, 'seller-a', call);
    const unit = (call.mock.calls[0]![1].body as { purchase_units: { custom_id: string }[] })
      .purchase_units[0]!;
    expect(unit.custom_id).toBe('seller-a:order-xyz');
  });

  it('sends an idempotency key derived from the order', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(order, 'seller-a', call);
    expect(call.mock.calls[0]![1].requestId).toContain('order-xyz');
  });

  it('asks for GBP and a UK experience with no shipping', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await createPayPalOrder(order, 'seller-a', call);
    const body = JSON.stringify(call.mock.calls[0]![1].body);
    expect(body).toContain('en-GB');
    expect(body).toContain('NO_SHIPPING');
    expect(body).toContain('PAY_NOW');
  });

  it('throws when PayPal returns no approval link', async () => {
    const call: PayPalFetch = async () => ({ id: 'X', status: 'CREATED', links: [] });
    await expect(createPayPalOrder(order, 'seller-a', call)).rejects.toMatchObject({
      code: 'PAYPAL_UNAVAILABLE',
    });
  });

  it('refuses to create an order for nothing', async () => {
    const call = vi.fn<PayPalFetch>().mockResolvedValue(created);
    await expect(
      createPayPalOrder({ ...order, amountDueMinor: 0 }, 'seller-a', call),
    ).rejects.toThrow();
    expect(call).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 6: Run it to verify it fails**

```bash
cd api && npx vitest run test/paypal-orders.test.ts
```

Expected: FAIL — cannot resolve `../src/paypal/orders.js`.

- [ ] **Step 7: Write `api/src/paypal/orders.ts`**

```ts
import { ApiError } from '../lib/errors.js';
import { toPayPalValue } from '../domain/money.js';
import type { OrderDoc } from '../domain/orders.js';
import type { PayPalFetch } from './client.js';

type CreatedOrder = {
  id: string;
  status: string;
  links?: { rel: string; href: string; method: string }[];
};

/**
 * Creates the order the buyer will approve.
 *
 * Shapes verified against a real sandbox order (docs/verified-facts.md):
 * with payment_source.paypal.experience_context the response status is
 * PAYER_ACTION_REQUIRED and the approval link is rel="payer-action" — there
 * is no rel="approve".
 */
export async function createPayPalOrder(
  order: OrderDoc,
  sellerId: string,
  call: PayPalFetch,
): Promise<{ paypalOrderId: string; approvalUrl: string }> {
  if (order.amountDueMinor <= 0) {
    throw new ApiError(
      400,
      'VALIDATION_FAILED',
      'There is nothing to charge for on this order.',
    );
  }

  const value = toPayPalValue(order.amountDueMinor);
  const takingDeposit = order.depositMinor !== null;

  // PayPal rejects the order unless item_total equals the sum of items, and a
  // deposit never equals the goods. Send the itemised breakdown only when the
  // buyer is paying for the whole order.
  const items = order.lineItems.map((line) => ({
    name: (line.nameResolved ?? line.nameRaw).slice(0, 127),
    quantity: String(line.qty),
    unit_amount: { currency_code: 'GBP', value: toPayPalValue(line.unitPriceMinor) },
  }));

  const purchaseUnit: Record<string, unknown> = {
    reference_id: order.id,
    custom_id: `${sellerId}:${order.id}`,
    amount: takingDeposit
      ? { currency_code: 'GBP', value }
      : {
          currency_code: 'GBP',
          value,
          breakdown: { item_total: { currency_code: 'GBP', value } },
        },
    ...(takingDeposit ? {} : { items }),
    ...(takingDeposit
      ? { description: `Deposit for order ${order.id.slice(0, 8)}` }
      : {}),
  };

  const created = (await call('/v2/checkout/orders', {
    method: 'POST',
    requestId: `create-${order.id}`,
    body: {
      intent: 'CAPTURE',
      purchase_units: [purchaseUnit],
      payment_source: {
        paypal: {
          experience_context: {
            brand_name: 'Sorted',
            locale: 'en-GB',
            user_action: 'PAY_NOW',
            shipping_preference: 'NO_SHIPPING',
            return_url: 'https://sorted-api-a4zo.onrender.com/v1/paypal/return',
            cancel_url: 'https://sorted-api-a4zo.onrender.com/v1/paypal/cancel',
          },
        },
      },
    },
  })) as CreatedOrder;

  const approval = created.links?.find((l) => l.rel === 'payer-action')?.href;
  if (!created.id || !approval) {
    throw new ApiError(
      502,
      'PAYPAL_UNAVAILABLE',
      'PayPal created the order but returned no checkout link. Try again.',
      { status: created.status },
    );
  }

  return { paypalOrderId: created.id, approvalUrl: approval };
}
```

- [ ] **Step 8: Run it to verify it passes**

```bash
cd api && npx vitest run test/paypal-orders.test.ts
```

Expected: PASS, 11 tests.

- [ ] **Step 9: Write the live test**

Create `api/test/paypal-orders.live.test.ts`. The unit tests stub `fetch`, so nothing has checked that PayPal actually accepts this body.

```ts
import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { makePayPalClient } from '../src/paypal/client.js';
import { createPayPalOrder } from '../src/paypal/orders.js';
import { loadEnv } from '../src/env.js';
import type { OrderDoc } from '../src/domain/orders.js';

const envFile = existsSync('.env') ? readFileSync('.env', 'utf8') : '';
const id = envFile.match(/^PAYPAL_CLIENT_ID=(.+)$/m)?.[1]?.trim();
const secret = envFile.match(/^PAYPAL_CLIENT_SECRET=(.+)$/m)?.[1]?.trim();
const ready = Boolean(id) && Boolean(secret);

const order = {
  id: 'live-probe-order',
  lineItems: [
    { id: 'li-1', productId: 'p1', variantIds: [], nameRaw: 'x', nameResolved: 'Lemon drizzle cake (10 inch)', qty: 1, unitPriceMinor: 4200, lineTotalMinor: 4200, matchConfidence: 1, matchMethod: 'exact' },
    { id: 'li-2', productId: 'p2', variantIds: [], nameRaw: 'y', nameResolved: 'Brownie box (Box of 6)', qty: 1, unitPriceMinor: 1400, lineTotalMinor: 1400, matchConfidence: 1, matchMethod: 'exact' },
  ],
  subtotalMinor: 5600, depositMinor: null, amountDueMinor: 5600, currency: 'GBP',
} as unknown as OrderDoc;

describe.skipIf(!ready)('createPayPalOrder against the real sandbox', () => {
  const env = loadEnv({
    NODE_ENV: 'test',
    PAYPAL_CLIENT_ID: id!, PAYPAL_CLIENT_SECRET: secret!, PAYPAL_WEBHOOK_ID: 'x',
    OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'm',
    FIREBASE_PROJECT_ID: 'x', INTERNAL_TOKEN: 'x',
  });

  it('builds a body PayPal accepts, and returns a usable checkout link', async () => {
    const unique = { ...order, id: `live-probe-${Date.now()}` };
    const out = await createPayPalOrder(unique, 'seller-live', makePayPalClient(env));

    expect(out.paypalOrderId).toMatch(/^[A-Z0-9]+$/);
    expect(out.approvalUrl).toContain('checkoutnow?token=');
    expect(out.approvalUrl).toContain(out.paypalOrderId);
  }, 60_000);

  it('is accepted with a deposit, where the items would not add up', async () => {
    const deposit = {
      ...order,
      id: `live-probe-dep-${Date.now()}`,
      depositMinor: 2000,
      amountDueMinor: 2000,
    };
    const out = await createPayPalOrder(deposit, 'seller-live', makePayPalClient(env));
    expect(out.approvalUrl).toContain('checkoutnow?token=');
  }, 60_000);
});
```

- [ ] **Step 10: Run the live test**

```bash
cd api && npx vitest run test/paypal-orders.live.test.ts
```

Expected: PASS, 2 tests. A `422 AMOUNT_MISMATCH` means the item breakdown logic is wrong — read the `detail` in the thrown error rather than guessing.

- [ ] **Step 11: Commit**

```bash
cd /Users/bstar/Documents/development/apps/flutter/sorted
git add api/src/paypal api/test/paypal-client.test.ts api/test/paypal-orders.test.ts api/test/paypal-orders.live.test.ts
git commit -m "feat(api): create PayPal orders, with the verified request shape

Token caching with a 60s safety margin, PayPal-Request-Id for
idempotency, and PayPal's own issue code surfaced in the error so
AMOUNT_MISMATCH does not arrive as a bare 502.

The approval link is read from rel=payer-action, verified against a
real sandbox order: with experience_context there is no rel=approve.
The itemised breakdown is sent only when the buyer pays the whole
order, because item_total must equal the sum of items and a deposit
never will. Two live tests prove PayPal accepts both bodies."
```

---

### Task 6: Confirm the order and draft the reply

Covers Review Focus items 3, 4 and 5.

**Files:**
- Create: `api/src/ai/draft_reply.ts`
- Modify: `api/src/routes/orders.ts` (add `/confirm`, `/reply/regenerate`, `GET /orders`), `api/src/app.ts` (pass a `PayPalFetch`)
- Test: `api/test/draft-reply.test.ts`, `api/test/orders-confirm.test.ts`

**Interfaces:**
- Consumes: `createPayPalOrder`, `PayPalFetch`; `assertTransition`, `blockingAmbiguities`, `OrderDoc`; `generateStructured`; `replyDraftSchema`; `formatGbp` equivalent via `toPayPalValue`.
- Produces:
  - `REPLY_SYSTEM: string`, `REPLY_JSON_SCHEMA`, `type ReplyTone = 'friendly' | 'short' | 'formal'`
  - `draftReply(input: { order: OrderDoc; personaTone: string; approvalUrl: string; tone: ReplyTone }, transport: ChatTransport, model: string): Promise<string>` from `src/ai/draft_reply.ts`
  - `OrdersDeps` gains `paypal: PayPalFetch`

- [ ] **Step 1: Write the failing reply test**

Create `api/test/draft-reply.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { REPLY_SYSTEM, draftReply } from '../src/ai/draft_reply.js';
import type { ChatTransport } from '../src/ai/client.js';
import type { OrderDoc } from '../src/domain/orders.js';

const order = {
  id: 'o1', buyerName: 'Jess M',
  lineItems: [
    { nameResolved: 'Lemon drizzle cake', variantIds: ['10-inch'], qty: 1, unitPriceMinor: 4200, lineTotalMinor: 4200 },
    { nameResolved: 'Brownie box', variantIds: ['box-of-6'], qty: 1, unitPriceMinor: 1400, lineTotalMinor: 1400 },
  ],
  amountDueMinor: 5600, depositMinor: null,
  fulfilment: { mode: 'collection', date: '2026-10-10', notes: null },
} as unknown as OrderDoc;

const link = 'https://www.sandbox.paypal.com/checkoutnow?token=PP1';
const ok: ChatTransport = async () => ({
  content: JSON.stringify({ reply: `Hi Jess! That's sorted. Pay here: ${link}` }),
});

describe('draftReply', () => {
  it('returns the reply text', async () => {
    const out = await draftReply(
      { order, personaTone: 'hiya! x', approvalUrl: link, tone: 'friendly' },
      ok, 'm',
    );
    expect(out).toContain('Jess');
    expect(out).toContain(link);
  });

  it('puts the exact link in the prompt so the model cannot invent one', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply({ order, personaTone: '', approvalUrl: link, tone: 'friendly' }, transport, 'm');
    expect(JSON.stringify(transport.mock.calls[0]![0])).toContain(link);
  });

  it('passes the seller\'s own voice through', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply(
      { order, personaTone: 'hiya! let me know what you fancy x', approvalUrl: link, tone: 'friendly' },
      transport, 'm',
    );
    expect(JSON.stringify(transport.mock.calls[0]![0])).toContain('let me know what you fancy');
  });

  it('tells the model the total as formatted money, never raw pence', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply({ order, personaTone: '', approvalUrl: link, tone: 'friendly' }, transport, 'm');
    const body = JSON.stringify(transport.mock.calls[0]![0]);
    expect(body).toContain('56.00');
    expect(body).not.toContain('5600');
  });

  it('says it is a deposit when one is set', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply(
      { order: { ...order, depositMinor: 2000, amountDueMinor: 2000 }, personaTone: '', approvalUrl: link, tone: 'friendly' },
      transport, 'm',
    );
    expect(JSON.stringify(transport.mock.calls[0]![0]).toLowerCase()).toContain('deposit');
  });

  it('carries the tone through', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply({ order, personaTone: '', approvalUrl: link, tone: 'formal' }, transport, 'm');
    expect(JSON.stringify(transport.mock.calls[0]![0]).toLowerCase()).toContain('formal');
  });

  it('rejects a reply that dropped the link', async () => {
    // A reply without the checkout link is worse than none: the seller sends
    // it, the buyer cannot pay, and nobody notices until the chase.
    const noLink: ChatTransport = async () => ({
      content: JSON.stringify({ reply: 'Hi Jess, that is all sorted!' }),
    });
    await expect(
      draftReply({ order, personaTone: '', approvalUrl: link, tone: 'friendly' }, noLink, 'm'),
    ).rejects.toMatchObject({ code: 'AI_PARSE_FAILED' });
  });

  it('rejects a reply that altered the link', async () => {
    const wrong: ChatTransport = async () => ({
      content: JSON.stringify({ reply: 'pay: https://paypal.com/checkoutnow?token=SOMETHINGELSE' }),
    });
    await expect(
      draftReply({ order, personaTone: '', approvalUrl: link, tone: 'friendly' }, wrong, 'm'),
    ).rejects.toMatchObject({ code: 'AI_PARSE_FAILED' });
  });

  it('never sets temperature', async () => {
    const transport = vi.fn<ChatTransport>().mockResolvedValue({
      content: JSON.stringify({ reply: `pay: ${link}` }),
    });
    await draftReply({ order, personaTone: '', approvalUrl: link, tone: 'friendly' }, transport, 'm');
    expect(transport.mock.calls[0]![0]).not.toHaveProperty('temperature');
  });

  it('tells the model to use UK English and keep it short', () => {
    expect(REPLY_SYSTEM).toMatch(/UK English/i);
    expect(REPLY_SYSTEM).toMatch(/\b60 words\b/);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd api && npx vitest run test/draft-reply.test.ts
```

Expected: FAIL — cannot resolve `../src/ai/draft_reply.js`.

- [ ] **Step 3: Write `api/src/ai/draft_reply.ts`**

```ts
import { replyDraftSchema } from './schemas.js';
import { generateStructured, type ChatTransport } from './client.js';
import { ApiError } from '../lib/errors.js';
import { formatGbp } from '../domain/money.js';
import type { OrderDoc } from '../domain/orders.js';

export type ReplyTone = 'friendly' | 'short' | 'formal';

export const REPLY_SYSTEM = [
  'You write the message a UK small seller sends back to a buyer in a DM, confirming their order and giving them a payment link.',
  'Write as the seller, in their voice. A sample of how they write is given below; match it.',
  'UK English. Under 60 words. Warm, not corporate.',
  'Include the payment link exactly once, exactly as given, with no words inside the URL and nothing appended to it.',
  'Do not invent a link, shorten it, or wrap it in markdown.',
  'Use no emoji unless the seller\'s own sample uses them.',
  'Do not promise a date, a time or anything else that is not in the order details given.',
  'Do not restate the itemised prices; name what they ordered and the total.',
].join(' ');

export const REPLY_JSON_SCHEMA: Record<string, unknown> = {
  type: 'object',
  additionalProperties: false,
  required: ['reply'],
  properties: { reply: { type: 'string' } },
};

const TONE_GUIDANCE: Record<ReplyTone, string> = {
  friendly: 'Tone: friendly and chatty, the way they would talk to a regular.',
  short: 'Tone: short. Two sentences at most, no small talk.',
  formal: 'Tone: formal and polite, but still a person, not a company.',
};

export async function draftReply(
  input: {
    order: OrderDoc;
    personaTone: string;
    approvalUrl: string;
    tone: ReplyTone;
  },
  transport: ChatTransport,
  model: string,
): Promise<string> {
  const { order, approvalUrl, tone } = input;

  const items = order.lineItems
    .map((l) => `${l.qty} x ${l.nameResolved ?? l.nameRaw}`)
    .join(', ');

  const details = [
    `Buyer: ${order.buyerName ?? 'the buyer'}`,
    `They ordered: ${items}`,
    order.depositMinor !== null
      ? `They are paying a deposit of ${formatGbp(order.amountDueMinor)} now, with the rest due on collection.`
      : `Total to pay: ${formatGbp(order.amountDueMinor)}`,
    order.fulfilment.date
      ? `${order.fulfilment.mode === 'delivery' ? 'Delivery' : 'Collection'}: ${order.fulfilment.date}`
      : '',
    order.fulfilment.notes ? `Note: ${order.fulfilment.notes}` : '',
    `Payment link, to include verbatim: ${approvalUrl}`,
  ]
    .filter(Boolean)
    .join('\n');

  const system = [
    REPLY_SYSTEM,
    `\n\n${TONE_GUIDANCE[tone]}`,
    input.personaTone.trim()
      ? `\n\nHow the seller writes: "${input.personaTone.trim()}"`
      : '',
    `\n\nOrder details:\n${details}`,
  ].join('');

  const { reply } = await generateStructured(
    {
      schemaName: 'reply_draft',
      schema: replyDraftSchema,
      jsonSchema: REPLY_JSON_SCHEMA,
      system,
      text: 'Write the reply.',
      // No temperature: gpt-5.5 only accepts the default.
    },
    transport,
    model,
  );

  // A reply the seller pastes without the right link is worse than no reply:
  // the buyer cannot pay and nobody finds out until the chase.
  if (!reply.includes(approvalUrl)) {
    throw new ApiError(
      502,
      'AI_PARSE_FAILED',
      'Sorted could not write that reply correctly. The link is below — paste it into the chat yourself.',
    );
  }

  return reply;
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
cd api && npx vitest run test/draft-reply.test.ts
```

Expected: PASS, 10 tests.

- [ ] **Step 5: Write the failing confirm test**

Create `api/test/orders-confirm.test.ts`:

```ts
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/env.js';
import { ApiError } from '../src/lib/errors.js';
import type { ChatTransport } from '../src/ai/client.js';
import type { PayPalFetch } from '../src/paypal/client.js';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.METADATA_SERVER_DETECTION = 'none';

const env = loadEnv({
  NODE_ENV: 'test',
  PAYPAL_CLIENT_ID: 'x', PAYPAL_CLIENT_SECRET: 'x', PAYPAL_WEBHOOK_ID: 'x',
  OPENAI_API_KEY: 'x', OPENAI_VISION_MODEL: 'test-model',
  FIREBASE_PROJECT_ID: 'sorted-confirm-test', INTERNAL_TOKEN: 't',
});

let db: Firestore;
beforeAll(() => {
  if (getApps().length === 0) initializeApp({ projectId: 'sorted-confirm-test' });
  db = getFirestore();
});

const LINK = 'https://www.sandbox.paypal.com/checkoutnow?token=PP-1';

const parsed = {
  buyerName: 'Jess M', buyerHandle: 'jess.mcr', buyerEmail: null, channel: 'instagram',
  lineItems: [{ nameRaw: 'lemon drizzle cake 10 inch', qty: 1, variantLabels: ['10 inch'] }],
  fulfilment: { mode: 'collection', date: '2026-10-10', notes: null },
  depositRequestedMinor: null, ambiguities: [], overallConfidence: 0.95,
};

function transportFor(payload: unknown): ChatTransport {
  return async (body) => {
    const sent = JSON.stringify(body);
    // The reply call carries the link in its system prompt; the parse call does not.
    if (sent.includes('checkoutnow')) {
      return { content: JSON.stringify({ reply: `All sorted! Pay here: ${LINK}` }) };
    }
    return { content: JSON.stringify(payload) };
  };
}

const happyPayPal: PayPalFetch = async () => ({
  id: 'PP-1',
  status: 'PAYER_ACTION_REQUIRED',
  links: [{ rel: 'payer-action', method: 'GET', href: LINK }],
});

function appWith(payload: unknown, paypal: PayPalFetch = happyPayPal) {
  return createApp({
    env, db, paypal,
    transport: transportFor(payload),
    verify: async (t: string) => {
      if (t === 'good') return { uid: 'seller-a' };
      throw new Error('no');
    },
  });
}

beforeEach(async () => {
  const sellers = await db.collection('sellers').listDocuments();
  await Promise.all(sellers.map((s) => db.recursiveDelete(s)));
  await db.doc('sellers/seller-a').set({
    id: 'seller-a', displayName: "Ola's Bakehouse", personaTone: 'hiya! x',
    currency: 'GBP', timezone: 'Europe/London', demoSeeded: true,
  });
  await db.doc('sellers/seller-a/products/p1').set({
    id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200, depositMinor: null, active: true,
    variants: [
      { id: '8-inch', axis: 'size', label: '8 inch', priceDeltaMinor: 0, active: true },
      { id: '10-inch', axis: 'size', label: '10 inch', priceDeltaMinor: 1000, active: true },
    ],
  });
});

async function draft(app: ReturnType<typeof appWith>) {
  const res = await request(app)
    .post('/v1/orders/draft')
    .set('Authorization', 'Bearer good')
    .field('text', 'a 10 inch lemon drizzle please');
  return res.body.order.id as string;
}

describe('POST /v1/orders/:orderId/confirm', () => {
  it('creates the PayPal order and returns the link and reply', async () => {
    const app = appWith(parsed);
    const id = await draft(app);

    const res = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});

    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('link_sent');
    expect(res.body.order.paypalOrderId).toBe('PP-1');
    expect(res.body.order.approvalUrl).toBe(LINK);
    expect(res.body.order.draftedReply).toContain(LINK);
  });

  it('charges exactly what the order says is due', async () => {
    const paypal = vi.fn<PayPalFetch>().mockResolvedValue({
      id: 'PP-1', status: 'PAYER_ACTION_REQUIRED',
      links: [{ rel: 'payer-action', method: 'GET', href: LINK }],
    });
    const app = appWith(parsed, paypal);
    const id = await draft(app);
    await request(app).post(`/v1/orders/${id}/confirm`).set('Authorization', 'Bearer good').send({});

    const body = paypal.mock.calls[0]![1].body as {
      purchase_units: { amount: { value: string } }[];
    };
    // The draft is a 10 inch lemon drizzle: GBP 32 base + GBP 10 = GBP 42.
    expect(body.purchase_units[0]!.amount.value).toBe('42.00');
  });

  it('refuses while a blocking ambiguity is unanswered', async () => {
    // Otherwise a link goes out with a guessed size and a price the seller
    // never agreed to.
    const vague = {
      ...parsed,
      lineItems: [{ nameRaw: 'lemon drizzle cake', qty: 1, variantLabels: [] }],
    };
    const app = appWith(vague);
    const id = await draft(app);

    const res = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});

    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('ORDER_STATE_INVALID');
    const stored = await db.doc(`sellers/seller-a/orders/${id}`).get();
    expect(stored.data()!.status).toBe('draft');
  });

  it('leaves the order a draft when PayPal rejects it', async () => {
    const angry: PayPalFetch = async () => {
      throw new ApiError(502, 'PAYPAL_UNAVAILABLE', 'PayPal rejected that request (AMOUNT_MISMATCH). Nothing was charged.');
    };
    const app = appWith(parsed, angry);
    const id = await draft(app);

    const res = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});

    expect(res.status).toBe(502);
    expect(res.body.error.code).toBe('PAYPAL_UNAVAILABLE');

    const stored = await db.doc(`sellers/seller-a/orders/${id}`).get();
    expect(stored.data()!.status).toBe('draft');
    expect(stored.data()!.paypalOrderId).toBeNull();
    // The seller's work is still there to retry with.
    expect(stored.data()!.lineItems).toHaveLength(1);
  });

  it('refuses to confirm the same order twice', async () => {
    const app = appWith(parsed);
    const id = await draft(app);
    await request(app).post(`/v1/orders/${id}/confirm`).set('Authorization', 'Bearer good').send({});

    const second = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({});

    expect(second.status).toBe(409);
  });

  it('applies a deposit sent at confirm time', async () => {
    const paypal = vi.fn<PayPalFetch>().mockResolvedValue({
      id: 'PP-1', status: 'PAYER_ACTION_REQUIRED',
      links: [{ rel: 'payer-action', method: 'GET', href: LINK }],
    });
    const app = appWith(parsed, paypal);
    const id = await draft(app);

    const res = await request(app)
      .post(`/v1/orders/${id}/confirm`)
      .set('Authorization', 'Bearer good')
      .send({ depositMinor: 1000 });

    expect(res.body.order.amountDueMinor).toBe(1000);
    const body = paypal.mock.calls[0]![1].body as { purchase_units: { amount: { value: string } }[] };
    expect(body.purchase_units[0]!.amount.value).toBe('10.00');
  });

  it('404s for an order that does not exist', async () => {
    const res = await request(appWith(parsed))
      .post('/v1/orders/nope/confirm')
      .set('Authorization', 'Bearer good')
      .send({});
    expect(res.status).toBe(404);
  });

  it('401s without a token', async () => {
    const app = appWith(parsed);
    const id = await draft(app);
    const res = await request(app).post(`/v1/orders/${id}/confirm`).send({});
    expect(res.status).toBe(401);
  });
});

describe('POST /v1/orders/:orderId/reply/regenerate', () => {
  it('rewrites the reply in another tone', async () => {
    const app = appWith(parsed);
    const id = await draft(app);
    await request(app).post(`/v1/orders/${id}/confirm`).set('Authorization', 'Bearer good').send({});

    const res = await request(app)
      .post(`/v1/orders/${id}/reply/regenerate`)
      .set('Authorization', 'Bearer good')
      .send({ tone: 'formal' });

    expect(res.status).toBe(200);
    expect(res.body.draftedReply).toContain(LINK);
  });

  it('409s on an order with no link yet', async () => {
    const app = appWith(parsed);
    const id = await draft(app);
    const res = await request(app)
      .post(`/v1/orders/${id}/reply/regenerate`)
      .set('Authorization', 'Bearer good')
      .send({ tone: 'short' });
    expect(res.status).toBe(409);
  });
});

describe('GET /v1/orders', () => {
  it('lists the seller\'s orders, newest first', async () => {
    const app = appWith(parsed);
    await draft(app);
    await draft(app);

    const res = await request(app).get('/v1/orders').set('Authorization', 'Bearer good');
    expect(res.status).toBe(200);
    expect(res.body.orders).toHaveLength(2);
  });

  it('401s without a token', async () => {
    const res = await request(appWith(parsed)).get('/v1/orders');
    expect(res.status).toBe(401);
  });
});
```

- [ ] **Step 6: Run it to verify it fails**

```bash
cd api && npx vitest run test/orders-confirm.test.ts
```

Expected: FAIL — `createApp` does not accept `paypal`, and the routes do not exist.

- [ ] **Step 7: Add the routes to `api/src/routes/orders.ts`**

Add these imports:

```ts
import { createPayPalOrder } from '../paypal/orders.js';
import type { PayPalFetch } from '../paypal/client.js';
import { draftReply, type ReplyTone } from '../ai/draft_reply.js';
import { assertTransition, blockingAmbiguities } from '../domain/orders.js';
```

Extend `OrdersDeps` with `paypal: PayPalFetch`, add these schemas beside the others:

```ts
const confirmBodySchema = z.object({
  depositMinor: z.number().int().nonnegative().nullable().optional(),
});
const regenerateBodySchema = z.object({
  tone: z.enum(['friendly', 'short', 'formal']).default('friendly'),
});
```

and add these routes inside `ordersRouter`, before `return router`:

```ts
  router.post('/orders/:orderId/confirm', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = confirmBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'That request is not valid.', parsed.error.format()));
      return;
    }

    const sellerId = req.sellerId!;
    const ref = deps.db.doc(`sellers/${sellerId}/orders/${req.params.orderId}`);

    try {
      const snap = await ref.get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such order.')); return; }

      const order = snap.data() as OrderDoc;
      assertTransition(order.status, 'link_sent');

      const open = blockingAmbiguities(order.ambiguities);
      if (open.length > 0) {
        next(
          new ApiError(
            409,
            'ORDER_STATE_INVALID',
            open[0]!.question,
            { unresolved: open.map((a) => a.field) },
          ),
        );
        return;
      }

      const amounts = computeAmounts(
        order.subtotalMinor,
        parsed.data.depositMinor === undefined ? order.depositMinor : parsed.data.depositMinor,
      );
      const priced: OrderDoc = { ...order, ...amounts };

      // Nothing is written until PayPal has accepted the order, so a rejection
      // leaves the seller's draft exactly as it was to retry.
      const { paypalOrderId, approvalUrl } = await createPayPalOrder(
        priced,
        sellerId,
        deps.paypal,
      );

      const sellerSnap = await deps.db.doc(`sellers/${sellerId}`).get();
      const personaTone = (sellerSnap.data()?.personaTone as string | undefined) ?? '';

      let draftedReply: string | null = null;
      try {
        draftedReply = await draftReply(
          { order: priced, personaTone, approvalUrl, tone: 'friendly' },
          deps.transport,
          deps.model,
        );
      } catch {
        // The link is the thing that matters. A failed draft must not lose it.
        draftedReply = null;
      }

      const updated: OrderDoc = {
        ...priced,
        status: 'link_sent',
        paypalOrderId,
        approvalUrl,
        draftedReply,
      };

      await ref.update({
        ...updated,
        linkSentAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      res.json({ order: updated });
    } catch (err) {
      next(err);
    }
  });

  router.post('/orders/:orderId/reply/regenerate', requireSeller(deps.verify), async (req, res, next) => {
    const parsed = regenerateBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      next(new ApiError(400, 'VALIDATION_FAILED', 'That tone is not one Sorted knows.'));
      return;
    }

    const sellerId = req.sellerId!;
    const ref = deps.db.doc(`sellers/${sellerId}/orders/${req.params.orderId}`);

    try {
      const snap = await ref.get();
      if (!snap.exists) { next(new ApiError(404, 'NOT_FOUND', 'No such order.')); return; }

      const order = snap.data() as OrderDoc;
      if (!order.approvalUrl) {
        next(new ApiError(409, 'ORDER_STATE_INVALID', 'That order has no payment link yet.'));
        return;
      }

      const sellerSnap = await deps.db.doc(`sellers/${sellerId}`).get();
      const draftedReply = await draftReply(
        {
          order,
          personaTone: (sellerSnap.data()?.personaTone as string | undefined) ?? '',
          approvalUrl: order.approvalUrl,
          tone: parsed.data.tone as ReplyTone,
        },
        deps.transport,
        deps.model,
      );

      await ref.update({ draftedReply, updatedAt: FieldValue.serverTimestamp() });
      res.json({ draftedReply });
    } catch (err) {
      next(err);
    }
  });

  router.get('/orders', requireSeller(deps.verify), async (req, res, next) => {
    try {
      const snap = await deps.db
        .collection(`sellers/${req.sellerId}/orders`)
        .orderBy('createdAt', 'desc')
        .limit(50)
        .get();
      res.json({ orders: snap.docs.map((d) => d.data()), nextCursor: null });
    } catch (err) {
      next(err);
    }
  });
```

- [ ] **Step 8: Wire `paypal` through `api/src/app.ts` and `api/src/index.ts`**

In `app.ts`, add `paypal: PayPalFetch` to `AppDeps` and pass `deps.paypal` into `ordersRouter`. In `index.ts`:

```ts
import { makePayPalClient } from './paypal/client.js';

createApp({
  env,
  db,
  verify: adminTokenVerifier(auth),
  transport: makeOpenAiTransport(env),
  paypal: makePayPalClient(env),
});
```

Add `paypal: async () => ({})` to the stub `deps` in `health.test.ts`, `session.test.ts`, `cors.test.ts`, `catalogue-route.test.ts`, `products-route.test.ts` and `orders-route.test.ts`.

- [ ] **Step 9: Run it to verify it passes**

```bash
cd api && npx vitest run test/orders-confirm.test.ts
```

Expected: PASS, 12 tests.

- [ ] **Step 10: Run the whole suite and typecheck**

```bash
cd api && npm test && npm run typecheck
```

Expected: everything green.

- [ ] **Step 11: Commit**

```bash
cd /Users/bstar/Documents/development/apps/flutter/sorted
git add api/src api/test
git commit -m "feat(api): confirm an order into a PayPal link and a drafted reply

Confirm refuses while a blocking ambiguity is unanswered, so a link
cannot go to a buyer with a guessed size and a price the seller never
agreed to. Nothing is written until PayPal accepts the order, so a
rejection leaves the draft intact to retry rather than stranding a
half-created order.

The reply is validated to contain the exact approval link: a reply the
seller pastes without a working link is worse than none, because the
buyer cannot pay and nobody finds out until the chase. A failed draft
does not lose the link."
```

---

### Task 7: Flutter order models

**Files:**
- Create: `app/lib/models/line_item.dart`, `app/lib/models/order.dart`
- Test: `app/test/order_model_test.dart`

**Interfaces:**
- Consumes: `Ambiguity` from `models/ambiguity.dart`.
- Produces: `LineItem`, `Order` (freezed, with `fromJson`/`toJson`). `Order` exposes `bool get isBlocked`, `List<Ambiguity> get blockingAmbiguities`, `bool get hasLink`, `int get balanceMinor`.

- [ ] **Step 1: Write the failing test**

Create `app/test/order_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/models/ambiguity.dart';
import 'package:sorted/models/line_item.dart';
import 'package:sorted/models/order.dart';

const _line = LineItem(
  id: 'li-1', productId: 'p1', variantIds: ['10-inch'],
  nameRaw: 'lemon drizzle', nameResolved: 'Lemon drizzle cake',
  qty: 1, unitPriceMinor: 4200, lineTotalMinor: 4200,
  matchConfidence: 1, matchMethod: 'exact',
);

Order order({
  List<Ambiguity> ambiguities = const [],
  String? approvalUrl,
  int? depositMinor,
}) => Order(
      id: 'o1', status: 'draft', buyerName: 'Jess M', buyerHandle: 'jess.mcr',
      channel: 'instagram', lineItems: const [_line],
      subtotalMinor: 5600, depositMinor: depositMinor,
      amountDueMinor: depositMinor ?? 5600,
      fulfilment: const Fulfilment(mode: 'collection', date: '2026-10-10'),
      ambiguities: ambiguities, approvalUrl: approvalUrl,
    );

void main() {
  test('round-trips through JSON', () {
    final o = order();
    expect(Order.fromJson(o.toJson()), o);
  });

  test('tolerates the nulls the API sends on a fresh draft', () {
    final json = order().toJson()
      ..remove('approvalUrl')
      ..remove('paypalOrderId')
      ..remove('draftedReply')
      ..remove('depositMinor');
    final o = Order.fromJson(json);
    expect(o.approvalUrl, isNull);
    expect(o.hasLink, isFalse);
  });

  test('isBlocked while a blocking ambiguity is unanswered', () {
    final o = order(ambiguities: const [
      Ambiguity(field: 'lineItems[0].variantIds', kind: 'missing', question: 'Which size?'),
    ]);
    expect(o.isBlocked, isTrue);
    expect(o.blockingAmbiguities, hasLength(1));
  });

  test('a non-blocking ambiguity does not block', () {
    final o = order(ambiguities: const [
      Ambiguity(field: 'x', kind: 'unclear', question: 'eh?', blocking: false),
    ]);
    expect(o.isBlocked, isFalse);
  });

  test('isBlocked is false with no ambiguities', () {
    expect(order().isBlocked, isFalse);
  });

  test('hasLink once PayPal has given one', () {
    expect(order(approvalUrl: 'https://x/checkoutnow?token=T').hasLink, isTrue);
  });

  test('balanceMinor is what is left after a deposit', () {
    // The Draft screen tells the buyer what is still owed on collection.
    expect(order(depositMinor: 2000).balanceMinor, 3600);
  });

  test('balanceMinor is zero when the whole order is paid up front', () {
    expect(order().balanceMinor, 0);
  });

  test('a line keeps the buyer\'s own words alongside the resolved name', () {
    expect(_line.nameRaw, 'lemon drizzle');
    expect(_line.nameResolved, 'Lemon drizzle cake');
  });

  test('an unmatched line has no product and no price', () {
    const unmatched = LineItem(
      id: 'li-2', productId: null, variantIds: [], nameRaw: 'carrot cake',
      nameResolved: null, qty: 1, unitPriceMinor: 0, lineTotalMinor: 0,
      matchConfidence: 0, matchMethod: 'unmatched',
    );
    expect(unmatched.isUnmatched, isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd app && flutter test test/order_model_test.dart
```

Expected: FAIL — the model files do not exist.

- [ ] **Step 3: Write `app/lib/models/line_item.dart`**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'line_item.freezed.dart';
part 'line_item.g.dart';

@freezed
abstract class LineItem with _$LineItem {
  const LineItem._();

  const factory LineItem({
    required String id,
    /// Null when the catalogue had nothing matching, which is a blocking
    /// ambiguity rather than a GBP 0 line.
    String? productId,
    @Default(<String>[]) List<String> variantIds,
    /// What the buyer actually wrote, kept so the seller can see it.
    required String nameRaw,
    String? nameResolved,
    @Default(1) int qty,
    @Default(0) int unitPriceMinor,
    @Default(0) int lineTotalMinor,
    @Default(0.0) double matchConfidence,
    @Default('unmatched') String matchMethod,
  }) = _LineItem;

  factory LineItem.fromJson(Map<String, dynamic> json) => _$LineItemFromJson(json);

  bool get isUnmatched => productId == null;

  String get displayName => nameResolved ?? nameRaw;
}
```

- [ ] **Step 4: Write `app/lib/models/order.dart`**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

import 'ambiguity.dart';
import 'line_item.dart';

part 'order.freezed.dart';
part 'order.g.dart';

@freezed
abstract class Fulfilment with _$Fulfilment {
  const factory Fulfilment({
    @Default('unknown') String mode,
    String? date,
    String? notes,
  }) = _Fulfilment;

  factory Fulfilment.fromJson(Map<String, dynamic> json) => _$FulfilmentFromJson(json);
}

@freezed
abstract class Order with _$Order {
  const Order._();

  const factory Order({
    required String id,
    @Default('draft') String status,
    String? buyerName,
    String? buyerHandle,
    String? buyerEmail,
    @Default('unknown') String channel,
    @Default(<LineItem>[]) List<LineItem> lineItems,
    @Default(0) int subtotalMinor,
    int? depositMinor,
    @Default(0) int amountDueMinor,
    @Default('GBP') String currency,
    @Default(Fulfilment()) Fulfilment fulfilment,
    @Default(<Ambiguity>[]) List<Ambiguity> ambiguities,
    String? paypalOrderId,
    String? approvalUrl,
    String? draftedReply,
    @Default('screenshot') String sourceKind,
  }) = _Order;

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);

  List<Ambiguity> get blockingAmbiguities =>
      ambiguities.where((a) => a.blocking && !a.resolved).toList();

  /// The seller cannot create a link while the AI is still unsure of
  /// something that changes what the buyer pays.
  bool get isBlocked => blockingAmbiguities.isNotEmpty;

  bool get hasLink => (approvalUrl ?? '').isNotEmpty;

  /// What is still owed after a deposit, which the reply mentions.
  int get balanceMinor =>
      depositMinor == null ? 0 : subtotalMinor - depositMinor!;
}
```

- [ ] **Step 5: Add `resolved` to `Ambiguity`**

`app/lib/models/ambiguity.dart` needs the field the order model reads. Add it to the factory:

```dart
    @Default(true) bool blocking,
    @Default(false) bool resolved,
```

- [ ] **Step 6: Generate and run**

```bash
cd app && dart run build_runner build --delete-conflicting-outputs
flutter test test/order_model_test.dart && flutter analyze
```

Expected: PASS, 10 tests, `No issues found!`.

- [ ] **Step 7: Commit**

```bash
cd /Users/bstar/Documents/development/apps/flutter/sorted
git add app
git commit -m "feat(app): add order and line item models

Order.isBlocked drives the Draft screen's Create link button, mirroring
the guard the API enforces, so the seller is never offered a button
that would be refused. balanceMinor is what is still owed after a
deposit, which the reply mentions.

A line keeps the buyer's own words alongside the resolved catalogue
name, so the seller can see what was actually written."
```

---

### Task 8: Orders repository and providers

**Files:**
- Create: `app/lib/data/orders_repository.dart`, `app/lib/providers/orders_providers.dart`
- Modify: `app/lib/data/firestore_refs.dart`
- Test: `app/test/orders_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `apiClientProvider`, `sellerIdProvider`, `Order`.
- Produces:
  - `abstract class OrdersApi` with `draftFromImage`, `draftFromText`, `resolve`, `confirm`, `regenerateReply`
  - `HttpOrdersApi(ApiClient)`
  - `OrdersRepository` with `Stream<List<Order>> watchOrders(String sellerId)`, `Future<Order?> draft(...)`, `Future<Order> resolve(...)`, `Future<Order> confirm(...)`, `Future<String> regenerateReply(...)`
  - `ordersRepositoryProvider`, `ordersProvider` (`StreamProvider<List<Order>>`), `draftControllerProvider` (`NotifierProvider<DraftController, DraftState>`)
  - `sealed class DraftState` with `DraftIdle`, `DraftReading`, `DraftReady(Order)`, `DraftEmpty(String reason)`, `DraftFailed(String message)`

- [ ] **Step 1: Write the failing test**

Create `app/test/orders_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/data/orders_repository.dart';
import 'package:sorted/models/order.dart';

Map<String, dynamic> orderJson({
  String id = 'o1',
  String status = 'draft',
  List<Map<String, dynamic>>? ambiguities,
  String? approvalUrl,
}) => {
      'id': id, 'status': status, 'buyerName': 'Jess M', 'buyerHandle': 'jess.mcr',
      'channel': 'instagram',
      'lineItems': [
        {
          'id': 'li-1', 'productId': 'p1', 'variantIds': ['10-inch'],
          'nameRaw': 'lemon drizzle', 'nameResolved': 'Lemon drizzle cake',
          'qty': 1, 'unitPriceMinor': 4200, 'lineTotalMinor': 4200,
          'matchConfidence': 1.0, 'matchMethod': 'exact',
        },
      ],
      'subtotalMinor': 4200, 'amountDueMinor': 4200, 'currency': 'GBP',
      'fulfilment': {'mode': 'collection', 'date': '2026-10-10'},
      'ambiguities': ambiguities ?? <Map<String, dynamic>>[],
      if (approvalUrl != null) 'approvalUrl': approvalUrl,
    };

class _FakeApi implements OrdersApi {
  Map<String, dynamic> draftResponse = {'order': null, 'reason': 'nothing here'};
  Map<String, dynamic> orderResponse = {'order': {}};
  String replyResponse = 'hi';
  Object? throwOn;
  Object? lastBody;
  String? lastPath;

  @override
  Future<Map<String, dynamic>> draftFromImage(List<int> bytes, String filename) async {
    lastPath = 'image';
    if (throwOn != null) throw throwOn!;
    return draftResponse;
  }

  @override
  Future<Map<String, dynamic>> draftFromText(String text) async {
    lastPath = 'text';
    lastBody = text;
    if (throwOn != null) throw throwOn!;
    return draftResponse;
  }

  @override
  Future<Map<String, dynamic>> resolve(String orderId, Object body) async {
    lastBody = body;
    return orderResponse;
  }

  @override
  Future<Map<String, dynamic>> confirm(String orderId, Object body) async {
    lastBody = body;
    if (throwOn != null) throw throwOn!;
    return orderResponse;
  }

  @override
  Future<Map<String, dynamic>> regenerateReply(String orderId, String tone) async {
    lastBody = tone;
    return {'draftedReply': replyResponse};
  }
}

void main() {
  late _FakeApi api;
  late OrdersRepository repo;

  setUp(() {
    api = _FakeApi();
    repo = OrdersRepository(api: api);
  });

  test('returns a parsed order from a text draft', () async {
    api.draftResponse = {'order': orderJson()};
    final out = await repo.draftFromText('a lemon drizzle please');
    expect(out!.buyerName, 'Jess M');
    expect(out.subtotalMinor, 4200);
  });

  test('returns null when the API found no order', () async {
    api.draftResponse = {'order': null, 'reason': 'Sorted could not find an order in that.'};
    expect(await repo.draftFromText('a cat photo'), isNull);
    expect(repo.lastDraftReason, contains('could not find'));
  });

  test('sends a variant choice as a line edit', () async {
    api.orderResponse = {'order': orderJson()};
    await repo.resolve('o1', variantFor: ('li-1', ['8-inch']));
    final body = api.lastBody! as Map<String, dynamic>;
    final line = (body['lineItems'] as List).single as Map<String, dynamic>;
    expect(line['id'], 'li-1');
    expect(line['variantIds'], ['8-inch']);
  });

  test('sends a deposit on its own', () async {
    api.orderResponse = {'order': orderJson()};
    await repo.resolve('o1', depositMinor: 2000);
    expect((api.lastBody! as Map<String, dynamic>)['depositMinor'], 2000);
  });

  test('refuses to confirm an order that is still blocked', () async {
    // The API refuses too; failing here saves a round trip and a confusing
    // error, and keeps the button and the rule in agreement.
    final blocked = Order.fromJson(orderJson(ambiguities: [
      {'field': 'lineItems[0].variantIds', 'kind': 'missing', 'question': 'Which size?'},
    ]));
    expect(() => repo.confirm(blocked), throwsA(isA<ArgumentError>()));
  });

  test('confirms an unblocked order', () async {
    api.orderResponse = {
      'order': orderJson(status: 'link_sent', approvalUrl: 'https://x/checkoutnow?token=T'),
    };
    final out = await repo.confirm(Order.fromJson(orderJson()));
    expect(out.status, 'link_sent');
    expect(out.hasLink, isTrue);
  });

  test('passes a deposit through on confirm', () async {
    api.orderResponse = {'order': orderJson()};
    await repo.confirm(Order.fromJson(orderJson()), depositMinor: 1500);
    expect((api.lastBody! as Map<String, dynamic>)['depositMinor'], 1500);
  });

  test('regenerates the reply in a given tone', () async {
    api.replyResponse = 'Dear Jess, ...';
    final out = await repo.regenerateReply('o1', 'formal');
    expect(out, 'Dear Jess, ...');
    expect(api.lastBody, 'formal');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd app && flutter test test/orders_repository_test.dart
```

Expected: FAIL — `orders_repository.dart` does not exist.

- [ ] **Step 3: Write `app/lib/data/orders_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/api_client.dart';
import '../models/order.dart';

/// Named so tests can fake it without Dio or a live token.
abstract class OrdersApi {
  Future<Map<String, dynamic>> draftFromImage(List<int> bytes, String filename);
  Future<Map<String, dynamic>> draftFromText(String text);
  Future<Map<String, dynamic>> resolve(String orderId, Object body);
  Future<Map<String, dynamic>> confirm(String orderId, Object body);
  Future<Map<String, dynamic>> regenerateReply(String orderId, String tone);
}

class HttpOrdersApi implements OrdersApi {
  HttpOrdersApi(this._client);
  final ApiClient _client;

  @override
  Future<Map<String, dynamic>> draftFromImage(List<int> bytes, String filename) =>
      _client.postImages('/v1/orders/draft', [(bytes: bytes, filename: filename)],
          field: 'image');

  @override
  Future<Map<String, dynamic>> draftFromText(String text) =>
      _client.postForm('/v1/orders/draft', {'text': text});

  @override
  Future<Map<String, dynamic>> resolve(String orderId, Object body) =>
      _client.postJson('/v1/orders/$orderId/resolve', body);

  @override
  Future<Map<String, dynamic>> confirm(String orderId, Object body) =>
      _client.postJson('/v1/orders/$orderId/confirm', body);

  @override
  Future<Map<String, dynamic>> regenerateReply(String orderId, String tone) =>
      _client.postJson('/v1/orders/$orderId/reply/regenerate', {'tone': tone});
}

class OrdersRepository {
  OrdersRepository({required this.api});
  final OrdersApi api;

  /// Set when a draft came back empty, so the screen can say why.
  String? lastDraftReason;

  Stream<List<Order>> watchOrders(String sellerId) => FirebaseFirestore.instance
      .collection('sellers/$sellerId/orders')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => Order.fromJson({...d.data(), 'id': d.id}))
          .toList());

  Order? _readOrder(Map<String, dynamic> json) {
    final raw = json['order'];
    if (raw == null) {
      lastDraftReason = json['reason'] as String?;
      return null;
    }
    lastDraftReason = null;
    return Order.fromJson(raw as Map<String, dynamic>);
  }

  Future<Order?> draftFromText(String text) async =>
      _readOrder(await api.draftFromText(text));

  Future<Order?> draftFromImage(List<int> bytes, String filename) async =>
      _readOrder(await api.draftFromImage(bytes, filename));

  Future<Order> resolve(
    String orderId, {
    (String, List<String>)? variantFor,
    int? qtyFor,
    String? qtyLineId,
    int? depositMinor,
    String? buyerName,
    String? fulfilmentDate,
  }) async {
    // Built as one list: two collection-ifs both writing 'lineItems' would
    // silently drop the first, so a call changing a variant AND a quantity
    // would lose the variant.
    final edits = <Map<String, dynamic>>[
      if (variantFor != null) {'id': variantFor.$1, 'variantIds': variantFor.$2},
      if (qtyFor != null && qtyLineId != null) {'id': qtyLineId, 'qty': qtyFor},
    ];

    final body = <String, dynamic>{
      if (edits.isNotEmpty) 'lineItems': edits,
      if (depositMinor != null) 'depositMinor': depositMinor,
      if (buyerName != null) 'buyerName': buyerName,
      if (fulfilmentDate != null) 'fulfilment': {'date': fulfilmentDate},
    };
    final json = await api.resolve(orderId, body);
    return Order.fromJson(json['order'] as Map<String, dynamic>);
  }

  Future<Order> confirm(Order order, {int? depositMinor}) async {
    if (order.isBlocked) {
      throw ArgumentError(order.blockingAmbiguities.first.question);
    }
    final json = await api.confirm(order.id, {
      if (depositMinor != null) 'depositMinor': depositMinor,
    });
    return Order.fromJson(json['order'] as Map<String, dynamic>);
  }

  Future<String> regenerateReply(String orderId, String tone) async {
    final json = await api.regenerateReply(orderId, tone);
    return json['draftedReply'] as String;
  }
}
```

- [ ] **Step 4: Extend `ApiClient` with the two shapes this needs**

`postImages` currently hardcodes the field name `images` and `postForm` does not exist. In `app/lib/core/api_client.dart`:

```dart
  Future<Map<String, dynamic>> postImages(
    String path,
    List<({List<int> bytes, String filename})> files, {
    String field = 'images',
  }) async {
    final form = FormData();
    for (final f in files) {
      form.files.add(
        MapEntry(field, MultipartFile.fromBytes(f.bytes, filename: f.filename)),
      );
    }
    final res = await _dio.post<Map<String, dynamic>>(
      path,
      data: form,
      options: await _authed(),
    );
    return res.data ?? <String, dynamic>{};
  }

  /// multipart with no file, because /orders/draft accepts either an image or
  /// a text field on the same endpoint.
  Future<Map<String, dynamic>> postForm(
    String path,
    Map<String, String> fields,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap(fields),
      options: await _authed(),
    );
    return res.data ?? <String, dynamic>{};
  }
```

- [ ] **Step 5: Write `app/lib/providers/orders_providers.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../data/orders_repository.dart';
import '../models/order.dart';
import 'api_provider.dart';
import 'seller_provider.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(api: HttpOrdersApi(ref.watch(apiClientProvider))),
);

/// The live order list. A Firestore listener, so an order that turns paid in
/// week 4 flips on screen without the app asking again.
final ordersProvider = StreamProvider<List<Order>>((ref) {
  final sellerId = ref.watch(sellerIdProvider).value;
  if (sellerId == null) return const Stream<List<Order>>.empty();
  return ref.watch(ordersRepositoryProvider).watchOrders(sellerId);
});

sealed class DraftState {
  const DraftState();
}

class DraftIdle extends DraftState {
  const DraftIdle();
}

/// The model is working. [step] drives the ticking checklist on Reading.
class DraftReading extends DraftState {
  const DraftReading(this.step);
  final int step;
}

class DraftReady extends DraftState {
  const DraftReady(this.order);
  final Order order;
}

/// The conversation had no order in it.
class DraftEmpty extends DraftState {
  const DraftEmpty(this.reason);
  final String reason;
}

class DraftFailed extends DraftState {
  const DraftFailed(this.message);
  final String message;
}

class DraftController extends Notifier<DraftState> {
  @override
  DraftState build() => const DraftIdle();

  Future<void> fromText(String text) =>
      _run(() => ref.read(ordersRepositoryProvider).draftFromText(text));

  Future<void> fromImage(List<int> bytes, String filename) =>
      _run(() => ref.read(ordersRepositoryProvider).draftFromImage(bytes, filename));

  Future<void> _run(Future<Order?> Function() call) async {
    state = const DraftReading(0);
    try {
      final order = await call();
      if (order == null) {
        state = DraftEmpty(
          ref.read(ordersRepositoryProvider).lastDraftReason ??
              'Sorted could not find an order in that.',
        );
        return;
      }
      state = DraftReady(order);
    } catch (e) {
      state = DraftFailed(describeApiError(e));
    }
  }

  /// Called by the Reading screen's ticker so the checklist advances while the
  /// request is in flight.
  void advance() {
    final current = state;
    if (current is DraftReading) state = DraftReading(current.step + 1);
  }

  void replace(Order order) => state = DraftReady(order);

  void clear() => state = const DraftIdle();
}

final draftControllerProvider =
    NotifierProvider<DraftController, DraftState>(DraftController.new);
```

- [ ] **Step 6: Run the tests and analyse**

```bash
cd app && flutter test test/orders_repository_test.dart && flutter analyze
```

Expected: PASS, 8 tests, `No issues found!`.

- [ ] **Step 7: Commit**

```bash
cd /Users/bstar/Documents/development/apps/flutter/sorted
git add app
git commit -m "feat(app): orders repository, draft state machine and providers

Orders stream from Firestore so week 4's paid flip needs no polling.
The repository refuses to confirm a blocked order, matching the guard
the API enforces, so the button and the rule cannot disagree.

DraftState distinguishes 'the model found no order' from 'the request
failed': the first is a normal outcome of photographing the wrong
thing and deserves its own screen, not an error."
```

---

### Task 9: The Intake and Reading screens

Covers Review Focus item 1 — a screenshot with no order in it must say so.

**Files:**
- Create: `app/lib/features/order/intake_screen.dart`, `app/lib/features/order/reading_screen.dart`
- Modify: `app/lib/router.dart`
- Test: `app/test/intake_screen_test.dart`, `app/test/reading_screen_test.dart`

**Interfaces:**
- Consumes: `draftControllerProvider`, `DraftState` and its variants, `imagePickerProvider` from `features/catalogue/snap_screen.dart`, `PrimaryButton`, `WarningCard`.
- Produces: `IntakeScreen`, `ReadingScreen`; routes `/order/new` and `/order/reading`.

- [ ] **Step 1: Write the failing intake test**

Create `app/test/intake_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/catalogue/snap_screen.dart' show ImagePickerPort, imagePickerProvider;
import 'package:sorted/features/order/intake_screen.dart';

class _FakePicker implements ImagePickerPort {
  _FakePicker(this.returns);
  final List<({List<int> bytes, String filename})> returns;
  int calls = 0;

  @override
  Future<List<({List<int> bytes, String filename})>> pick({required bool fromCamera}) async {
    calls++;
    return returns;
  }
}

Widget _host(_FakePicker picker) => ProviderScope(
      overrides: [imagePickerProvider.overrideWithValue(picker)],
      child: MaterialApp.router(
        theme: sortedTheme(),
        routerConfig: GoRouter(
          initialLocation: '/order/new',
          routes: [
            GoRoute(path: '/order/new', builder: (_, _) => const IntakeScreen()),
            GoRoute(path: '/order/reading', builder: (_, _) => const Scaffold(body: Text('reading landed'))),
          ],
        ),
      ),
    );

void main() {
  testWidgets('offers both paste and upload, because web has no share sheet', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Upload'), findsWidgets);
  });

  testWidgets('the read button is disabled with an empty box', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.enabled, isFalse);
  });

  testWidgets('typing a message enables the read button', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'can I get a 10 inch lemon drizzle');
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.enabled, isTrue);
  });

  testWidgets('whitespace alone does not count as a message', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '    ');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).enabled, isFalse);
  });

  testWidgets('picking a screenshot goes straight to reading', (tester) async {
    final picker = _FakePicker([(bytes: [1, 2, 3], filename: 'dm.png')]);
    await tester.pumpWidget(_host(picker));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('intake-upload')));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(find.text('reading landed'), findsOneWidget);
  });

  testWidgets('explains what to share', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    await tester.pumpAndSettle();
    expect(find.textContaining('screenshot'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd app && flutter test test/intake_screen_test.dart
```

Expected: FAIL — `intake_screen.dart` does not exist.

- [ ] **Step 3: Write `app/lib/features/order/intake_screen.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import '../catalogue/snap_screen.dart' show imagePickerProvider;

/// Where an order starts on the web, and the fallback on mobile when the
/// share sheet is not used. The hosted build has no share sheet at all, so
/// paste and upload are the judges' path.
class IntakeScreen extends ConsumerStatefulWidget {
  const IntakeScreen({super.key});

  @override
  ConsumerState<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends ConsumerState<IntakeScreen> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    setState(() => _busy = true);
    final picked = await ref.read(imagePickerProvider).pick(fromCamera: false);
    if (!mounted) return;
    if (picked.isEmpty) {
      setState(() => _busy = false);
      return;
    }
    final first = picked.first;
    unawaited(
      ref.read(draftControllerProvider.notifier).fromImage(first.bytes, first.filename),
    );
    if (mounted) context.push('/order/reading');
  }

  Future<void> _read() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    unawaited(ref.read(draftControllerProvider.notifier).fromText(text));
    if (mounted) context.push('/order/reading');
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final hasText = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('New order')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SortedShape.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share the conversation', style: text.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Paste what the buyer wrote, or upload a screenshot of the chat. Sorted reads it and builds the order.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                key: const Key('intake-upload'),
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Upload a screenshot'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: Divider(color: c.line)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or paste it', style: text.bodySmall),
                  ),
                  Expanded(child: Divider(color: c.line)),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SortedShape.cardRadius),
                    ),
                    hintText: 'hiya! can I get a 10 inch lemon drizzle for Saturday?',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: 'Read this',
                onPressed: hasText && !_busy ? _read : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

`unawaited` comes from `dart:async`, imported above. It is deliberate: the
draft request runs while the Reading screen animates, so the seller watches
progress instead of a frozen button.

- [ ] **Step 4: Write the failing reading test**

Create `app/test/reading_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/order/reading_screen.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/providers/orders_providers.dart';

class _StubController extends DraftController {
  _StubController(this._initial);
  final DraftState _initial;
  @override
  DraftState build() => _initial;
}

Widget _host(DraftState state) => ProviderScope(
      overrides: [draftControllerProvider.overrideWith(() => _StubController(state))],
      child: MaterialApp.router(
        theme: sortedTheme(),
        routerConfig: GoRouter(
          initialLocation: '/order/reading',
          routes: [
            GoRoute(path: '/order/reading', builder: (_, _) => const ReadingScreen()),
            GoRoute(path: '/order/draft', builder: (_, _) => const Scaffold(body: Text('draft landed'))),
            GoRoute(path: '/order/new', builder: (_, _) => const Scaffold(body: Text('intake landed'))),
          ],
        ),
      ),
    );

const _order = Order(id: 'o1', buyerName: 'Jess M');

void main() {
  testWidgets('shows the checklist while the model works', (tester) async {
    await tester.pumpWidget(_host(const DraftReading(0)));
    await tester.pump();
    expect(find.textContaining('Reading'), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('moves to the draft once it is ready', (tester) async {
    await tester.pumpWidget(_host(const DraftReady(_order)));
    await tester.pumpAndSettle();
    expect(find.text('draft landed'), findsOneWidget);
  });

  testWidgets('says plainly when the photo had no order in it', (tester) async {
    // Photographing a receipt or a menu is a normal mistake and deserves an
    // explanation, not an error screen.
    await tester.pumpWidget(_host(const DraftEmpty('Sorted could not find an order in that.')));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not find an order'), findsOneWidget);
    expect(find.textContaining('Try again'), findsWidgets);
  });

  testWidgets('offers another go after an empty read', (tester) async {
    await tester.pumpWidget(_host(const DraftEmpty('nothing there')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('intake landed'), findsOneWidget);
  });

  testWidgets('shows the message when the request failed', (tester) async {
    await tester.pumpWidget(_host(const DraftFailed('Sorted could not reach the server.')));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not reach the server'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run it to verify it fails**

```bash
cd app && flutter test test/reading_screen_test.dart
```

Expected: FAIL — `reading_screen.dart` does not exist.

- [ ] **Step 6: Write `app/lib/features/order/reading_screen.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';

/// The 3-10 second wait while the model reads the conversation.
///
/// Reading.dc.html shows a checklist that ticks off rather than a spinner,
/// which is the difference between "it is thinking" and "it is working". The
/// steps are honest about what the backend does in order.
const _steps = [
  'Reading the conversation',
  'Finding what they asked for',
  'Matching your catalogue',
  'Checking sizes and prices',
];

class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({super.key});

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  Timer? _ticker;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    // Advance a step roughly every second so the list moves while the single
    // request is in flight. It stops at the last step rather than looping.
    _ticker = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      setState(() => _shown = (_shown + 1).clamp(0, _steps.length - 1));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(draftControllerProvider);

    ref.listen(draftControllerProvider, (_, next) {
      if (next is DraftReady) context.go('/order/draft');
    });

    if (state is DraftEmpty || state is DraftFailed) {
      final message = state is DraftEmpty
          ? state.reason
          : (state as DraftFailed).message;
      final isEmpty = state is DraftEmpty;

      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SortedShape.screenPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isEmpty ? 'No order in that one' : 'That did not work',
                  style: text.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Try again',
                  onPressed: () {
                    ref.read(draftControllerProvider.notifier).clear();
                    context.go('/order/new');
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SortedShape.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('New order', style: text.bodySmall),
              Text('Reading the message', style: text.headlineMedium),
              const SizedBox(height: 24),
              for (var i = 0; i < _steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      if (i < _shown)
                        Icon(Icons.check_circle, size: 20, color: c.success)
                      else if (i == _shown)
                        SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
                        )
                      else
                        Icon(Icons.circle_outlined, size: 20, color: c.line),
                      const SizedBox(width: 12),
                      Text(
                        _steps[i],
                        style: i <= _shown
                            ? text.bodyLarge
                            : text.bodyMedium?.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Add the routes to `app/lib/router.dart`**

```dart
import 'features/order/intake_screen.dart';
import 'features/order/reading_screen.dart';
```

and outside the shell route, beside the existing catalogue routes:

```dart
    GoRoute(path: '/order/new', builder: (_, _) => const IntakeScreen()),
    GoRoute(path: '/order/reading', builder: (_, _) => const ReadingScreen()),
```

Change the shell's centre action to start an order rather than a snap, which is what the design's raised button means:

```dart
        onPressed: () => context.push('/order/new'),
```

- [ ] **Step 8: Run the tests and analyse**

```bash
cd app && flutter test test/intake_screen_test.dart test/reading_screen_test.dart && flutter analyze
```

Expected: PASS, 11 tests, `No issues found!`.

- [ ] **Step 9: Commit**

```bash
cd /Users/bstar/Documents/development/apps/flutter/sorted
git add app
git commit -m "feat(app): add the Intake and Reading screens

Intake is paste-or-upload, which is the only path on the web build and
the fallback on mobile. Reading shows the ticking checklist from the
design rather than a spinner, so the 3-10 second wait reads as work
rather than a hang.

A conversation with no order in it gets its own screen saying so and
offering another go: photographing a receipt or a menu is a normal
mistake, not an error."
```

---

### Task 10: The Draft screen

The beat the demo video holds on: the seller tapping an ambiguity chip, proving the AI asked rather than guessed.

**Files:**
- Create: `app/lib/features/order/draft_screen.dart`
- Modify: `app/lib/router.dart`
- Test: `app/test/draft_screen_test.dart`

**Interfaces:**
- Consumes: `draftControllerProvider`, `ordersRepositoryProvider`, `Order`, `formatGbp`, `SelectableChip`, `WarningCard`, `PrimaryButton`, `describeApiError`.
- Produces: `DraftScreen`; route `/order/draft`.

- [ ] **Step 1: Write the failing test**

Create `app/test/draft_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/data/orders_repository.dart';
import 'package:sorted/features/order/draft_screen.dart';
import 'package:sorted/models/ambiguity.dart';
import 'package:sorted/models/line_item.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/providers/orders_providers.dart';

const _cake = LineItem(
  id: 'li-1', productId: 'p1', variantIds: ['10-inch'],
  nameRaw: 'lemon drizzle cake', nameResolved: 'Lemon drizzle cake',
  qty: 1, unitPriceMinor: 4200, lineTotalMinor: 4200,
  matchConfidence: 1, matchMethod: 'exact',
);
const _brownies = LineItem(
  id: 'li-2', productId: 'p2', variantIds: ['box-of-6'],
  nameRaw: 'brownie box of 6', nameResolved: 'Brownie box',
  qty: 1, unitPriceMinor: 1400, lineTotalMinor: 1400,
  matchConfidence: 1, matchMethod: 'exact',
);

Order _order({List<Ambiguity> ambiguities = const []}) => Order(
      id: 'o1', status: 'draft', buyerName: 'Jess M', buyerHandle: 'jess.mcr',
      channel: 'instagram', lineItems: const [_cake, _brownies],
      subtotalMinor: 5600, amountDueMinor: 5600,
      fulfilment: const Fulfilment(mode: 'collection', date: '2026-10-10', notes: "For her mum's birthday"),
      ambiguities: ambiguities,
    );

class _FakeApi implements OrdersApi {
  Object? lastResolveBody;
  bool confirmed = false;
  Order? resolveReturns;

  @override
  Future<Map<String, dynamic>> draftFromImage(List<int> b, String f) async => {'order': null};
  @override
  Future<Map<String, dynamic>> draftFromText(String t) async => {'order': null};
  @override
  Future<Map<String, dynamic>> resolve(String id, Object body) async {
    lastResolveBody = body;
    return {'order': (resolveReturns ?? _order()).toJson()};
  }
  @override
  Future<Map<String, dynamic>> confirm(String id, Object body) async {
    confirmed = true;
    return {
      'order': _order().copyWith(status: 'link_sent', approvalUrl: 'https://x/checkoutnow?token=T').toJson(),
    };
  }
  @override
  Future<Map<String, dynamic>> regenerateReply(String id, String tone) async => {'draftedReply': 'hi'};
}

class _StubController extends DraftController {
  _StubController(this._order);
  final Order _order;
  @override
  DraftState build() => DraftReady(_order);
}

Widget _host(Order order, {_FakeApi? api}) => ProviderScope(
      overrides: [
        draftControllerProvider.overrideWith(() => _StubController(order)),
        if (api != null)
          ordersRepositoryProvider.overrideWithValue(OrdersRepository(api: api)),
      ],
      child: MaterialApp.router(
        theme: sortedTheme(),
        routerConfig: GoRouter(
          initialLocation: '/order/draft',
          routes: [
            GoRoute(path: '/order/draft', builder: (_, _) => const DraftScreen()),
            GoRoute(path: '/order/reply', builder: (_, _) => const Scaffold(body: Text('reply landed'))),
          ],
        ),
      ),
    );

void main() {
  testWidgets('shows the buyer, the items and the total', (tester) async {
    await tester.pumpWidget(_host(_order()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Jess M'), findsWidgets);
    expect(find.text('Lemon drizzle cake'), findsOneWidget);
    expect(find.text('Brownie box'), findsOneWidget);
    expect(find.textContaining('£56.00'), findsWidgets);
  });

  testWidgets('shows the collection date and note from the conversation', (tester) async {
    await tester.pumpWidget(_host(_order()));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-10-10'), findsWidgets);
    expect(find.textContaining("mum's birthday"), findsWidgets);
  });

  testWidgets('asks which size when the AI could not tell', (tester) async {
    // The beat the demo holds on: it asked instead of guessing.
    await tester.pumpWidget(_host(_order(ambiguities: const [
      Ambiguity(
        field: 'lineItems[0].variantIds', kind: 'missing',
        question: "Jess didn't say which size. Pick one.",
        options: ['8 inch', '10 inch'],
      ),
    ])));
    await tester.pumpAndSettle();
    expect(find.textContaining("didn't say which size"), findsOneWidget);
    expect(find.text('8 inch'), findsOneWidget);
    expect(find.text('10 inch'), findsOneWidget);
  });

  testWidgets('the create button is disabled while a question is unanswered', (tester) async {
    await tester.pumpWidget(_host(_order(ambiguities: const [
      Ambiguity(field: 'lineItems[0].variantIds', kind: 'missing', question: 'Which size?', options: ['8 inch']),
    ])));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).enabled, isFalse);
  });

  testWidgets('the create button is enabled with nothing outstanding', (tester) async {
    await tester.pumpWidget(_host(_order()));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).enabled, isTrue);
  });

  testWidgets('answering a question sends the variant to the API', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_host(
      _order(ambiguities: const [
        Ambiguity(
          field: 'lineItems[0].variantIds', kind: 'missing',
          question: 'Which size?', options: ['8 inch', '10 inch'],
        ),
      ]),
      api: api,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8 inch'));
    await tester.pumpAndSettle();

    final body = api.lastResolveBody! as Map<String, dynamic>;
    final line = (body['lineItems'] as List).single as Map<String, dynamic>;
    expect(line['id'], 'li-1');
    expect(line['variantIds'], ['8-inch']);
  });

  testWidgets('flags a line the catalogue did not have', (tester) async {
    const unmatched = LineItem(
      id: 'li-3', productId: null, variantIds: [], nameRaw: 'gluten free carrot cake',
      nameResolved: null, qty: 1, unitPriceMinor: 0, lineTotalMinor: 0,
      matchConfidence: 0, matchMethod: 'unmatched',
    );
    final order = _order().copyWith(lineItems: const [unmatched]);
    await tester.pumpWidget(_host(order));
    await tester.pumpAndSettle();
    expect(find.textContaining('gluten free carrot cake'), findsWidgets);
    expect(find.textContaining('not in your catalogue'), findsWidgets);
  });

  testWidgets('creating the link goes to the reply', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_host(_order(), api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(api.confirmed, isTrue);
    expect(find.text('reply landed'), findsOneWidget);
  });

  testWidgets('shows the deposit split when one is set', (tester) async {
    final order = _order().copyWith(depositMinor: 2000, amountDueMinor: 2000);
    await tester.pumpWidget(_host(order));
    await tester.pumpAndSettle();
    expect(find.textContaining('£20.00'), findsWidgets);
    expect(find.textContaining('£36.00'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd app && flutter test test/draft_screen_test.dart
```

Expected: FAIL — `draft_screen.dart` does not exist.

- [ ] **Step 3: Write `app/lib/features/order/draft_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../models/ambiguity.dart';
import '../../models/line_item.dart';
import '../../models/order.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/selectable_chip.dart';
import '../../widgets/warning_card.dart';

/// Turns a variant label into the id the API expects. The backend slugifies
/// labels the same way, so "Box of 6" and "box-of-6" line up.
String _slug(String label) => label
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

int? _lineIndexFor(Ambiguity a) {
  final match = RegExp(r'^lineItems\[(\d+)\]').firstMatch(a.field);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// Written as a loop rather than `.firstOrNull`, which is a package:collection
/// extension and not part of dart:core.
Ambiguity? _ambiguityForLine(Order order, int index) {
  for (final a in order.blockingAmbiguities) {
    if (_lineIndexFor(a) == index) return a;
  }
  return null;
}

class DraftScreen extends ConsumerStatefulWidget {
  const DraftScreen({super.key});

  @override
  ConsumerState<DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends ConsumerState<DraftScreen> {
  bool _busy = false;

  Future<void> _answer(Order order, Ambiguity a, String label) async {
    final index = _lineIndexFor(a);
    if (index == null || index >= order.lineItems.length) return;
    final line = order.lineItems[index];

    setState(() => _busy = true);
    try {
      final updated = await ref.read(ordersRepositoryProvider).resolve(
            order.id,
            variantFor: (line.id, [_slug(label)]),
          );
      ref.read(draftControllerProvider.notifier).replace(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create(Order order) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final confirmed = await ref.read(ordersRepositoryProvider).confirm(order);
      ref.read(draftControllerProvider.notifier).replace(confirmed);
      router.go('/order/reply');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(describeApiError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(draftControllerProvider);

    if (state is! DraftReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final order = state.order;

    return Scaffold(
      appBar: AppBar(title: const Text('Order draft')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SortedShape.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order for ${order.buyerName ?? 'your buyer'}',
                style: text.headlineMedium,
              ),
              Text(
                order.sourceKind == 'screenshot'
                    ? 'Read from a screenshot'
                    : 'Read from a pasted message',
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < order.lineItems.length; i++)
                      _LineCard(
                        line: order.lineItems[i],
                        ambiguity: _ambiguityForLine(order, i),
                        busy: _busy,
                        onAnswer: (ambiguity, label) => _answer(order, ambiguity, label),
                      ),
                    const SizedBox(height: 10),
                    _Detail(label: 'Buyer', value: [
                      order.buyerName,
                      if (order.buyerHandle != null) '(${order.buyerHandle})',
                    ].whereType<String>().join(' ')),
                    if (order.fulfilment.date != null)
                      _Detail(
                        label: order.fulfilment.mode == 'delivery' ? 'Delivery' : 'Collection',
                        value: order.fulfilment.date!,
                      ),
                    if (order.fulfilment.notes != null)
                      _Detail(label: 'Note', value: order.fulfilment.notes!),
                  ],
                ),
              ),
              Divider(color: c.line),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order.depositMinor == null ? 'Total' : 'Deposit now',
                    style: text.titleLarge,
                  ),
                  Text(formatGbp(order.amountDueMinor), style: text.headlineMedium),
                ],
              ),
              if (order.depositMinor != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${formatGbp(order.balanceMinor)} on collection',
                    style: text.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: _busy ? 'Creating the link…' : 'Create payment link',
                onPressed: order.isBlocked || _busy ? null : () => _create(order),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.ambiguity,
    required this.busy,
    required this.onAnswer,
  });

  final LineItem line;
  final Ambiguity? ambiguity;
  final bool busy;
  final void Function(Ambiguity ambiguity, String label) onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  line.qty > 1 ? '${line.qty} x ${line.displayName}' : line.displayName,
                  style: text.titleLarge,
                ),
              ),
              if (!line.isUnmatched)
                Text(formatGbp(line.lineTotalMinor), style: text.labelLarge),
            ],
          ),
          if (line.isUnmatched) ...[
            const SizedBox(height: 8),
            WarningCard(
              message:
                  '"${line.nameRaw}" is not in your catalogue, so it has no price. '
                  'Add it from the Catalogue tab, then read the message again.',
            ),
          ] else if (ambiguity != null) ...[
            const SizedBox(height: 8),
            WarningCard(
              message: ambiguity!.question,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in ambiguity!.options)
                    SelectableChip(
                      label: option,
                      selected: false,
                      onTap: busy ? () {} : () => onAnswer(ambiguity!, option),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: text.bodySmall?.copyWith(color: c.muted)),
          ),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Add the route**

In `app/lib/router.dart`, beside the other order routes:

```dart
    GoRoute(path: '/order/draft', builder: (_, _) => const DraftScreen()),
```

- [ ] **Step 5: Run the tests and analyse**

```bash
cd app && flutter test test/draft_screen_test.dart && flutter analyze
```

Expected: PASS, 9 tests, `No issues found!`.

- [ ] **Step 6: Commit**

```bash
cd /Users/bstar/Documents/development/apps/flutter/sorted
git add app
git commit -m "feat(app): add the Draft screen

The confirm step the core flow exists for. An ambiguity renders as a
warning card with tappable options right under the line it belongs to,
so the seller answers in one tap and the screen reprices from the API
rather than guessing locally.

Create payment link stays disabled while anything is unanswered, which
mirrors the guard the API enforces. A line the catalogue did not have
says so instead of showing a GBP 0 price."
```

---

### Task 11: The Reply screen

**Files:**
- Create: `app/lib/features/order/reply_screen.dart`
- Modify: `app/lib/router.dart`
- Test: `app/test/reply_screen_test.dart`

**Interfaces:**
- Consumes: `draftControllerProvider`, `ordersRepositoryProvider`, `Order`, `formatGbp`, `SelectableChip`, `PrimaryButton`.
- Produces: `ReplyScreen`; route `/order/reply`.

- [ ] **Step 1: Write the failing test**

Create `app/test/reply_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/data/orders_repository.dart';
import 'package:sorted/features/order/reply_screen.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/providers/orders_providers.dart';

const _link = 'https://www.sandbox.paypal.com/checkoutnow?token=PP1';

Order _sent({String? reply}) => Order(
      id: 'o1', status: 'link_sent', buyerName: 'Jess M',
      subtotalMinor: 5600, amountDueMinor: 5600,
      approvalUrl: _link,
      draftedReply: reply ?? "Hi Jess! That's sorted, £56 total. Pay here: $_link",
    );

class _FakeApi implements OrdersApi {
  String? lastTone;
  @override
  Future<Map<String, dynamic>> draftFromImage(List<int> b, String f) async => {'order': null};
  @override
  Future<Map<String, dynamic>> draftFromText(String t) async => {'order': null};
  @override
  Future<Map<String, dynamic>> resolve(String id, Object body) async => {'order': _sent().toJson()};
  @override
  Future<Map<String, dynamic>> confirm(String id, Object body) async => {'order': _sent().toJson()};
  @override
  Future<Map<String, dynamic>> regenerateReply(String id, String tone) async {
    lastTone = tone;
    return {'draftedReply': 'Dear Jess, your order is confirmed. $_link'};
  }
}

class _StubController extends DraftController {
  _StubController(this._order);
  final Order _order;
  @override
  DraftState build() => DraftReady(_order);
}

Widget _host(Order order, {_FakeApi? api}) => ProviderScope(
      overrides: [
        draftControllerProvider.overrideWith(() => _StubController(order)),
        if (api != null)
          ordersRepositoryProvider.overrideWithValue(OrdersRepository(api: api)),
      ],
      child: MaterialApp.router(
        theme: sortedTheme(),
        routerConfig: GoRouter(
          initialLocation: '/order/reply',
          routes: [
            GoRoute(path: '/order/reply', builder: (_, _) => const ReplyScreen()),
            GoRoute(path: '/orders', builder: (_, _) => const Scaffold(body: Text('orders landed'))),
          ],
        ),
      ),
    );

void main() {
  testWidgets('shows the amount and the drafted reply', (tester) async {
    await tester.pumpWidget(_host(_sent()));
    await tester.pumpAndSettle();
    expect(find.textContaining('£56'), findsWidgets);
    expect(find.textContaining('Hi Jess!'), findsOneWidget);
  });

  testWidgets('shows the link so the seller can see what they are sending', (tester) async {
    await tester.pumpWidget(_host(_sent()));
    await tester.pumpAndSettle();
    expect(find.textContaining('checkoutnow'), findsWidgets);
  });

  testWidgets('copy puts the whole reply on the clipboard', (tester) async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });

    await tester.pumpWidget(_host(_sent()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, contains(_link));
  });

  testWidgets('changing the tone asks the API to rewrite it', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_host(_sent(), api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Formal'));
    await tester.pumpAndSettle();
    expect(api.lastTone, 'formal');
    expect(find.textContaining('Dear Jess'), findsOneWidget);
  });

  testWidgets('says it is waiting to be paid', (tester) async {
    await tester.pumpWidget(_host(_sent()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Waiting'), findsWidgets);
  });

  testWidgets('offers the link alone when the draft failed', (tester) async {
    // draftReply can refuse to return a reply that lost the link. The seller
    // must still be able to get paid.
    final order = _sent().copyWith(draftedReply: null);
    await tester.pumpWidget(_host(order));
    await tester.pumpAndSettle();
    expect(find.textContaining('checkoutnow'), findsWidgets);
    expect(find.textContaining('Copy'), findsWidgets);
  });

  testWidgets('goes to orders', (tester) async {
    await tester.pumpWidget(_host(_sent()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to orders'));
    await tester.pumpAndSettle();
    expect(find.text('orders landed'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd app && flutter test test/reply_screen_test.dart
```

Expected: FAIL — `reply_screen.dart` does not exist.

- [ ] **Step 3: Write `app/lib/features/order/reply_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../models/order.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/selectable_chip.dart';

const _tones = [('Friendly', 'friendly'), ('Short', 'short'), ('Formal', 'formal')];

class ReplyScreen extends ConsumerStatefulWidget {
  const ReplyScreen({super.key});

  @override
  ConsumerState<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends ConsumerState<ReplyScreen> {
  String _tone = 'friendly';
  bool _busy = false;

  Future<void> _retone(Order order, String tone) async {
    setState(() {
      _tone = tone;
      _busy = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final reply = await ref
          .read(ordersRepositoryProvider)
          .regenerateReply(order.id, tone);
      ref
          .read(draftControllerProvider.notifier)
          .replace(order.copyWith(draftedReply: reply));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(draftControllerProvider);

    if (state is! DraftReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final order = state.order;
    // If the draft failed, the link alone still gets the seller paid.
    final toCopy = order.draftedReply ?? order.approvalUrl ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Reply ready')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SortedShape.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Link created for ${formatGbp(order.amountDueMinor)}',
                style: text.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Paste this back into the chat. The order turns paid on its own as soon as they pay.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: c.ink,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(22),
                            topRight: Radius.circular(22),
                            bottomLeft: Radius.circular(22),
                            bottomRight: Radius.circular(6),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (order.draftedReply != null)
                              Text(
                                order.draftedReply!,
                                style: text.bodyLarge?.copyWith(color: Colors.white),
                              )
                            else
                              Text(
                                'Sorted could not write the message this time. The link below still works — send it with a line of your own.',
                                style: text.bodyMedium?.copyWith(color: c.onDarkMuted),
                              ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: c.darkLink,
                                borderRadius: BorderRadius.circular(SortedShape.pillRadius),
                              ),
                              child: Text(
                                order.approvalUrl ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(color: c.accentCyan),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('Tone', style: text.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (label, value) in _tones)
                            SelectableChip(
                              label: label,
                              selected: _tone == value,
                              onTap: _busy ? () {} : () => _retone(order, value),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(color: c.warningText, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Waiting for ${order.buyerName ?? 'them'} to pay',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Copy reply',
                icon: Icons.copy_outlined,
                onPressed: _busy
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: toCopy));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied. Paste it into the chat.')),
                        );
                      },
              ),
              TextButton(
                onPressed: () {
                  ref.read(draftControllerProvider.notifier).clear();
                  context.go('/orders');
                },
                child: const Text('Go to orders'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add the route and an orders placeholder**

In `app/lib/router.dart`:

```dart
    GoRoute(path: '/order/reply', builder: (_, _) => const ReplyScreen()),
```

The shell already lists `/orders` as a tab but it is inert. Add a minimal route inside the shell so "Go to orders" lands somewhere, with the real screen arriving in Plan 4:

```dart
        GoRoute(
          path: '/orders',
          builder: (_, _) => const Center(child: Text('Orders arrive in week 4')),
        ),
```

and make the `/orders` tab navigable in `_NavShell.onDestinationSelected`.

- [ ] **Step 5: Run everything**

```bash
cd app && flutter test && flutter analyze && flutter build web --release
cd ../api && npm test && npm run typecheck
```

Expected: all green, web build succeeds.

- [ ] **Step 6: Commit**

```bash
cd /Users/bstar/Documents/development/apps/flutter/sorted
git add app
git commit -m "feat(app): add the Reply screen

The drafted message in a chat bubble with the checkout link visible, so
the seller sees exactly what they are about to send. Copy puts the
whole reply on the clipboard, tone chips ask the API to rewrite it.

When the draft failed its link check the screen says so and copies the
bare link instead: a seller who cannot get paid because the message
could not be written is a worse outcome than a plain link."
```

---

## Plan complete

**What exists at the end of Plan 3:** a seller pastes or uploads a DM, watches the model read it, answers whatever it could not work out, and gets a real PayPal checkout link with a ready-to-send reply. That is the spec's core flow and the spine of the demo video.

**Test count:** roughly 270. Node: existing 164 plus `parse-dm` 9 (+1 live), `match-catalogue` 12, `orders-domain` 15, `orders-route` 13, `paypal-client` 7, `paypal-orders` 11 (+2 live), `draft-reply` 10, `orders-confirm` 12. Flutter: existing 54 plus `order_model` 10, `orders_repository` 8, `intake_screen` 6, `reading_screen` 5, `draft_screen` 9, `reply_screen` 7.

**Deliberate scope calls:**
- **Direct REST for PayPal, not the agent toolkit.** Creating an order is a deterministic call; the toolkit exists to hand tools to an LLM, which is week 5's nudge loop. Using it here would be decoration.
- **No share-sheet handling.** Android intent and the iOS extension are week 5; Intake covers every platform meanwhile and is the only path the web build has.
- **No capture, no webhooks.** Week 4. An order ends this plan at `link_sent`.
- **Three live tests** (`parse-dm`, `paypal-orders` x2). Plan 2 shipped a request body the model rejected because every unit test faked the transport; these cost a few seconds and a fraction of a penny.

**Next:** Plan 4 — orders that track themselves. Webhooks, signature verification, capture, and the live flip to Paid that the video holds on.
