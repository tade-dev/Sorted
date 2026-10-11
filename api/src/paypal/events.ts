import { ApiError } from '../lib/errors.js';
import type { OrderStatus } from '../domain/orders.js';
import type { PayPalFetch } from './client.js';

export const HANDLED_EVENTS = new Set([
  'CHECKOUT.ORDER.APPROVED',
  'CHECKOUT.PAYMENT-APPROVAL.REVERSED',
  'PAYMENT.CAPTURE.COMPLETED',
  'PAYMENT.CAPTURE.PENDING',
  'PAYMENT.CAPTURE.DENIED',
  'PAYMENT.CAPTURE.REFUNDED',
]);

export type PayPalEvent = {
  id: string;
  eventType: string;
  /** Capture id when the resource is a capture, otherwise the PayPal order id. */
  resourceId: string | null;
  captureId: string | null;
  paypalOrderId: string | null;
  customId: string | null;
  amountMinor: number | null;
};

function str(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

export function amountToMinor(value: unknown): number | null {
  if (typeof value !== 'string' || !/^\d+\.\d{2}$/.test(value)) return null;
  return Number(value.replace('.', ''));
}

export function parseCustomId(value: string | null): { sellerId: string; orderId: string } | null {
  if (!value) return null;
  const sep = value.indexOf(':');
  if (sep <= 0 || sep === value.length - 1) return null;
  return { sellerId: value.slice(0, sep), orderId: value.slice(sep + 1) };
}

export function parsePayPalEvent(body: unknown): PayPalEvent | null {
  if (!body || typeof body !== 'object') return null;
  const event = body as Record<string, unknown>;
  const id = str(event.id);
  const eventType = str(event.event_type);
  if (!id || !eventType) return null;

  const resource = (event.resource ?? {}) as Record<string, unknown>;
  const resourceId = str(resource.id);
  const isCapture = eventType.startsWith('PAYMENT.CAPTURE.');

  if (isCapture) {
    const related = (resource.supplementary_data ?? {}) as Record<string, unknown>;
    const relatedIds = (related.related_ids ?? {}) as Record<string, unknown>;
    const amount = (resource.amount ?? {}) as Record<string, unknown>;
    return {
      id,
      eventType,
      resourceId,
      captureId: resourceId,
      paypalOrderId: str(relatedIds.order_id),
      customId: str(resource.custom_id),
      amountMinor: amountToMinor(amount.value),
    };
  }

  const units = Array.isArray(resource.purchase_units) ? resource.purchase_units : [];
  const unit = (units[0] ?? {}) as Record<string, unknown>;
  return {
    id,
    eventType,
    resourceId,
    captureId: null,
    paypalOrderId: resourceId,
    customId: str(unit.custom_id),
    amountMinor: null,
  };
}

/**
 * What the capture *response* may set. COMPLETED here is not Paid: that waits
 * for PAYMENT.CAPTURE.COMPLETED.
 */
export type CaptureInterim = 'link_sent' | 'processing' | 'pending' | 'declined';

export function interimFromPayPalOrder(body: unknown): { interim: CaptureInterim; captureId: string | null } {
  const order = (body ?? {}) as Record<string, unknown>;
  const units = Array.isArray(order.purchase_units) ? order.purchase_units : [];
  const unit = (units[0] ?? {}) as Record<string, unknown>;
  const payments = (unit.payments ?? {}) as Record<string, unknown>;
  const captures = Array.isArray(payments.captures) ? payments.captures : [];
  const capture = (captures[0] ?? {}) as Record<string, unknown>;
  const captureStatus = str(capture.status);
  const orderStatus = str(order.status);
  const captureId = str(capture.id);
  const status = captureStatus ?? orderStatus ?? '';

  if (!captureStatus && orderStatus !== 'COMPLETED') {
    return { interim: 'link_sent', captureId };
  }
  if (status === 'PENDING') return { interim: 'pending', captureId };
  if (status === 'DECLINED' || status === 'DENIED' || status === 'FAILED') {
    return { interim: 'declined', captureId };
  }
  if (status === 'COMPLETED' || orderStatus === 'COMPLETED') {
    return { interim: 'processing', captureId };
  }
  return { interim: 'link_sent', captureId };
}

/** The order status a webhook is allowed to move to. Refunds do not move it. */
export function statusForEvent(eventType: string): OrderStatus | null {
  switch (eventType) {
    case 'PAYMENT.CAPTURE.COMPLETED':
      return 'paid';
    case 'PAYMENT.CAPTURE.PENDING':
      return 'pending';
    case 'PAYMENT.CAPTURE.DENIED':
      return 'declined';
    case 'CHECKOUT.PAYMENT-APPROVAL.REVERSED':
      return 'link_sent';
    default:
      return null;
  }
}

export function paypalIssue(err: unknown): string | undefined {
  if (!(err instanceof ApiError) || !err.details || typeof err.details !== 'object') return undefined;
  const detail = (err.details as { detail?: unknown }).detail;
  return typeof detail === 'string' ? detail : undefined;
}

export function verifyWebhookBody(
  rawEvent: string,
  headers: {
    authAlgo: string;
    certUrl: string;
    transmissionId: string;
    transmissionSig: string;
    transmissionTime: string;
  },
  webhookId: string,
): string {
  const head = JSON.stringify({
    auth_algo: headers.authAlgo,
    cert_url: headers.certUrl,
    transmission_id: headers.transmissionId,
    transmission_sig: headers.transmissionSig,
    transmission_time: headers.transmissionTime,
    webhook_id: webhookId,
  });
  return `${head.slice(0, -1)},"webhook_event":${rawEvent}}`;
}

export async function capturePayPalOrder(
  call: PayPalFetch,
  paypalOrderId: string,
  orderId: string,
): Promise<unknown> {
  return call(`/v2/checkout/orders/${encodeURIComponent(paypalOrderId)}/capture`, {
    method: 'POST',
    requestId: `capture-${orderId}`,
    body: {},
  });
}

export async function getPayPalOrder(call: PayPalFetch, paypalOrderId: string): Promise<unknown> {
  return call(`/v2/checkout/orders/${encodeURIComponent(paypalOrderId)}`, { method: 'GET' });
}
