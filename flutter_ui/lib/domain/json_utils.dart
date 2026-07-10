/// Small, dependency-free helpers used by the manually serialized domain
/// models. Persisted state is treated as untrusted because older builds may
/// have written strings where the current schema writes numbers or booleans.
int jsonInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double jsonDouble(Object? value, [double fallback = 0]) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

bool jsonBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  switch (value?.toString().toLowerCase()) {
    case 'true':
    case '1':
    case 'yes':
      return true;
    case 'false':
    case '0':
    case 'no':
      return false;
    default:
      return fallback;
  }
}

String jsonString(Object? value, [String fallback = '']) =>
    value == null ? fallback : value.toString();

DateTime? jsonDateTime(Object? value) {
  if (value == null) return null;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return DateTime.tryParse(value.toString());
}

Map<String, Object?> jsonMap(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> jsonList(Object? value) =>
    value is List ? List<Object?>.from(value) : const <Object?>[];
