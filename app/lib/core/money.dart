/// Formats integer pence as the design writes it: £1,234.56.
/// Arithmetic belongs to the backend; this only renders.
String formatGbp(int minor) {
  final negative = minor < 0;
  final abs = minor.abs();
  final pounds = (abs ~/ 100).toString();
  final pence = (abs % 100).toString().padLeft(2, '0');
  final grouped = pounds.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${negative ? '-' : ''}£$grouped.$pence';
}

/// The orders list drops a trailing ".00", the way the order cards are drawn.
/// Anything with pence stays exact, so a £20.50 deposit is not shown as £21.
String formatGbpCompact(int minor) {
  final full = formatGbp(minor);
  if (full.endsWith('.00')) return full.substring(0, full.length - 3);
  return full;
}

/// Parses what a seller types into integer pence, or null if it is not a GBP
/// amount. Mirrors the backend's parseGbp so the two cannot disagree.
///
/// Strict on purpose. The permissive version — strip commas, parse a double —
/// turned "32,50" into £3,250.00, a hundredfold overcharge from the way much
/// of Europe writes a decimal point, and silently rounded "32.456" up.
int? parseGbpInput(String input) {
  final trimmed = input.trim();
  final match = RegExp(r'^£?(\d{1,3}(?:,\d{3})*|\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(trimmed);
  if (match == null) return null;

  final pounds = int.tryParse(match.group(1)!.replaceAll(',', ''));
  if (pounds == null) return null;

  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return pounds * 100 + int.parse(fraction);
}
