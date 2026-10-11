const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Tue 13 Oct". Matches the API's formatUkDate, using UTC so the calendar
/// day does not shift. Anything that is not an ISO date is left as written.
String formatUkDate(String iso) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (match == null) return iso;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return iso;
  // DateTime.weekday is Monday=1 … Sunday=7. Sunday maps to index 0.
  return '${_weekdays[date.weekday % 7]} $day ${_months[month - 1]}';
}

/// Chip labels that are ISO dates, shown the same way as a stored date.
String displayDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return value;
  return formatUkDate(value);
}
