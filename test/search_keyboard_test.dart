import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/play_mode.dart';
import 'package:flowingpod/core/models/player_state.dart';
import 'package:flowingpod/core/models/track_source.dart';
import 'package:flowingpod/features/search/search_page.dart';
import 'package:flowingpod/features/shell/app_shell.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/state/providers.dart';
// Material also exports a `SearchController`, hence the prefix.
import 'package:flowingpod/state/search_controller.dart' as search;
import 'package:flowingpod/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signed-out session so the page never reaches the network.
class _SignedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

/// Reports one playing track, so the shell keeps its mini player docked.
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

/// A finished search that failed: renders the message together with the retry
/// action, which is the tallest state of the page.
class _FailedSearch extends search.SearchController {
  _FailedSearch(super.source);

  @override
  search.SearchState build() => search.SearchState(
    source: source,
    keyword: 'taylor',
    error: '网络连接失败，请检查网络设置',
  );
}

Widget _host() => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(_SignedOutAuth.new),
    search
        .searchControllerProvider(TrackSource.bilibili)
        .overrideWith(() => _FailedSearch(TrackSource.bilibili)),
  ],
  // Mirrors AppShell: a Scaffold holding the mini player and the page Scaffold.
  child: MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const Expanded(child: SearchPage()),
          const SizedBox(height: 62), // mini player slot
        ],
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
        ],
      ),
    ),
  ),
);

/// Sizes the test view as [logicalSize] dp with a soft keyboard of [keyboard] dp.
void _setViewport(
  WidgetTester tester, {
  required Size logicalSize,
  required double keyboard,
  double pixelRatio = 3,
}) {
  tester.view.physicalSize = logicalSize * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * pixelRatio);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('small phone with a tall keyboard', (tester) async {
    // 360x640dp with a keyboard that carries a toolbar/suggestion strip; this
    // used to overflow the search page by 34px.
    _setViewport(tester, logicalSize: const Size(360, 640), keyboard: 340);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '搜索页在键盘展开时不应溢出');
  });

  testWidgets('large phone with the keyboard open', (tester) async {
    _setViewport(tester, logicalSize: const Size(411, 914), keyboard: 300);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape with the keyboard open', (tester) async {
    _setViewport(tester, logicalSize: const Size(640, 360), keyboard: 200);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the real shell uses the whole area the keyboard leaves', (
    tester,
  ) async {
    _setViewport(tester, logicalSize: const Size(411, 914), keyboard: 300);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authControllerProvider.overrideWith(_SignedOutAuth.new),
          playerStateProvider.overrideWith(_FakePlayer.new),
          playbackPositionProvider.overrideWithValue(
            const AsyncValue.data(Duration(seconds: 30)),
          ),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to the search tab; the other tabs are kept offstage.
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();

    // The empty search page centres its hint in the body the shell gives it,
    // so the body itself must reach all the way down to the mini player.
    final bar = tester.getRect(find.byType(MiniPlayer));
    final body = tester.getRect(
      find.descendant(
        of: find.byType(SearchPage),
        matching: find.byType(SingleChildScrollView),
      ),
    );

    expect(
      body.bottom,
      moreOrLessEquals(bar.top, epsilon: 0.5),
      reason: '键盘展开时，页面不应在键盘与迷你播放栏之间留出空白',
    );
  });
}
