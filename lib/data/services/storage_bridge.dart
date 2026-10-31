import 'dart:io';

import 'package:flutter/services.dart';

/// Native storage helpers: shared-storage access and a folder picker.
abstract final class StorageBridge {
  static const MethodChannel _channel = MethodChannel(
    'thirhythm.flowingpod/storage',
  );

  /// Whether downloads may be written to shared storage.
  static Future<bool> hasAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasAccess') ?? false;
    } on Exception {
      return false;
    }
  }

  /// Opens the system permission flow, returning the resulting access state.
  static Future<bool> requestAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestAccess') ?? false;
    } on Exception {
      return false;
    }
  }

  /// Opens the system folder picker and returns the chosen absolute path.
  static Future<String?> pickDirectory() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('pickDirectory');
    } on Exception {
      return null;
    }
  }
}
