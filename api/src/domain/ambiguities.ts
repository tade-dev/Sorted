import type { Ambiguity } from '../ai/schemas.js';

/**
 * These do not change what the buyer pays or which product is being made.
 * The spec leaves buyer identity nullable, and the drafted reply already
 * falls back when the name is missing, so a missing name must not trap
 * "Create PayPal link".
 */
export const OPTIONAL_IDENTITY_FIELDS = new Set([
  'buyerName',
  'buyerHandle',
  'buyerEmail',
  'buyer',
  'customerName',
  'channel',
  'fulfilment.notes',
  'fulfillment.notes',
]);

export type AmbiguityOrder = {
  lineItems: {
    id: string;
    variantIds: string[];
    productId: string | null;
    qty: number;
  }[];
  buyerName: string | null;
  buyerHandle: string | null;
  buyerEmail: string | null;
  fulfilment: { mode: string; date: string | null; notes: string | null };
  depositMinor: number | null;
};

export type AmbiguityPatch = {
  lineItems?: { id: string; qty?: number }[];
  depositMinor?: number | null;
  resolvedAmbiguities?: string[];
};

export function ambiguityBlocks(ambiguity: Ambiguity): boolean {
  if (!ambiguity.blocking) return false;
  if ((ambiguity as { resolved?: boolean }).resolved) return false;
  return !OPTIONAL_IDENTITY_FIELDS.has(ambiguity.field);
}

/** The model defaults `blocking` to true. Optional identity fields are not. */
export function applyBlockingPolicy(ambiguity: Ambiguity): Ambiguity {
  if (OPTIONAL_IDENTITY_FIELDS.has(ambiguity.field)) {
    return { ...ambiguity, blocking: false };
  }
  return ambiguity;
}

/** Line props that are really "which variant", whatever the model called them. */
const VARIANT_PROPS = new Set([
  'variantids',
  'variantid',
  'variantlabels',
  'variantlabel',
  'variant',
  'variants',
  'size',
  'sizes',
]);

function lineField(field: string): { index: number; prop: string } | null {
  const match = /^lineItems\[(\d+)\]\.(.+)$/.exec(field);
  if (!match?.[1] || !match[2]) return null;
  return { index: Number(match[1]), prop: match[2].toLowerCase() };
}

function isVariantProp(prop: string): boolean {
  return VARIANT_PROPS.has(prop);
}

function isDateField(field: string): boolean {
  return (
    field === 'date' ||
    field === 'fulfilment' ||
    field === 'fulfillment' ||
    field === 'collectionDate' ||
    field === 'deliveryDate' ||
    field.endsWith('.date')
  );
}

function isDepositField(field: string): boolean {
  return (
    field === 'depositMinor' ||
    field === 'depositRequestedMinor' ||
    field === 'deposit'
  );
}

function blank(value: string | null | undefined): boolean {
  return value == null || value.trim() === '';
}

/**
 * True while the seller has not answered this question.
 *
 * A variant question, including one the model named `size` or
 * `variantLabels` rather than `variantIds`, clears once that line has a
 * variant. Quantity clears only when this resolve changes that line's qty:
 * the model may already have stored a guess. Any line question also clears
 * when the seller lists its field in `resolvedAmbiguities`.
 */
export function stillOpen(
  ambiguity: Ambiguity,
  order: AmbiguityOrder,
  patch: AmbiguityPatch = {},
): boolean {
  const parsed = lineField(ambiguity.field);
  if (parsed) {
    if (patch.resolvedAmbiguities?.includes(ambiguity.field)) return false;
    const line = order.lineItems[parsed.index];
    if (!line) return true;
    if (isVariantProp(parsed.prop)) return line.variantIds.length === 0;
    if (parsed.prop === 'productid') return line.productId == null;
    if (parsed.prop === 'qty') {
      const edit = patch.lineItems?.find((item) => item.id === line.id);
      return edit?.qty == null;
    }
    return true;
  }

  if (patch.resolvedAmbiguities?.includes(ambiguity.field)) return false;

  if (ambiguity.field === 'buyerHandle') return blank(order.buyerHandle);
  if (ambiguity.field === 'buyerEmail') return blank(order.buyerEmail);
  if (
    ambiguity.field === 'fulfilment.notes' ||
    ambiguity.field === 'fulfillment.notes'
  ) {
    return blank(order.fulfilment.notes);
  }
  if (ambiguity.field === 'channel') return false;
  if (
    ambiguity.field === 'buyerName' ||
    ambiguity.field === 'buyer' ||
    ambiguity.field === 'customerName'
  ) {
    return blank(order.buyerName);
  }
  if (isDateField(ambiguity.field)) return blank(order.fulfilment.date);
  if (
    ambiguity.field === 'fulfilment.mode' ||
    ambiguity.field === 'fulfillment.mode'
  ) {
    return !order.fulfilment.mode || order.fulfilment.mode === 'unknown';
  }
  if (isDepositField(ambiguity.field)) {
    if (patch.depositMinor !== undefined) return false;
    return order.depositMinor == null;
  }
  return true;
}

type VariantLine = { variantIds: string[]; productId: string | null };
type VariantProduct = { id: string; variants: { active: boolean }[] };

/**
 * Drops model questions about size or variant once matching has already
 * chosen one: the line has variant ids, or the product has a single live
 * variant. A real choice between sizes is left for the seller.
 */
export function withoutSettledVariantQuestions<T extends { field: string }>(
  ambiguities: T[],
  lines: VariantLine[],
  products: VariantProduct[],
): T[] {
  return ambiguities.filter((ambiguity) => {
    const parsed = lineField(ambiguity.field);
    if (!parsed || !isVariantProp(parsed.prop)) return true;
    const line = lines[parsed.index];
    if (!line) return true;
    if (line.variantIds.length > 0) return false;
    const product = products.find((item) => item.id === line.productId);
    if (!product) return true;
    return product.variants.filter((variant) => variant.active).length !== 1;
  });
}
