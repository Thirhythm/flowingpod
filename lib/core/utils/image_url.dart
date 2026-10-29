import 'secure_url.dart';

/// Helpers for the cover URLs of both supported services.
abstract final class ImageUrl {
  /// Ensures the URL uses HTTPS and optionally asks the CDN for a thumbnail at
  /// the displayed size.
  ///
  /// Bilibili images take a BFS suffix (`@360w_360h_1c.webp`); NetEase images
  /// take a `param` query instead.
  /// [height] defaults to [width]; pass it for artwork that is rendered in a
  /// non-square box so the download matches the displayed ratio.
  static String? resolve(String? url, {int? width, int? height}) {
    final result = SecureUrl.ensureHttps(url);
    if (result == null || result.isEmpty) return null;
    if (width == null) return result;

    final host = Uri.tryParse(result)?.host ?? '';
    if (_isBilibiliHost(host)) {
      if (!result.contains('@')) {
        return '$result@${width}w_${height ?? width}h_1c.webp';
      }
    } else if (_isNeteaseHost(host)) {
      if (!result.contains('param=')) {
        final separator = result.contains('?') ? '&' : '?';
        return '$result${separator}param=${width}y${height ?? width}';
      }
    }
    return result;
  }

  /// Requested pixel size for list thumbnails.
  static const int thumbnailWidth = 360;

  static bool _isBilibiliHost(String host) =>
      _matches(host, 'hdslb.com') ||
      _matches(host, 'bilivideo.com') ||
      _matches(host, 'bilivideo.cn');

  static bool _isNeteaseHost(String host) => _matches(host, '126.net');

  /// Matches [domain] and its subdomains, but not lookalikes such as
  /// `evil-hdslb.com`.
  static bool _matches(String host, String domain) =>
      host == domain || host.endsWith('.$domain');
}
