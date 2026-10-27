import 'package:flowingpod/core/models/recent_folder.dart';
import 'package:flowingpod/data/repositories/local_recent_folders_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecentFolder _folder(int id, {String? title, int mediaCount = 1}) =>
    RecentFolder(
      id: id,
      title: title ?? '收藏夹$id',
      cover: 'https://i0.hdslb.com/cover$id.jpg',
      mediaCount: mediaCount,
    );

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('RecentFolder', () {
    test('round trips through JSON and reopens its folder', () {
      final folder = _folder(7, title: '深夜电台', mediaCount: 3);
      final restored = RecentFolder.fromJson(folder.toJson());

      expect(restored, folder);
      expect(restored.cover, folder.cover);
      final reopened = restored.toFolder();
      expect(reopened.id, 7);
      expect(reopened.title, '深夜电台');
      expect(reopened.mediaCount, 3);
    });

    test('defaults the fields a bare payload leaves out', () {
      final folder = RecentFolder.fromJson(const {'id': '7'});

      expect(folder.id, 7);
      expect(folder.title, '未命名收藏夹');
      expect(folder.cover, '');
      expect(folder.mediaCount, 0);
    });
  });

  group('LocalRecentFoldersRepository', () {
    test('stores newest first and survives a reload', () async {
      final repository = LocalRecentFoldersRepository(prefs);
      await repository.record(_folder(1, title: '第一个'));
      await repository.record(_folder(2, title: '第二个'));

      final reloaded = LocalRecentFoldersRepository(prefs).load();
      expect(reloaded.map((folder) => folder.title), ['第二个', '第一个']);
    });

    test(
      're-recording a folder moves it to the front and refreshes it',
      () async {
        final repository = LocalRecentFoldersRepository(prefs);
        await repository.record(_folder(1, title: '旧标题'));
        await repository.record(_folder(2));
        await repository.record(_folder(1, title: '新标题'));

        final folders = repository.load();
        expect(folders, hasLength(2), reason: '同一个收藏夹不应出现两条记录');
        expect(folders.map((folder) => folder.id), [1, 2]);
        expect(folders.first.title, '新标题');
      },
    );

    test('caps the list so storage cannot grow without bound', () async {
      final repository = LocalRecentFoldersRepository(prefs);
      for (var id = 1; id <= 25; id++) {
        await repository.record(_folder(id));
      }

      final folders = repository.load();
      expect(folders, hasLength(20));
      expect(folders.first.id, 25);
      expect(folders.last.id, 6);
    });

    test('remove and clear', () async {
      final repository = LocalRecentFoldersRepository(prefs);
      await repository.record(_folder(1));
      await repository.record(_folder(2));

      await repository.remove(1);
      expect(repository.load().map((folder) => folder.id), [2]);

      await repository.clear();
      expect(repository.load(), isEmpty);
    });

    test('starts empty and tolerates a corrupted payload', () async {
      expect(LocalRecentFoldersRepository(prefs).load(), isEmpty);

      await prefs.setString('local_recent_folders_v1', 'not-json');
      expect(LocalRecentFoldersRepository(prefs).load(), isEmpty);
    });
  });
}
