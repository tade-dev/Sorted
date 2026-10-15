import { z } from 'zod';

/** Integer pence, never negative. Mirrors money.ts's Minor. */
const minor = z.number().int().nonnegative();
/** Signed integer pence: a variant may legitimately reduce the price. */
const signedMinor = z.number().int();

export const ambiguitySchema = z.object({
  field: z.string().min(1),
  kind: z.enum([
    'missing',
    'unclear',
    'unknown_product',
    'price_conflict',
    'qty_unclear',
  ]),
  /** Seller-facing, answerable in one tap. Never model-speak. */
  question: z.string().min(1).max(160),
  options: z.array(z.string()).default([]),
  blocking: z.boolean().default(true),
});
export type Ambiguity = z.infer<typeof ambiguitySchema>;

const variantSchema = z.object({
  axis: z.enum(['size', 'colour', 'flavour', 'other']),
  label: z.string().min(1).max(40),
  priceDeltaMinor: signedMinor,
});

export const productCandidateSchema = z.object({
  name: z.string().min(1).max(60),
  description: z.string().max(240),
  /** null when no price was readable — the seller supplies it before saving. */
  basePriceMinor: minor.nullable(),
  variants: z.array(variantSchema).max(12),
  confidence: z.number().min(0).max(1),
  ambiguities: z.array(ambiguitySchema).default([]),
  /**
   * 0-based index of the uploaded photo this product is clearest in, so the
   * app can attach that photo to the saved product. Null when unsure.
   */
  photoIndex: z.number().int().min(0).nullable().default(null),
});
export type ProductCandidate = z.infer<typeof productCandidateSchema>;

export const catalogueExtractionSchema = z.object({
  candidates: z.array(productCandidateSchema).max(20),
});
export type CatalogueExtraction = z.infer<typeof catalogueExtractionSchema>;

const isoDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'must be an ISO date (YYYY-MM-DD)');

export const dmOrderSchema = z.object({
  buyerName: z.string().max(80).nullable(),
  buyerHandle: z.string().max(80).nullable(),
  buyerEmail: z.string().email().nullable(),
  channel: z.enum(['instagram', 'tiktok', 'whatsapp', 'other', 'unknown']),
  lineItems: z
    .array(
      z.object({
        /** The buyer's own words, quoted. */
        nameRaw: z.string().min(1).max(200),
        qty: z.number().int().min(1).max(999),
        variantLabels: z.array(z.string().max(40)).default([]),
      }),
    )
    .max(30),
  fulfilment: z.object({
    mode: z.enum(['collection', 'delivery', 'unknown']),
    date: isoDate.nullable(),
    notes: z.string().max(300).nullable(),
  }),
  depositRequestedMinor: minor.nullable(),
  ambiguities: z.array(ambiguitySchema).default([]),
  overallConfidence: z.number().min(0).max(1),
});
export type DmOrder = z.infer<typeof dmOrderSchema>;

export const replyDraftSchema = z.object({
  reply: z.string().min(1).max(1000),
});
export type ReplyDraft = z.infer<typeof replyDraftSchema>;

export const nudgeDraftSchema = z.object({
  text: z.string().max(500),
  recommendChannel: z.enum(['paypal_invoice', 'manual_copy']),
  /** An agent that knows when not to chase is more credible than one that always fires. */
  shouldSkip: z.boolean(),
  skipReason: z.string().max(200).nullable(),
});
export type NudgeDraft = z.infer<typeof nudgeDraftSchema>;

export const dailySummarySchema = z.object({
  highlights: z.array(z.string().max(70)).max(3),
});
export type DailySummary = z.infer<typeof dailySummarySchema>;
