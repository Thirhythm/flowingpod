/// Defensive JSON coercion helpers.
///
/// The Bilibili API is inconsistent about number types (numbers are sometimes
/// returned as strings) and occasionally omits fields, so every parse goes
/// through these helpers instead of direct casts.
abstract final class JsonUtils {
  static String string(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is String) return value.isEmpty ? fallback : value;
    return '$value';
  }

  static String? nullableString(Object? value) {
    if (value == null) return null;
    final text = value is String ? value : '$value';
    return text.isEmpty ? null : text;
  }

  static int integer(Object? value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool boolean(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return fallback;
  }

  static double decimal(Object? value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Reads a nested list of numbers, skipping entries of the wrong shape.
  static List<double> doubles(Object? value) {
    if (value is! List) return const [];
    return [for (final item in value) if (item is num) item.toDouble()];
  }

  /// Reads a nested map, returning an empty map when absent.
  static Map<String, dynamic> map(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', item));
    }
    return const {};
  }

  /// Reads a nested list of maps, skipping entries of the wrong shape.
  static List<Map<String, dynamic>> list(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map) item.map((key, entry) => MapEntry('$key', entry)),
    ];
  }

  /// Reads a list of non-empty strings, ignoring entries of another type.
  static List<String> strings(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String && item.isNotEmpty) item,
    ];
  }

  /// Turns a second duration into a [Duration].
  static Duration durationFromSeconds(Object? value) =>
      Duration(seconds: integer(value));

  /// Parses the many duration encodings returned by the API: seconds as a
  /// number, seconds as a string, or `mm:ss` / `hh:mm:ss`.
  static Duration flexibleDuration(Object? value) {
    if (value is num) return Duration(seconds: value.toInt());
    if (value is! String || value.isEmpty) return Duration.zero;
    if (!value.contains(':')) {
      return Duration(seconds: int.tryParse(value) ?? 0);
    }
    final segments = value.split(':').map((s) => int.tryParse(s) ?? 0).toList();
    var seconds = 0;
    for (final segment in segments) {
      seconds = seconds * 60 + segment;
    }
    return Duration(seconds: seconds);
  }
}
