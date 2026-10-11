import { describe, expect, it } from 'vitest';
import {
  interimFromPayPalOrder,
  parseCustomId,
  parsePayPalEvent,
  reconcileAction,
  statusForEvent,
  verifyWebhookBody,
} from '../src/paypal/events.js';

describe('parsePayPalEvent', () => {
  it('reads the seller and order from an approved order', () => {
    const event = parsePayPalEvent({
      id: 'WH-1',
      event_type: 'CHECKOUT.ORDER.APPROVED',
      resource: {
        id: 'PP-1',
        purchase_units: [{ custom_id: 'seller-a:o1' }],
      },
    });
    expect(event).toMatchObject({
      id: 'WH-1',
      paypalOrderId: 'PP-1',
      customId: 'seller-a:o1',
    });
    expect(parseCustomId(event!.customId)).toEqual({ sellerId: 'seller-a', orderId: 'o1' });
  });

  it('reads a capture from the capture resource', () => {
    const event = parsePayPalEvent({
      id: 'WH-2',
      event_type: 'PAYMENT.CAPTURE.COMPLETED',
      resource: {
        id: 'CAP-1',
        status: 'COMPLETED',
        custom_id: 'seller-a:o1',
        amount: { currency_code: 'GBP', value: '42.00' },
        supplementary_data: { related_ids: { order_id: 'PP-1' } },
      },
    });
    expect(event).toMatchObject({
      captureId: 'CAP-1',
      paypalOrderId: 'PP-1',
      amountMinor: 4200,
    });
  });
});

describe('interimFromPayPalOrder', () => {
  it('treats a COMPLETED capture response as interim, not paid', () => {
    expect(
      interimFromPayPalOrder({
        status: 'COMPLETED',
        purchase_units: [{ payments: { captures: [{ id: 'CAP-1', status: 'COMPLETED' }] } }],
      }).interim,
    ).toBe('processing');
  });

  it('keeps a pending capture pending', () => {
    expect(
      interimFromPayPalOrder({
        status: 'COMPLETED',
        purchase_units: [{ payments: { captures: [{ id: 'CAP-1', status: 'PENDING' }] } }],
      }).interim,
    ).toBe('pending');
  });
});

describe('statusForEvent', () => {
  it('marks paid only for the completed capture webhook', () => {
    expect(statusForEvent('PAYMENT.CAPTURE.COMPLETED')).toBe('paid');
    expect(statusForEvent('CHECKOUT.ORDER.APPROVED')).toBeNull();
    expect(statusForEvent('PAYMENT.CAPTURE.REFUNDED')).toBeNull();
    expect(statusForEvent('CHECKOUT.PAYMENT-APPROVAL.REVERSED')).toBe('link_sent');
  });
});

describe('reconcileAction', () => {
  it('treats a completed capture as paid, because the webhook that would is missing', () => {
    expect(reconcileAction({
      status: 'COMPLETED',
      purchase_units: [{ payments: { captures: [{ id: 'CAP-1', status: 'COMPLETED' }] } }],
    })).toEqual({ kind: 'move', status: 'paid', captureId: 'CAP-1' });
  });

  it('asks for a capture when the buyer has approved and nothing was captured', () => {
    expect(reconcileAction({
      status: 'APPROVED',
      purchase_units: [{ custom_id: 'seller-a:o1' }],
    })).toEqual({ kind: 'capture' });
  });

  it('follows a pending or declined capture', () => {
    expect(reconcileAction({
      status: 'COMPLETED',
      purchase_units: [{ payments: { captures: [{ id: 'CAP-1', status: 'PENDING' }] } }],
    })).toEqual({ kind: 'move', status: 'pending', captureId: 'CAP-1' });
    expect(reconcileAction({
      status: 'COMPLETED',
      purchase_units: [{ payments: { captures: [{ id: 'CAP-1', status: 'DECLINED' }] } }],
    })).toEqual({ kind: 'move', status: 'declined', captureId: 'CAP-1' });
  });

  it('leaves an order the buyer has not approved', () => {
    expect(reconcileAction({ status: 'PAYER_ACTION_REQUIRED', purchase_units: [] })).toEqual({ kind: 'leave' });
  });
});

describe('verifyWebhookBody', () => {
  it('embeds the raw event without reordering it', () => {
    const raw = '{"z":1,"a":2}';
    const body = verifyWebhookBody(
      raw,
      {
        authAlgo: 'SHA256withRSA',
        certUrl: 'https://example.test/cert',
        transmissionId: 'tid',
        transmissionSig: 'sig',
        transmissionTime: '2026-10-11T12:00:00Z',
      },
      'wh-1',
    );
    expect(body).toContain(`"webhook_event":${raw}`);
    expect(JSON.parse(body).webhook_id).toBe('wh-1');
  });
});
