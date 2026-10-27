import 'package:flowingpod/core/models/fav_folder.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/paged_result.dart';
import 'package:flowingpod/core/models/play_mode.dart';
import 'package:flowingpod/core/models/player_state.dart';
import 'package:flowingpod/features/library/playlist_detail_page.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/library_controllers.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flowingpod/widgets/player_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signed-out session so no cloud request is attempted.
class _SignedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

/// Reports a fixed queue so the mini player has something to show, without
/// touching the real audio service.
class _FakePlayer extends PlayerController {
  @override
  PlayerState build() => const PlayerState(
    queue: [
      MediaTrack(
        bvid: 'BV1',
        aid: 1,
        cid: 2,
        title: '正在播放的歌曲',
        artist: 'UP主',
        cover: '',
        duration: Duration(minutes: 3),
      ),
    ],
    currentIndex: 0,
    mode: PlayMode.listLoop,
    playing: true,
    duration: Duration(minutes: 3),
  );
}

Future<Widget> _wrap(
  Widget home, {
  PlayerController Function()? player,
  int folderId = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authControllerProvider.overrideWith(_SignedOutAuth.new),
      playerStateProvider.overrideWith(player ?? _FakePlayer.new),
      playbackPositionProvider.overrideWithValue(
        const AsyncValue.data(Duration(seconds: 30)),
      ),
      // Serves the folder without touching the network.
      favMediaProvider(folderId).overrideWithBuild(
        (ref, notifier) => const PagedResult(
          items: [
            MediaTrack(
              bvid: 'BV9',
              aid: 9,
              cid: 9,
              title: '收藏夹里的歌曲',
              artist: 'UP主',
              cover: '',
            ),
          ],
          page: 1,
          hasMore: false,
        ),
      ),
    ],
    child: MaterialApp(home: home),
  );
}

void main() {
  testWidgets('PlayerScaffold docks the mini player below the content', (
    tester,
  ) async {
    await tester.pumpWidget(
      await _wrap(
        const PlayerScaffold(
          title: Text('某个页面'),
          body: Center(child: Text('页面内容')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Both the page content and the player bar are visible.
    expect(find.text('页面内容'), findsOneWidget);
    expect(find.text('正在播放的歌曲'), findsOneWidget);

    // The bar must be laid out below the content instead of covering it.
    final content = tester.getRect(find.text('页面内容'));
    final bar = tester.getRect(find.text('正在播放的歌曲'));
    expect(
      bar.top,
      greaterThanOrEqualTo(content.bottom),
      reason: '播放栏不应遮挡页面内容',
    );
  });

  testWidgets('a favourite folder keeps the player bar and hides no content', (
    tester,
  ) async {
    const folder = FavFolder(id: 1, title: '我的收藏夹', mediaCount: 1);
    await tester.pumpWidget(
      await _wrap(const FolderDetailPage(folder: folder)),
    );
    await tester.pumpAndSettle();

    expect(find.text('收藏夹里的歌曲'), findsOneWidget);
    expect(find.text('正在播放的歌曲'), findsOneWidget, reason: '进入特定收藏夹后应显示播放控制栏');

    // The bar must not cover the list.
    final row = tester.getRect(find.text('收藏夹里的歌曲'));
    final bar = tester.getRect(find.text('正在播放的歌曲'));
    expect(bar.top, greaterThanOrEqualTo(row.bottom));
  });

  testWidgets('the bar disappears again when the queue is cleared', (
    tester,
  ) async {
    await tester.pumpWidget(
      await _wrap(
        const PlayerScaffold(title: Text('页面'), body: SizedBox()),
        player: _EmptyPlayer.new,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('正在播放的歌曲'), findsNothing);
  });
}

/// Player that reports an empty queue.
class _EmptyPlayer extends PlayerController {
  @override
  PlayerState build() => const PlayerState();
}
