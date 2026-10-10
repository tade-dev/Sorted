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
