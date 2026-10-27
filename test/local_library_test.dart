import 'dart:convert';

import 'package:flowingpod/core/models/local_playlist.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/data/repositories/local_history_repository.dart';
import 'package:flowingpod/data/repositories/local_playlist_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MediaTrack _track(String bvid, int cid, {String? title}) => MediaTrack(
  bvid: bvid,
  aid: 7,
  cid: cid,
  title: title ?? '曲目$cid',
  artist: 'UP主',
  cover: '',
);

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('我喜欢的音乐', () {
    test('stores newest first and survives a reload', () async {
      final repository = LocalPlaylistRepository(prefs);
      await repository.addTracks(LocalPlaylist.likedId, [
        _track('BV1', 1, title: '第一首'),
      ]);
      await repository.addTracks(LocalPlaylist.likedId, [
        _track('BV2', 2, title: '第二首'),
      ]);

      final reloaded = LocalPlaylistRepository(prefs).likedTracks;
      expect(reloaded.map((track) => track.title), ['第二首', '第一首']);
      expect(reloaded.first.cid, 2);
    });

    test(
      're-adding a track moves it to the front without duplicating',
      () async {
        final repository = LocalPlaylistRepository(prefs);
        await repository.addTracks(LocalPlaylist.likedId, [_track('BV1', 1)]);
        await repository.addTracks(LocalPlaylist.likedId, [_track('BV2', 2)]);
        await repository.addTracks(LocalPlaylist.likedId, [_track('BV1', 1)]);

        final tracks = repository.likedTracks;
        expect(tracks, hasLength(2));
        expect(tracks.map((track) => track.id), ['BV1:1', 'BV2:2']);
      },
    );

    test('merges a placeholder with its resolved twin', () async {
      final repository = LocalPlaylistRepository(prefs);
      // Favourited before the player resolved the part id …
      await repository.addTracks(LocalPlaylist.likedId, [_track('BV1', 0)]);
      // … then again as the real part.
      await repository.addTracks(LocalPlaylist.likedId, [_track('BV1', 999)]);

      final tracks = repository.likedTracks;
      expect(tracks, hasLength(1), reason: '同一个分P不应收藏两次');
      expect(tracks.single.cid, 999);
    });

    test('remove and clear', () async {
      final repository = LocalPlaylistRepository(prefs);
      await repository.addTracks(LocalPlaylist.likedId, [
        _track('BV1', 1),
        _track('BV2', 2),
      ]);

      await repository.removeTracks(LocalPlaylist.likedId, [_track('BV1', 1)]);
      expect(repository.likedTracks.map((track) => track.id), ['BV2:2']);

      await repository.clearLiked();
      expect(repository.likedTracks, isEmpty);
    });

    test('starts empty and tolerates a corrupted payload', () async {
      expect(LocalPlaylistRepository(prefs).likedTracks, isEmpty);
      await prefs.setString('local_favorites_v1', 'not-json');
      expect(LocalPlaylistRepository(prefs).likedTracks, isEmpty);
    });
  });

  group('LocalPlaylistRepository', () {
    test('always exposes the built-in liked playlist', () {
      final repository = LocalPlaylistRepository(prefs);
      final playlists = repository.load();

      expect(playlists, hasLength(1));
      expect(playlists.single.id, LocalPlaylist.likedId);
      expect(playlists.single.name, LocalPlaylist.likedName);

      // It cannot be deleted.
      repository.remove(LocalPlaylist.likedId);
      expect(LocalPlaylistRepository(prefs).load(), hasLength(1));
    });

    test('migrates the old flat favourites into 我喜欢的音乐', () async {
      SharedPreferences.setMockInitialValues({
        'local_favorites_v1': jsonEncode([
          _track('BV1', 1, title: '旧收藏').toJson(),
        ]),
      });
      final migrated = await SharedPreferences.getInstance();

      final tracks = LocalPlaylistRepository(migrated).likedTracks;
      expect(tracks.map((track) => track.title), ['旧收藏']);
      await Future<void>.delayed(Duration.zero);
      expect(migrated.getString('local_favorites_v1'), isNull);
    });

    test('creates and removes ordinary playlists', () async {
      final repository = LocalPlaylistRepository(prefs);
      final created = await repository.create('通勤');
      expect(created.map((playlist) => playlist.name), [
        LocalPlaylist.likedName,
        '通勤',
      ]);

      final id = created.last.id;
      final updated = await repository.remove(id);
      expect(updated.map((playlist) => playlist.name), [
        LocalPlaylist.likedName,
      ]);
    });

    test('adds without duplicates and reorders tracks', () async {
      final repository = LocalPlaylistRepository(prefs);
      final created = await repository.create('通勤');
      final id = created.last.id;

      await repository.addTracks(id, [_track('BV1', 1), _track('BV2', 2)]);
      await repository.addTracks(id, [_track('BV1', 1, title: '更新')]);
      var playlist = LocalPlaylistRepository(prefs)
          .load()
          .firstWhere((item) => item.id == id);
      expect(playlist.tracks.map((track) => track.title), ['更新', '曲目2']);

      await repository.reorder(id, 0, 2);
      playlist = LocalPlaylistRepository(prefs)
          .load()
          .firstWhere((item) => item.id == id);
      expect(playlist.tracks.map((track) => track.title), ['曲目2', '更新']);
    });
  });

  group('LocalHistoryRepository', () {
    test('moves a replayed track to the front', () async {
      final repository = LocalHistoryRepository(prefs);
      await repository.record(_track('BV1', 1, title: 'A'));
      await repository.record(_track('BV2', 2, title: 'B'));
      await repository.record(_track('BV1', 1, title: 'A'));

      expect(repository.load().map((track) => track.title), ['A', 'B']);
    });

    test('caps the list so storage cannot grow without bound', () async {
      final repository = LocalHistoryRepository(prefs);
      for (var index = 0; index < 130; index++) {
        await repository.record(_track('BV$index', index));
      }

      final tracks = repository.load();
      expect(tracks, hasLength(100));
      expect(tracks.first.id, 'BV129:129');
    });

    test('remove and clear', () async {
      final repository = LocalHistoryRepository(prefs);
      await repository.record(_track('BV1', 1));
      await repository.record(_track('BV2', 2));

      await repository.remove('BV2:2');
      expect(repository.load().map((track) => track.id), ['BV1:1']);

      await repository.clear();
      expect(repository.load(), isEmpty);
    });

    test('never stores a track whose part id is still unknown', () async {
      final repository = LocalHistoryRepository(prefs);

      // A placeholder (cid 0) comes from search / favourites and is expanded by
      // the player into real parts afterwards.
      await repository.record(_track('BV1', 0, title: '同一首歌'));

      expect(repository.load(), isEmpty);
      expect(prefs.getString('local_history_v1'), isNull);
    });

    test(
      'drops already stored placeholders so the list has no duplicates',
      () async {
        // Mirrors the payload an older build produced for one played song: the
        // resolved part plus the placeholder it was expanded from.
        await prefs.setString(
          'local_history_v1',
          jsonEncode([
            {
              'bvid': 'BV1',
              'aid': 7,
              'cid': 999,
              'title': '同一首歌',
              'artist': 'UP主',
              'cover': '',
              'durationMs': 133000,
              'page': 1,
              'partTitle': '可视化',
              'playCount': 0,
            },
            {
              'bvid': 'BV1',
              'aid': 7,
              'cid': 0,
              'title': '同一首歌',
              'artist': 'UP主',
              'cover': '',
              'durationMs': 266000,
              'page': 1,
              'partTitle': null,
              'playCount': 0,
            },
          ]),
        );

        final tracks = LocalHistoryRepository(prefs).load();

        expect(tracks, hasLength(1), reason: '同一首歌不应出现两条记录');
        expect(tracks.single.cid, 999);
        expect(tracks.single.partTitle, '可视化');
      },
    );
  });
}
