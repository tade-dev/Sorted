export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Coarse line for the buyer. Anything else stays off the page. */
export function buyerStatusLine(status: string | null): string | null {
  switch (status) {
    case 'paid':
      return "It's paid.";
    case 'pending':
      return 'PayPal still has it as pending.';
    case 'processing':
      return 'The shop is confirming it.';
    case 'declined':
      return 'PayPal declined it.';
    default:
      return null;
  }
}

export function buyerPage(opts: {
  title: string;
  headline: string;
  detail: string;
  statusLine?: string | null;
  link?: { href: string; label: string } | null;
}): string {
  const status = opts.statusLine
    ? `<p>${escapeHtml(opts.statusLine)}</p>`
    : '';
  const link = opts.link
    ? `<p><a href="${escapeHtml(opts.link.href)}">${escapeHtml(opts.link.label)}</a></p>`
    : '';
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>${escapeHtml(opts.title)}</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@700&amp;family=Plus+Jakarta+Sans:wght@400;600&amp;display=swap">
<style>
  body { margin: 0; background: #F5F7FA; color: #001C64; font-family: "Plus Jakarta Sans", sans-serif; }
  main { max-width: 28rem; margin: 0 auto; padding: 4.5rem 1.5rem 3rem; }
  .mark { margin: 0 0 1.5rem; font-weight: 600; font-size: 0.875rem; letter-spacing: 0.04em; color: #0070E0; }
  h1 { margin: 0; font-family: "Bricolage Grotesque", sans-serif; font-weight: 700; font-size: 1.75rem; letter-spacing: -0.03em; line-height: 1.25; }
  p { margin: 1rem 0 0; color: #515A6B; font-size: 1rem; line-height: 1.5; }
  a { color: #0070E0; font-weight: 600; }
</style>
</head>
<body>
<main>
  <p class="mark">Sorted</p>
  <h1>${escapeHtml(opts.headline)}</h1>
  <p>${escapeHtml(opts.detail)}</p>
  ${status}
  ${link}
</main>
</body>
</html>
`;
}
