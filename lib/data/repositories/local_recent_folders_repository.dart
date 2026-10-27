import 'dart:convert';

import 'package:flowingpod/core/models/recent_folder.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device record of the favourite folders played from, newest first.
///
/// It feeds the home page's 最近播放 shortcuts in every session, signed in or
/// not: the folders themselves live on the account, but which ones were played
/// is app activity and has to survive logging out.
class LocalRecentFoldersRepository {
  LocalRecentFoldersRepository(this._prefs);

  static const String _key = 'local_recent_folders_v1';
  static const int _limit = 20;

  final SharedPreferences _prefs;

  List<RecentFolder> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            RecentFolder.fromJson(item.map((k, v) => MapEntry('$k', v))),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Moves [folder] to the front and returns the updated list.
  ///
  /// Recording the same folder again refreshes its cover and count instead of
  /// adding a second shortcut.
  Future<List<RecentFolder>> record(RecentFolder folder) async {
    final folders = [...load()]..removeWhere((item) => item.id == folder.id);
    folders.insert(0, folder);
    if (folders.length > _limit) {
      folders.removeRange(_limit, folders.length);
    }
    await _save(folders);
    return folders;
  }

  Future<List<RecentFolder>> remove(int folderId) async {
    final folders = [...load()]..removeWhere((item) => item.id == folderId);
    await _save(folders);
    return folders;
  }

  Future<void> clear() => _prefs.remove(_key);

  Future<void> _save(List<RecentFolder> folders) => _prefs.setString(
    _key,
    jsonEncode([for (final folder in folders) folder.toJson()]),
  );
}
