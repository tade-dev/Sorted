import { describe, expect, it } from 'vitest';
import { Timestamp } from 'firebase-admin/firestore';
import { countToday, fallbackHighlights, londonDay } from '../src/domain/summary.js';
import { writeHighlights } from '../src/ai/daily_summary.js';
import type { ChatTransport } from '../src/ai/client.js';

const now = new Date('2026-10-15T09:00:00Z');
const ts = (iso: string) => Timestamp.fromDate(new Date(iso));

describe('countToday', () => {
  it('counts paid today, waiting and drafts from code', () => {
    const c = countToday(
      [
        { status: 'paid', amountDueMinor: 4800, paidAt: ts('2026-10-15T08:00:00Z') },
        { status: 'paid', amountDueMinor: 9700, paidAt: ts('2026-10-14T23:30:00Z') }, // 00:30 BST, today
        { status: 'paid', amountDueMinor: 1000, paidAt: ts('2026-10-14T22:30:00Z') }, // yesterday
        { status: 'link_sent', amountDueMinor: 2000 },
        { status: 'declined', amountDueMinor: 500 },
        { status: 'draft', amountDueMinor: 100 },
        { status: 'cancelled', amountDueMinor: 100 },
      ],
      now,
    );
    expect(c).toEqual({
      date: '2026-10-15', paidCount: 2, waitingCount: 2, draftCount: 1,
      paidTotalMinor: 14500, waitingTotalMinor: 2500,
    });
  });

  it('uses the UK day, not UTC', () => {
    expect(londonDay(new Date('2026-10-14T23:30:00Z'))).toBe('2026-10-15');
  });

  it('falls back to the plain line', () => {
    expect(fallbackHighlights({ date: 'x', paidCount: 3, waitingCount: 1, draftCount: 0, paidTotalMinor: 14500, waitingTotalMinor: 0 }))
      .toEqual(['3 paid, 1 waiting, £145.00 today']);
  });
});

const counts = { date: '2026-10-15', paidCount: 3, waitingCount: 1, draftCount: 0, paidTotalMinor: 14500, waitingTotalMinor: 4800 };
const reply = (highlights: string[]): ChatTransport => async () => ({ content: JSON.stringify({ highlights }) });

describe('writeHighlights', () => {
  it('returns the model highlights', async () => {
    expect(await writeHighlights(counts, reply(['Three orders paid, £145 in', 'One link still open']), 'm'))
      .toEqual(['Three orders paid, £145 in', 'One link still open']);
  });

  it('drops a highlight with an amount the code did not give', async () => {
    expect(await writeHighlights(counts, reply(['£200 taken today', 'One link still open']), 'm'))
      .toEqual(['One link still open']);
  });

  it('strips exclamation marks and markup', async () => {
    expect(await writeHighlights(counts, reply(['<b>Good day</b>!']), 'm')).toEqual(['Good day.']);
  });

  it('falls back when the model fails', async () => {
    const broken: ChatTransport = async () => { throw new Error('down'); };
    expect(await writeHighlights(counts, broken, 'm')).toEqual(['3 paid, 1 waiting, £145.00 today']);
  });

  it('skips the model on an empty day', async () => {
    let called = false;
    const t: ChatTransport = async () => { called = true; return { content: '{}' }; };
    expect(await writeHighlights({ ...counts, paidCount: 0, waitingCount: 0, paidTotalMinor: 0, waitingTotalMinor: 0 }, t, 'm')).toEqual([]);
    expect(called).toBe(false);
  });
});
