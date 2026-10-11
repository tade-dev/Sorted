/// Reads a time from either the API (ISO-8601) or a Firestore snapshot
/// (Timestamp, or the `{seconds, nanoseconds}` map). A value we cannot read
/// becomes null so one bad field does not blank the whole order list.
DateTime? dateTimeFromJson(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
  if (value is num) {
    final raw = value.toInt();
    final millis = raw.abs() > 100000000000 ? raw : raw * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
  if (value is Map) {
    final seconds = _asInt(value['_seconds'] ?? value['seconds']);
    if (seconds == null) return null;
    final nanos = _asInt(value['_nanoseconds'] ?? value['nanoseconds']) ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000 + nanos ~/ 1000000,
      isUtc: true,
    );
  }
  try {
    final dynamic stamp = value;
    final result = stamp.toDate();
    if (result is DateTime) return result;
  } catch (_) {}
  return null;
}

String? dateTimeToJson(DateTime? value) => value?.toUtc().toIso8601String();

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}
