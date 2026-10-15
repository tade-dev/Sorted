import { Timestamp } from 'firebase-admin/firestore';
import { formatGbp } from './money.js';

/** Statuses still waiting on the buyer. Matches the Home card in the app. */
export const WAITING_STATUSES = new Set(['link_sent', 'processing', 'pending', 'declined']);

export type SummaryCounts = {
  date: string;
  paidCount: number;
  waitingCount: number;
  draftCount: number;
  paidTotalMinor: number;
  waitingTotalMinor: number;
};

export type SummaryOrder = {
  status: string;
  amountDueMinor: number;
  paidAt?: Timestamp | null;
  updatedAt?: Timestamp | null;
};

/** The seller's day is a UK day, whatever the server clock says. */
export function londonDay(d: Date): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/London',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(d);
}

/** Figures come from code, never from the model, so the money cannot be invented. */
export function countToday(orders: SummaryOrder[], now: Date): SummaryCounts {
  const date = londonDay(now);
  const c: SummaryCounts = {
    date, paidCount: 0, waitingCount: 0, draftCount: 0, paidTotalMinor: 0, waitingTotalMinor: 0,
  };
  for (const o of orders) {
    if (o.status === 'paid' && o.paidAt && londonDay(o.paidAt.toDate()) === date) {
      c.paidCount++;
      c.paidTotalMinor += o.amountDueMinor;
    } else if (WAITING_STATUSES.has(o.status)) {
      c.waitingCount++;
      c.waitingTotalMinor += o.amountDueMinor;
    } else if (o.status === 'draft') {
      c.draftCount++;
    }
  }
  return c;
}

/** "3 paid, 1 waiting, £145.00 today". Used whenever the model cannot help. */
export function fallbackHighlights(c: SummaryCounts): string[] {
  if (c.paidCount === 0 && c.waitingCount === 0) return [];
  return [`${c.paidCount} paid, ${c.waitingCount} waiting, ${formatGbp(c.paidTotalMinor)} today`];
}
