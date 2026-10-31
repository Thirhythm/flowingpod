import 'dart:io';

import 'package:flutter/services.dart';

/// Hands downloads to the Android foreground service that keeps running while
/// the app is backgrounded and reports progress in a notification.
abstract final class DownloadBridge {
  static const MethodChannel _channel = MethodChannel(
    'thirhythm.flowingpod/download',
  );

  /// Starts a background download. Returns `false` when the service could not
  /// be started.
  static Future<bool> enqueueDownload({
    required List<String> urls,
    required Map<String, String> headers,
    required String filePath,
    required String title,
    required String subtitle,
  }) async {
    if (!Platform.isAndroid) return false;
    await requestNotificationAccess();
    try {
      return await _channel.invokeMethod<bool>('enqueueDownload', {
            'urls': urls,
            'headers': headers,
            'filePath': filePath,
            'title': title,
            'subtitle': subtitle,
          }) ??
          false;
    } on Exception {
      return false;
    }
  }

  /// Asks for notification access so download progress is visible. The result
  /// is advisory: a denied prompt does not stop the download.
  static Future<bool> requestNotificationAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestNotificationAccess') ??
          true;
    } on Exception {
      return false;
    }
  }
}
