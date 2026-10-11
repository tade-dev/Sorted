import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import type { Ambiguity } from '../ai/schemas.js';
import { applyBlockingPolicy, ambiguityBlocks } from './ambiguities.js';
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
  return ambiguities.filter(ambiguityBlocks);
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
    ambiguities: input.ambiguities.map(applyBlockingPolicy),
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
