const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const;

/**
 * A date a buyer or seller can read. The design writes "Sat 10 Oct"; there is
 * no time on the order, so none is invented. An unparseable value is returned
 * unchanged rather than guessed.
 */
export function formatUkDate(iso: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!match) return iso;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return iso;
  }
  return `${WEEKDAYS[date.getUTCDay()]} ${day} ${MONTHS[month - 1]}`;
}

/** Replaces any ISO date the model echoed. Leaves the payment link alone. */
export function humaniseIsoDates(text: string): string {
  return text.replace(/\b\d{4}-\d{2}-\d{2}\b/g, (iso) => formatUkDate(iso));
}
