/// Error thrown when a supported service responds with a non-zero business
/// `code`, or when the transport layer fails.
class BiliApiException implements Exception {
  const BiliApiException({
    required this.code,
    required this.message,
    this.path,
  });

  /// Upstream business code (`-1`, `-101`, `-400`, …).
  final int code;

  /// Human readable message, either from the API or synthesised locally.
  final String message;

  /// Request path that produced the error, for diagnostics.
  final String? path;

  @override
  String toString() =>
      'BiliApiException(code: $code, message: $message'
      '${path == null ? '' : ', path: $path'})';
}
