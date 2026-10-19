import type { OrderDoc } from './orders.js';

/**
 * Nudge timings, in one place, from the design spec's lifecycle table: the
 * first reminder is due a day after the link went out, the second at three
 * days, and there is no third. A buyer chased three times is being nagged.
 */
export const NUDGE_DUE_HOURS = [24, 72] as const;
export const MAX_NUDGES = NUDGE_DUE_HOURS.length;
/** Never two reminders within a day of each other, whatever the thresholds say. */
export const NUDGE_GAP_HOURS = 24;
/** "Remind me tomorrow". */
export const NUDGE_SNOOZE_HOURS = 24;

const HOUR_MS = 60 * 60 * 1000;

export function millis(value: unknown): number | null {
  if (!value || typeof value !== 'object' || !('toMillis' in value)) return null;
  const ms = (value as { toMillis: () => number }).toMillis();
  return typeof ms === 'number' && !Number.isNaN(ms) ? ms : null;
}

export type NudgeState = {
  count?: number;
  lastSentAt?: unknown;
  snoozedUntil?: unknown;
};

/**
 * Whether a nudge may be drafted at all. Only a sent, unpaid link a day old
 * qualifies: before that it is not late, and anything else is either not
 * sent, already moving at PayPal, or closed. Reasons are the seller's words.
 */
export function nudgeRefusal(
  order: Pick<OrderDoc, 'status' | 'approvalUrl'> & { linkSentAt?: unknown },
  nowMs: number,
): string | null {
  switch (order.status) {
    case 'link_sent':
      break;
    case 'paid':
      return 'That order is already paid.';
    case 'cancelled':
    case 'expired':
      return `That order is ${order.status}, so there is nothing to chase.`;
    case 'processing':
    case 'pending':
      return 'The buyer is paying for this right now.';
    case 'draft':
      return 'That order has no payment link yet.';
    default:
      return 'That order cannot be nudged.';
  }
  if (!order.approvalUrl) return 'That order has no payment link yet.';
  const sent = millis(order.linkSentAt);
  if (sent === null) return 'That order has no payment link yet.';
  if (nowMs - sent < NUDGE_DUE_HOURS[0] * HOUR_MS) {
    return 'The link went out less than a day ago. Give them a little longer first.';
  }
  return null;
}

/**
 * Whether Sorted should bring the order up by itself: on Home, and in the
 * hourly sweep. Stricter than nudgeRefusal, which is what the seller may ask
 * for; this is what Sorted volunteers.
 */
export function nudgeDue(
  order: Pick<OrderDoc, 'status' | 'approvalUrl'> & { linkSentAt?: unknown; nudge?: NudgeState | null },
  nowMs: number,
): boolean {
  if (nudgeRefusal(order, nowMs) !== null) return false;
  const nudge = order.nudge ?? {};
  const count = typeof nudge.count === 'number' ? nudge.count : 0;
  if (count >= MAX_NUDGES) return false;
  const sent = millis(order.linkSentAt)!;
  if (nowMs - sent < NUDGE_DUE_HOURS[count]! * HOUR_MS) return false;
  const last = millis(nudge.lastSentAt);
  if (last !== null && nowMs - last < NUDGE_GAP_HOURS * HOUR_MS) return false;
  const snoozed = millis(nudge.snoozedUntil);
  if (snoozed !== null && nowMs < snoozed) return false;
  return true;
}

export function snoozeUntil(nowMs: number): number {
  return nowMs + NUDGE_SNOOZE_HOURS * HOUR_MS;
}
