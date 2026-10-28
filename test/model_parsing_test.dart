import 'package:flowingpod/core/models/audio_stream.dart';
import 'package:flowingpod/core/models/history_entry.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/netease_quality.dart';
import 'package:flowingpod/core/models/play_mode.dart';
import 'package:flowingpod/core/models/track_source.dart';
import 'package:flowingpod/core/models/video_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaTrack', () {
    test('round trips through JSON', () {
      const track = MediaTrack(
        bvid: 'BV1xx',
        aid: 42,
        cid: 99,
        title: '歌名',
        artist: 'UP主',
        cover: 'https://i0.hdslb.com/c.jpg',
        artistId: 7,
        duration: Duration(seconds: 215),
        page: 2,
        partTitle: 'P2',
        playCount: 1234,
      );

      final restored = MediaTrack.fromJson(track.toJson());

      expect(restored, track);
      expect(restored.duration, const Duration(seconds: 215));
      expect(restored.artistId, 7);
      expect(restored.playCount, 1234);
    });

    test('compares by video and part', () {
      const a = MediaTrack(
        bvid: 'BV1',
        aid: 1,
        cid: 10,
        title: 'a',
        artist: 'x',
        cover: '',
      );
      final b = a.copyWith(title: 'b');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == b.copyWith(cid: 11), isFalse);
    });

    test('displayTitle appends the part name only when it differs', () {
      const single = MediaTrack(
        bvid: 'BV1',
        aid: 1,
        cid: 1,
        title: '歌名',
        artist: 'x',
        cover: '',
        partTitle: '歌名',
      );
      expect(single.displayTitle, '歌名');

      const multi = MediaTrack(
        bvid: 'BV1',
        aid: 1,
        cid: 2,
        title: '合集',
        artist: 'x',
        cover: '',
        partTitle: 'P2',
      );
      expect(multi.displayTitle, '合集 · P2');
    });

    test('keeps NetEase songs separate from Bilibili entries', () {
      const song = MediaTrack(
        source: TrackSource.netease,
        songId: 42,
        title: '网易云歌曲',
        artist: '歌手',
        cover: '',
        duration: Duration(seconds: 200),
      );

      expect(song.id, 'netease:42');
      expect(song.partKey, 'netease:42');
      expect(song.isResolved, isTrue);
      expect(song.canFavorite, isTrue);

      final restored = MediaTrack.fromJson(song.toJson());
      expect(restored, song);
      expect(restored.source, TrackSource.netease);
      expect(restored.songId, 42);
      expect(restored.isNetease, isTrue);
    });
  });

  group('VideoDetail', () {
    test('expands every part into its own track', () {
      final detail = VideoDetail.fromJson({
        'bvid': 'BV1',
        'aid': 100,
        'title': '专辑',
        'pic': 'http://i0.hdslb.com/cover.jpg',
        'desc': '简介',
        'duration': 120,
        'owner': {'mid': 5, 'name': 'UP主', 'face': ''},
        'stat': {'view': 10000},
        'pages': [
          {'cid': 11, 'page': 1, 'part': '第一首', 'duration': 60},
          {'cid': 22, 'page': 2, 'part': '第二首', 'duration': 60},
        ],
      });

      final tracks = detail.toTracks();

      expect(tracks, hasLength(2));
      expect(tracks[0].cid, 11);
      expect(tracks[1].cid, 22);
      expect(tracks[0].partTitle, '第一首');
      expect(tracks[0].artist, 'UP主');
      expect(tracks[0].artistId, 5);
      expect(tracks[0].playCount, 10000);
      expect(tracks[0].duration, const Duration(seconds: 60));
    });

    test('falls back to a single part when pages are missing', () {
      final detail = VideoDetail.fromJson({
        'bvid': 'BV2',
        'aid': 200,
        'cid': 33,
        'title': '单曲',
        'pic': '',
        'duration': 200,
        'pages': null,
      });

      final tracks = detail.toTracks();

      expect(tracks, hasLength(1));
      expect(tracks.single.cid, 33);
      expect(tracks.single.partTitle, isNull);
      expect(tracks.single.artist, '未知作者');
    });
  });

  group('PlaybackSource', () {
    test('orders DASH audio by bandwidth, best first', () {
      final source = PlaybackSource.fromPlayUrl({
        'dash': {
          'duration': 60,
          'audio': [
            {
              'id': 30216,
              'baseUrl': 'https://cdn/low.m4s',
              'bandwidth': 64000,
              'mimeType': 'audio/mp4',
            },
            {
              'id': 30280,
              'baseUrl': 'https://cdn/high.m4s',
              'bandwidth': 192000,
              'mimeType': 'audio/mp4',
              'backupUrl': ['https://backup/high.m4s'],
            },
          ],
        },
      });

      expect(source.best!.qualityId, 30280);
      expect(source.best!.qualityLabel, '192K');
      expect(source.best!.backupUrls, ['https://backup/high.m4s']);
      expect(source.duration, const Duration(seconds: 60));
    });

    test('reads the legacy durl fallback', () {
      final source = PlaybackSource.fromPlayUrl({
        'quality': 16,
        'durl': [
          {'url': 'https://cdn/audio.m4s', 'backup_url': <String>[]},
        ],
      });

      expect(source.isEmpty, isFalse);
      expect(source.best!.url, 'https://cdn/audio.m4s');
    });

    test('reports emptiness when no stream is available', () {
      expect(
        PlaybackSource.fromPlayUrl({
          'dash': {'audio': null},
        }).isEmpty,
        isTrue,
      );
    });
  });

  group('HistoryEntry', () {
    test('reads the nested history object and builds the delete id', () {
      final entry = HistoryEntry.fromJson({
        'title': '歌名',
        'cover': 'http://i0.hdslb.com/c.jpg',
        'author_name': 'UP主',
        'author_mid': 5,
        'view_at': 1700000000,
        'progress': 30,
        'duration': 200,
        'show_title': 'P2',
        'history': {'oid': 456, 'bvid': 'BV1xx', 'cid': 789, 'page': 2},
      });

      expect(entry.track.bvid, 'BV1xx');
      expect(entry.track.cid, 789);
      expect(entry.track.aid, 456);
      expect(entry.avid, 456);
      expect(entry.deleteKid, 'archive_456');
      expect(entry.progress, const Duration(seconds: 30));
      expect(entry.isValid, isTrue);
    });

    test('is invalid when no playable video is present', () {
      final entry = HistoryEntry.fromJson({
        'title': '直播',
        'view_at': 1,
        'history': <String, dynamic>{},
      });

      expect(entry.isValid, isFalse);
      expect(entry.deleteKid, isNull);
    });
  });

  group('PlayMode', () {
    test('restores persisted values', () {
      expect(PlayMode.fromStorage('shuffle'), PlayMode.shuffle);
      expect(PlayMode.fromStorage(null), PlayMode.listLoop);
      expect(PlayMode.fromStorage('unknown'), PlayMode.listLoop);
    });

    test('cycles through every mode', () {
      expect(PlayMode.sequential.next, PlayMode.listLoop);
      expect(PlayMode.listLoop.next, PlayMode.singleLoop);
      expect(PlayMode.singleLoop.next, PlayMode.shuffle);
      expect(PlayMode.shuffle.next, PlayMode.sequential);
    });
  });

  group('NeteaseQuality', () {
    test('restores an unknown or missing preference to 极高', () {
      expect(NeteaseQuality.fromStorage('lossless'), NeteaseQuality.lossless);
      expect(NeteaseQuality.fromStorage('exhigh'), NeteaseQuality.exhigh);
      expect(NeteaseQuality.fromStorage(null), NeteaseQuality.fallback);
      expect(NeteaseQuality.fromStorage('bogus'), NeteaseQuality.fallback);
    });

    test('maps API level strings and ignores unknown ones', () {
      expect(NeteaseQuality.fromApiValue('hires'), NeteaseQuality.hires);
      expect(NeteaseQuality.fromApiValue('dolby'), isNull);
    });

    test('ranks the ladder from 标准 up to 臻音全景声', () {
      expect(NeteaseQuality.standard.index, 0);
      expect(
        NeteaseQuality.values.map((quality) => quality.index),
        orderedEquals(List.generate(NeteaseQuality.values.length, (i) => i)),
      );
      expect(
        NeteaseQuality.vivid.index,
        greaterThan(NeteaseQuality.hires.index),
      );
    });
  });
}
