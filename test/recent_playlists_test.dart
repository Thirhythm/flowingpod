import 'dart:convert';

import 'package:flowingpod/core/models/playlist_ref.dart';
import 'package:flowingpod/core/models/recent_playlist.dart';
import 'package:flowingpod/data/repositories/local_recent_playlists_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecentPlaylist _playlist(
  String id, {
  PlaylistSource source = PlaylistSource.bilibili,
  String? title,
  int count = 1,
}) => RecentPlaylist(
  source: source,
  id: id,
  title: title ?? '歌单$id',
  cover: 'https://i0.hdslb.com/cover$id.jpg',
  count: count,
);

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('RecentPlaylist', () {
    test('round trips through JSON and reopens its playlist', () {
      final playlist = _playlist('7', title: '深夜电台', count: 3);
      final restored = RecentPlaylist.fromJson(playlist.toJson());

      expect(restored, playlist);
      expect(restored.cover, playlist.cover);
      final reopened = restored.toRef();
      expect(reopened.id, '7');
      expect(reopened.source, PlaylistSource.bilibili);
      expect(reopened.title, '深夜电台');
      expect(reopened.count, 3);
    });

    test('defaults the fields a bare payload leaves out', () {
      final playlist = RecentPlaylist.fromJson(const {'id': '7'});

      expect(playlist.id, '7');
      expect(playlist.source, PlaylistSource.bilibili);
      expect(playlist.title, '未命名歌单');
      expect(playlist.cover, '');
      expect(playlist.count, 0);
    });

    test('keeps the same id from different sources apart', () {
      final local = RecentPlaylist.fromJson(
        _playlist('1', source: PlaylistSource.local).toJson(),
      );
      final netease = RecentPlaylist.fromJson(
        _playlist('1', source: PlaylistSource.netease).toJson(),
      );

      expect(local, isNot(netease));
    });
  });

  group('LocalRecentPlaylistsRepository', () {
    test('stores newest first and survives a reload', () async {
      final repository = LocalRecentPlaylistsRepository(prefs);
      await repository.record(_playlist('1', title: '第一个'));
      await repository.record(_playlist('2', title: '第二个'));

      final reloaded = LocalRecentPlaylistsRepository(prefs).load();
      expect(reloaded.map((playlist) => playlist.title), ['第二个', '第一个']);
    });

    test('records playlists from every source', () async {
      final repository = LocalRecentPlaylistsRepository(prefs);
      await repository.record(_playlist('1', source: PlaylistSource.local));
      await repository.record(_playlist('1', source: PlaylistSource.netease));

      final playlists = repository.load();
      expect(playlists, hasLength(2), reason: '不同来源的同 id 歌单应各自保留');
      expect(playlists.map((playlist) => playlist.source), [
        PlaylistSource.netease,
        PlaylistSource.local,
      ]);
    });

    test(
      're-recording a playlist moves it to the front and refreshes it',
      () async {
        final repository = LocalRecentPlaylistsRepository(prefs);
        await repository.record(_playlist('1', title: '旧标题'));
        await repository.record(_playlist('2'));
        await repository.record(_playlist('1', title: '新标题'));

        final playlists = repository.load();
        expect(playlists, hasLength(2), reason: '同一个歌单不应出现两条记录');
        expect(playlists.map((playlist) => playlist.id), ['1', '2']);
        expect(playlists.first.title, '新标题');
      },
    );

    test('caps the list so storage cannot grow without bound', () async {
      final repository = LocalRecentPlaylistsRepository(prefs);
      for (var id = 1; id <= 25; id++) {
        await repository.record(_playlist('$id'));
      }

      final playlists = repository.load();
      expect(playlists, hasLength(20));
      expect(playlists.first.id, '25');
      expect(playlists.last.id, '6');
    });

    test('remove and clear', () async {
      final repository = LocalRecentPlaylistsRepository(prefs);
      await repository.record(_playlist('1'));
      await repository.record(_playlist('2'));

      await repository.remove(_playlist('1'));
      expect(repository.load().map((playlist) => playlist.id), ['2']);

      await repository.clear();
      expect(repository.load(), isEmpty);
    });

    test('starts empty and tolerates a corrupted payload', () async {
      expect(LocalRecentPlaylistsRepository(prefs).load(), isEmpty);

      await prefs.setString('local_recent_folders_v1', 'not-json');
      expect(LocalRecentPlaylistsRepository(prefs).load(), isEmpty);
    });

    test('reads the favourites payload stored by older builds', () async {
      await prefs.setString(
        'local_recent_folders_v1',
        jsonEncode([
          {'id': 7, 'title': '深夜电台', 'cover': 'x', 'mediaCount': 3},
        ]),
      );

      final restored = LocalRecentPlaylistsRepository(prefs).load();
      expect(restored, hasLength(1));
      expect(restored.single.id, '7');
      expect(restored.single.source, PlaylistSource.bilibili);
      expect(restored.single.count, 3);
    });
  });
}
