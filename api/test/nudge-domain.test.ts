import { describe, expect, it } from 'vitest';
import { Timestamp } from 'firebase-admin/firestore';
import { nudgeDue, nudgeRefusal, snoozeUntil } from '../src/domain/nudge.js';

const HOUR = 60 * 60 * 1000;
const NOW = Date.UTC(2026, 9, 19, 12);
const ago = (hours: number) => Timestamp.fromMillis(NOW - hours * HOUR);
const link = 'https://www.sandbox.paypal.com/checkoutnow?token=PP1';

const order = (extra: Record<string, unknown> = {}) => ({
  status: 'link_sent' as const,
  approvalUrl: link,
  linkSentAt: ago(25),
  nudge: { count: 0, lastSentAt: null, snoozedUntil: null },
  ...extra,
});

describe('nudgeRefusal', () => {
  it('allows a day-old unpaid link', () => {
    expect(nudgeRefusal(order(), NOW)).toBeNull();
  });

  it('asks for a little patience before a day is up', () => {
    expect(nudgeRefusal(order({ linkSentAt: ago(23) }), NOW)).toMatch(/less than a day/);
  });

  it.each([
    ['paid', /already paid/],
    ['cancelled', /cancelled/],
    ['expired', /expired/],
    ['processing', /paying for this right now/],
    ['pending', /paying for this right now/],
    ['draft', /no payment link/],
  ] as const)('never for a %s order', (status, message) => {
    expect(nudgeRefusal(order({ status }), NOW)).toMatch(message);
  });

  it('needs a link', () => {
    expect(nudgeRefusal(order({ approvalUrl: null }), NOW)).toMatch(/no payment link/);
    expect(nudgeRefusal(order({ linkSentAt: null }), NOW)).toMatch(/no payment link/);
  });
});

describe('nudgeDue', () => {
  it('brings up the first reminder at a day', () => {
    expect(nudgeDue(order({ linkSentAt: ago(23) }), NOW)).toBe(false);
    expect(nudgeDue(order({ linkSentAt: ago(24) }), NOW)).toBe(true);
  });

  it('the second waits for three days and a day after the first', () => {
    const once = (linkHours: number, lastHours: number) =>
      order({ linkSentAt: ago(linkHours), nudge: { count: 1, lastSentAt: ago(lastHours), snoozedUntil: null } });
    expect(nudgeDue(once(48, 20), NOW)).toBe(false);
    expect(nudgeDue(once(72, 20), NOW)).toBe(false);
    expect(nudgeDue(once(72, 24), NOW)).toBe(true);
  });

  it('stops after two', () => {
    expect(nudgeDue(order({ linkSentAt: ago(150), nudge: { count: 2, lastSentAt: ago(70) } }), NOW)).toBe(false);
  });

  it('stays quiet while snoozed, then comes back', () => {
    expect(nudgeDue(order({ nudge: { count: 0, snoozedUntil: Timestamp.fromMillis(NOW + HOUR) } }), NOW)).toBe(false);
    expect(nudgeDue(order({ nudge: { count: 0, snoozedUntil: Timestamp.fromMillis(NOW - HOUR) } }), NOW)).toBe(true);
  });

  it('copes with an order that has never had a nudge field', () => {
    expect(nudgeDue(order({ nudge: undefined }), NOW)).toBe(true);
  });

  it('is never due on a closed or paid order', () => {
    for (const status of ['paid', 'cancelled', 'expired'] as const) {
      expect(nudgeDue(order({ status, linkSentAt: ago(100) }), NOW)).toBe(false);
    }
  });

  it('snoozes until the same time tomorrow', () => {
    expect(snoozeUntil(NOW)).toBe(NOW + 24 * HOUR);
  });
});
