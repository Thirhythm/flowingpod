import 'dart:io';

/// Filesystem locations used by the app.
abstract final class StoragePaths {
  /// Shared Music folder on Android's primary storage.
  static const String androidMusicDirectory = '/storage/emulated/0/Music';

  /// Where downloads go until the user picks another folder.
  static String get defaultMusicDirectory => Platform.isAndroid
      ? androidMusicDirectory
      : '${Directory.current.path}${Platform.pathSeparator}Music';
}
