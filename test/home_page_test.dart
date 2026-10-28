import 'package:flowingpod/core/models/fav_folder.dart';
import 'package:flowingpod/core/models/local_playlist.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/paged_result.dart';
import 'package:flowingpod/core/models/player_state.dart';
import 'package:flowingpod/core/models/playlist_ref.dart';
import 'package:flowingpod/core/models/recent_playlist.dart';
import 'package:flowingpod/data/repositories/local_history_repository.dart';
import 'package:flowingpod/data/repositories/local_playlist_repository.dart';
import 'package:flowingpod/data/repositories/local_recent_playlists_repository.dart';
import 'package:flowingpod/features/home/home_page.dart';
import 'package:flowingpod/features/library/playlist_detail_page.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/library_controllers.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signed-out session: the home page still shows what played in this app.
class _SignedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

/// An idle queue, so the mini player on the pushed folder page stays quiet and
/// playback requests never reach the audio service.
class _IdlePlayer extends PlayerController {
  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> playTracks(
    List<MediaTrack> tracks, {
    int startIndex = 0,
  }) async {}
}

const _played = MediaTrack(
  bvid: 'BV2',
  aid: 22,
  cid: 202,
  title: '本机播放过的歌曲',
  artist: 'UP主',
  cover: '',
);

const _folderTrack = MediaTrack(
  bvid: 'BV3',
  aid: 33,
  cid: 0,
  title: '收藏夹里的歌曲',
  artist: 'UP主',
  cover: '',
);

const _folder = RecentPlaylist(
  source: PlaylistSource.bilibili,
  id: '7',
  title: '深夜电台',
  cover: '',
  count: 3,
);

/// Serves [_folderTrack] for the folder, so its page loads without a client.
class _FakeFavMedia extends FavMediaController {
  _FakeFavMedia(super.mediaId);

  @override
  Future<PagedResult<MediaTrack>> build() async =>
      const PagedResult(items: [_folderTrack], page: 1, hasMore: false);
}

/// Serves a folder whose total has moved on since it was recorded.
class _FakeFolders extends FavFoldersController {
  @override
  Future<List<FavFolder>> build() async =>
      const [FavFolder(id: 7, title: '深夜电台', mediaCount: 5)];
}

Future<SharedPreferences> _seedPrefs({bool withFolder = true}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await LocalHistoryRepository(prefs).record(_played);
  if (withFolder) {
    await LocalRecentPlaylistsRepository(prefs).record(_folder);
  }
  return prefs;
}

Widget _wrap(SharedPreferences prefs, {Widget home = const HomePage()}) =>
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authControllerProvider.overrideWith(_SignedOutAuth.new),
        playerStateProvider.overrideWith(_IdlePlayer.new),
        favMediaProvider(_folder.toRef().numericId)
            .overrideWith(() => _FakeFavMedia(_folder.toRef().numericId)),
      ],
      child: MaterialApp(home: home),
    );

Finder _horizontalStrips() => find.byWidgetPredicate(
  (widget) => widget is ListView && widget.scrollDirection == Axis.horizontal,
);

void main() {
  testWidgets('recently played folders sit above the recently played tracks', (
    tester,
  ) async {
    final prefs = await _seedPrefs();
    await tester.pumpWidget(_wrap(prefs));
    await tester.pumpAndSettle();

    expect(find.text(_folder.title), findsOneWidget);
    expect(find.text('3 个内容'), findsOneWidget);
    expect(find.text(_played.title), findsOneWidget);

    // Covers are laid out horizontally at the top of 最近播放 …
    expect(_horizontalStrips(), findsOneWidget);
    // … above the track rows.
    expect(
      tester.getTopLeft(find.text(_folder.title)).dy,
      lessThan(tester.getTopLeft(find.text(_played.title)).dy),
    );
  });

  testWidgets('the folder strip is hidden until one has been played from', (
    tester,
  ) async {
    final prefs = await _seedPrefs(withFolder: false);
    await tester.pumpWidget(_wrap(prefs));
    await tester.pumpAndSettle();

    expect(_horizontalStrips(), findsNothing);
    expect(find.text(_played.title), findsOneWidget);
  });

  testWidgets('a folder shortcut count follows the folder total', (
    tester,
  ) async {
    final prefs = await _seedPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_SignedOutAuth.new),
          playerStateProvider.overrideWith(_IdlePlayer.new),
          favFoldersProvider.overrideWith(_FakeFolders.new),
          favMediaProvider(
            _folder.toRef().numericId,
          ).overrideWith(() => _FakeFavMedia(_folder.toRef().numericId)),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('5 个内容'), findsOneWidget);
    expect(find.text('3 个内容'), findsNothing);
  });

  testWidgets('a local shortcut count follows the playlist total', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await LocalPlaylistRepository(
      prefs,
    ).addTracks(LocalPlaylist.likedId, const [_played]);
    await LocalRecentPlaylistsRepository(prefs).record(
      const RecentPlaylist(
        source: PlaylistSource.local,
        id: LocalPlaylist.likedId,
        title: LocalPlaylist.likedName,
        cover: '',
        count: 9,
      ),
    );

    await tester.pumpWidget(_wrap(prefs));
    await tester.pumpAndSettle();

    expect(find.text('1 首'), findsOneWidget);
    expect(find.text('9 首'), findsNothing);
  });

  testWidgets('an empty history keeps its hint', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_wrap(prefs));
    await tester.pumpAndSettle();

    expect(find.text('没有播放记录'), findsOneWidget);
    expect(_horizontalStrips(), findsNothing);
  });

  testWidgets('tapping a folder cover opens the folder', (tester) async {
    final prefs = await _seedPrefs();
    await tester.pumpWidget(_wrap(prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_folder.title));
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistDetailPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(_folder.title),
      ),
      findsOneWidget,
    );
    // The folder contents load instead of the error state.
    expect(find.text(_folderTrack.title), findsOneWidget);
  });

  testWidgets('playing from a folder feeds the home shortcuts', (tester) async {
    final prefs = await _seedPrefs(withFolder: false);
    await tester.pumpWidget(
      _wrap(prefs, home: PlaylistDetailPage(playlist: _folder.toRef())),
    );
    await tester.pumpAndSettle();
    expect(LocalRecentPlaylistsRepository(prefs).load(), isEmpty);

    await tester.tap(find.text(_folderTrack.title));
    await tester.pumpAndSettle();

    // The shortcut keeps the playlist identity plus the cover it was played with.
    final recorded = LocalRecentPlaylistsRepository(prefs).load();
    expect(recorded, hasLength(1));
    expect(recorded.single.id, _folder.id);
    expect(recorded.single.source, PlaylistSource.bilibili);
    expect(recorded.single.title, _folder.title);
    expect(recorded.single.count, _folder.count);
    expect(recorded.single.cover, _folderTrack.cover);
  });

  testWidgets('long pressing a folder cover removes only the shortcut', (
    tester,
  ) async {
    final prefs = await _seedPrefs();
    await tester.pumpWidget(_wrap(prefs));
    await tester.pumpAndSettle();

    await tester.longPress(find.text(_folder.title));
    await tester.pumpAndSettle();

    expect(find.text('确定将「${_folder.title}」从最近播放中移除吗？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await tester.pumpAndSettle();

    expect(find.text(_folder.title), findsNothing);
    expect(LocalRecentPlaylistsRepository(prefs).load(), isEmpty);
    // The played track stays.
    expect(find.text(_played.title), findsOneWidget);
  });
}
