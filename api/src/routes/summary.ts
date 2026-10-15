import { Router } from 'express';
import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { requireSeller, type TokenVerifier } from '../lib/auth.js';
import type { ChatTransport } from '../ai/client.js';
import { writeHighlights } from '../ai/daily_summary.js';
import { countToday, type SummaryCounts, type SummaryOrder } from '../domain/summary.js';

const STALE_MS = 15 * 60 * 1000;

type StoredSummary = SummaryCounts & { highlights: string[]; generatedAt: Timestamp };

function same(a: SummaryCounts, b: SummaryCounts): boolean {
  return a.paidCount === b.paidCount && a.waitingCount === b.waitingCount &&
    a.draftCount === b.draftCount && a.paidTotalMinor === b.paidTotalMinor &&
    a.waitingTotalMinor === b.waitingTotalMinor;
}

export function summaryRouter(deps: {
  db: Firestore;
  verify: TokenVerifier;
  transport: ChatTransport;
  model: string;
  now?: () => Date;
}): Router {
  const router = Router();

  router.get('/summary/today', requireSeller(deps.verify), async (req, res, next) => {
    try {
      const sellerId = req.sellerId!;
      const now = (deps.now ?? (() => new Date()))();
      const snap = await deps.db.collection(`sellers/${sellerId}/orders`).get();
      const orders = snap.docs.map((d) => d.data() as SummaryOrder);
      const counts = countToday(orders, now);

      const ref = deps.db.doc(`sellers/${sellerId}/summaries/${counts.date}`);
      const cached = (await ref.get()).data() as StoredSummary | undefined;
      const generatedMs = cached?.generatedAt?.toMillis() ?? 0;
      const changedSince = orders.some((o) => (o.updatedAt?.toMillis() ?? 0) > generatedMs);
      const fresh = cached !== undefined && now.getTime() - generatedMs < STALE_MS &&
        !changedSince && same(cached, counts);

      let highlights: string[];
      let generatedAt: Date;
      if (fresh) {
        highlights = cached.highlights;
        generatedAt = cached.generatedAt.toDate();
      } else {
        highlights = await writeHighlights(counts, deps.transport, deps.model);
        generatedAt = now;
        await ref.set({ ...counts, highlights, generatedAt: Timestamp.fromDate(now), writtenAt: FieldValue.serverTimestamp() });
      }

      res.json({ summary: { ...counts, highlights, generatedAt: generatedAt.toISOString() } });
    } catch (e) {
      next(e);
    }
  });

  return router;
}
