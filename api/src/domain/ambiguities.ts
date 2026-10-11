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
 * A size or a product clears only when that value is actually set, so a
 * seller cannot dismiss a price-changing question with a flag. Quantity
 * clears only when this resolve changes that line's qty: the model may
 * already have stored a guess. Everything else can also be closed by
 * listing the field in `resolvedAmbiguities`.
 */
export function stillOpen(
  ambiguity: Ambiguity,
  order: AmbiguityOrder,
  patch: AmbiguityPatch = {},
): boolean {
  const lineMatch = /^lineItems\[(\d+)\]\.(.+)$/.exec(ambiguity.field);
  if (lineMatch) {
    const line = order.lineItems[Number(lineMatch[1])];
    if (!line) return true;
    const prop = lineMatch[2];
    if (prop === 'variantIds') return line.variantIds.length === 0;
    if (prop === 'productId') return line.productId == null;
    if (prop === 'qty') {
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
