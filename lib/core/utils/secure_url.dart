/// Rewrites media URLs to HTTPS so the app can reject cleartext traffic.
abstract final class SecureUrl {
  /// Upgrades an `http://` URL, or a protocol-relative `//host` URL, to HTTPS.
  ///
  /// URLs that already use another scheme are returned unchanged; callers only
  /// ever pass URLs from the two supported services, whose CDNs serve HTTPS.
  static String? ensureHttps(String? url) {
    if (url == null || url.isEmpty) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('http://')) return 'https://${url.substring(7)}';
    return url;
  }
}
