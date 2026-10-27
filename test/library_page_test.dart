import 'package:flowingpod/core/models/local_playlist.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/player_state.dart';
import 'package:flowingpod/data/repositories/local_history_repository.dart';
import 'package:flowingpod/data/repositories/local_playlist_repository.dart';
import 'package:flowingpod/features/library/library_page.dart';
import 'package:flowingpod/features/library/playlist_detail_page.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signed-out session: the library must fall back to the on-device stores.
class _SignedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

/// Idle queue so pages that dock the mini player never touch the audio engine.
class _IdlePlayer extends PlayerController {
  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> playTracks(
    List<MediaTrack> tracks, {
    int startIndex = 0,
  }) async {}
}

const _favorite = MediaTrack(
  bvid: 'BV1',
  aid: 11,
  cid: 101,
  title: '本地收藏的歌曲',
  artist: 'UP主',
  cover: '',
);

const _played = MediaTrack(
  bvid: 'BV2',
  aid: 22,
  cid: 202,
  title: '本机播放过的歌曲',
  artist: 'UP主',
  cover: '',
);

Future<SharedPreferences> _seedPrefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await LocalPlaylistRepository(prefs)
      .addTracks(LocalPlaylist.likedId, [_favorite]);
  await LocalHistoryRepository(prefs).record(_played);
  return prefs;
}

Widget _wrap(SharedPreferences prefs, Widget home) => ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    authControllerProvider.overrideWith(_SignedOutAuth.new),
    playerStateProvider.overrideWith(_IdlePlayer.new),
    playbackPositionProvider.overrideWithValue(
      const AsyncValue.data(Duration.zero),
    ),
  ],
  child: MaterialApp(home: home),
);

void main() {
  testWidgets('signed out, the library shows local playlists and history', (
    tester,
  ) async {
    final prefs = await _seedPrefs();
    await tester.pumpWidget(_wrap(prefs, const LibraryPage()));
    await tester.pumpAndSettle();

    expect(find.text('媒体库'), findsOneWidget);
    expect(find.text('歌单'), findsOneWidget);
    expect(find.text('播放历史'), findsOneWidget);
    expect(find.text('本地歌单'), findsOneWidget);
    expect(find.text(LocalPlaylist.likedName), findsOneWidget);
    expect(find.text('1 首'), findsOneWidget);

    // Cloud sections only appear while signed in.
    expect(find.text('哔哩哔哩'), findsNothing);
    expect(find.text('网易云音乐'), findsNothing);

    await tester.tap(find.text(LocalPlaylist.likedName));
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistDetailPage), findsOneWidget);
    expect(find.text(_favorite.title), findsOneWidget);
    expect(find.textContaining('共 1 首'), findsOneWidget);
    expect(find.text('播放全部'), findsNothing);
    expect(find.byTooltip('播放全部'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('播放历史'));
    await tester.pumpAndSettle();

    expect(find.text(_played.title), findsOneWidget);
    expect(find.textContaining('共 1 条'), findsOneWidget);
  });

  testWidgets('creates a local playlist from the library', (tester) async {
    final prefs = await _seedPrefs();
    await tester.pumpWidget(_wrap(prefs, const LibraryPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建本地歌单'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '通勤歌单');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();

    expect(find.text('通勤歌单'), findsOneWidget);
    final stored = LocalPlaylistRepository(prefs).load();
    expect(stored.map((playlist) => playlist.name), [
      LocalPlaylist.likedName,
      '通勤歌单',
    ]);
  });

  testWidgets('long pressing a track enters batch mode and deletes it', (
    tester,
  ) async {
    final prefs = await _seedPrefs();
    await tester.pumpWidget(_wrap(prefs, const LibraryPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(LocalPlaylist.likedName));
    await tester.pumpAndSettle();

    await tester.longPress(find.text(_favorite.title));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('删除选中的 1 首歌曲'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text(_favorite.title), findsNothing);
    expect(find.text('这个歌单还没有歌曲'), findsOneWidget);
    expect(LocalPlaylistRepository(prefs).likedTracks, isEmpty);
  });

  testWidgets('favouriting stores the track in 我喜欢的音乐 and opens the picker', (
    tester,
  ) async {
    final prefs = await _seedPrefs();
    await tester.pumpWidget(_wrap(prefs, const LibraryPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('播放历史'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text(_played.title));
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsOneWidget);

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();

    // The sheet lists playlists to add to and reports the automatic like.
    expect(find.text('已加入「${LocalPlaylist.likedName}」'), findsOneWidget);
    expect(find.text(LocalPlaylist.likedName), findsOneWidget);

    // The favourite is already stored before the sheet is confirmed.
    expect(
      LocalPlaylistRepository(prefs).likedTracks.map((track) => track.id),
      [_played.id, _favorite.id],
    );

    await tester.tap(find.textContaining('保存到'));
    await tester.pumpAndSettle();

    expect(find.text('已更新收藏'), findsOneWidget);
  });
}
