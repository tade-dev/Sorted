import { dailySummarySchema } from './schemas.js';
import { generateStructured, type ChatTransport } from './client.js';
import { formatGbp } from '../domain/money.js';
import { fallbackHighlights, type SummaryCounts } from '../domain/summary.js';

export const SUMMARY_SYSTEM = [
  "Two or three short highlights for a seller's home screen.",
  'Use only the numbers given. No advice, no exclamation marks.',
  'UK English, no hype, no emoji. Each highlight under 70 characters.',
].join(' ');

export const SUMMARY_JSON_SCHEMA: Record<string, unknown> = {
  type: 'object',
  additionalProperties: false,
  required: ['highlights'],
  properties: { highlights: { type: 'array', items: { type: 'string' }, maxItems: 3 } },
};

const MONEY = /£\s?[\d,]+(?:\.\d{2})?/g;

/**
 * Prose only. A highlight that names an amount the code did not give is
 * dropped, so the line under the card never disagrees with the card.
 */
export async function writeHighlights(
  counts: SummaryCounts,
  transport: ChatTransport,
  model: string,
): Promise<string[]> {
  if (counts.paidCount === 0 && counts.waitingCount === 0 && counts.draftCount === 0) return [];
  const allowed = new Set(
    [counts.paidTotalMinor, counts.waitingTotalMinor].flatMap((m) => {
      const full = formatGbp(m);
      return [full, full.replace(/\.00$/, '')];
    }),
  );
  try {
    const { highlights } = await generateStructured(
      {
        schemaName: 'daily_summary',
        schema: dailySummarySchema,
        jsonSchema: SUMMARY_JSON_SCHEMA,
        system: SUMMARY_SYSTEM,
        text: [
          `Paid today: ${counts.paidCount} orders, ${formatGbp(counts.paidTotalMinor)}`,
          `Waiting for payment: ${counts.waitingCount} orders, ${formatGbp(counts.waitingTotalMinor)}`,
          `Drafts not sent yet: ${counts.draftCount}`,
        ].join('\n'),
      },
      transport,
      model,
    );
    const clean = highlights
      .map((h) => h.replace(/<[^>]*>/g, '').replace(/!/g, '.').trim())
      .filter((h) => h.length > 0)
      .filter((h) => (h.match(MONEY) ?? []).every((m) => allowed.has(m.replace(/\s/g, ''))));
    return clean.length > 0 ? clean : fallbackHighlights(counts);
  } catch {
    return fallbackHighlights(counts);
  }
}
