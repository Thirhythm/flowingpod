import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/play_mode.dart';
import 'package:flowingpod/core/models/player_state.dart';
import 'package:flowingpod/features/player/player_page.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flowingpod/widgets/marquee_text.dart';
import 'package:flowingpod/widgets/player_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/marquee.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _shortTitle = '短标题';
const String _longTitle = '这是一个非常非常长的歌曲标题，长到一行肯定放不下，需要跑马灯滚动才能看全';

class _SignedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

class _FakePlayer extends PlayerController {
  _FakePlayer(this.title);

  final String title;

  @override
  PlayerState build() => PlayerState(
    queue: [
      MediaTrack(
        bvid: 'BV1',
        aid: 1,
        cid: 2,
        title: title,
        artist: '作者名称',
        cover: '',
        duration: const Duration(minutes: 3),
      ),
    ],
    currentIndex: 0,
    mode: PlayMode.listLoop,
    playing: true,
    duration: const Duration(minutes: 3),
  );
}

/// The [TickerMode] the marquee itself is driven by (its nearest ancestor).
bool _marqueeTickerEnabled(WidgetTester tester) =>
    (find
                .ancestor(
                  of: find.byType(Marquee),
                  matching: find.byType(TickerMode),
                )
                .evaluate()
                .first
                .widget
            as TickerMode)
        .enabled;

/// Hosts [MarqueeText] inside a fixed width so overflow is deterministic.
Widget _hostText(String text, {double width = 200}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: MarqueeText(text: text),
      ),
    ),
  ),
);

Future<Widget> _hostPlayerPage(String title) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authControllerProvider.overrideWith(_SignedOutAuth.new),
      playerStateProvider.overrideWith(() => _FakePlayer(title)),
      playbackPositionProvider.overrideWithValue(
        const AsyncValue.data(Duration(seconds: 30)),
      ),
    ],
    child: const MaterialApp(home: PlayerPage()),
  );
}

/// Hosts the global mini player through the scaffold used by pushed pages.
Future<Widget> _hostMiniPlayer(String title) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authControllerProvider.overrideWith(_SignedOutAuth.new),
      playerStateProvider.overrideWith(() => _FakePlayer(title)),
      playbackPositionProvider.overrideWithValue(
        const AsyncValue.data(Duration(seconds: 30)),
      ),
    ],
    child: const MaterialApp(
      home: PlayerScaffold(title: Text('页面'), body: SizedBox()),
    ),
  );
}

void main() {
  group('MarqueeText', () {
    testWidgets('keeps short text static', (tester) async {
      await tester.pumpWidget(_hostText(_shortTitle));
      await tester.pumpAndSettle();

      expect(find.text(_shortTitle), findsOneWidget);
      expect(find.byType(Marquee), findsNothing);
    });

    testWidgets('scrolls text that does not fit', (tester) async {
      await tester.pumpWidget(_hostText(_longTitle));
      // A marquee animates forever, so the tree never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Marquee), findsOneWidget);
    });

    testWidgets('falls back to a plain label without a bounded width', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(children: [MarqueeText(text: _longTitle)]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Marquee), findsNothing);
      expect(find.text(_longTitle), findsOneWidget);
    });

    testWidgets('stops scrolling when an ancestor TickerMode is disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: TickerMode(
                  enabled: false,
                  child: MarqueeText(text: _longTitle),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Flush the marquee's zero delay before it starts its scroll animation.
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byType(Marquee), findsOneWidget);
      expect(_marqueeTickerEnabled(tester), isFalse);
    });

    testWidgets('pauses while the app is in the background', (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      await tester.pumpWidget(_hostText(_longTitle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(_marqueeTickerEnabled(tester), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(_marqueeTickerEnabled(tester), isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_marqueeTickerEnabled(tester), isTrue);
    });
  });

  group('PlayerPage', () {
    testWidgets('left aligns the song name and the artist', (tester) async {
      await tester.pumpWidget(await _hostPlayerPage(_shortTitle));
      await tester.pumpAndSettle();

      final pageWidth = tester.getSize(find.byType(PlayerPage)).width;
      final title = tester.getRect(find.text(_shortTitle));
      final artist = tester.getRect(find.text('作者名称'));

      expect(title.left, artist.left, reason: '名称与作者应左对齐');
      expect(title.left, lessThan(pageWidth / 3), reason: '名称应位于页面左侧而不是居中');
    });

    testWidgets('scrolls a long song name', (tester) async {
      await tester.pumpWidget(await _hostPlayerPage(_longTitle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Marquee), findsOneWidget);
    });
  });

  group('Mini player', () {
    /// The mini player competes with the artwork and the buttons for width, so
    /// it is measured on a phone sized surface.
    void usePhoneViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 800) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('scrolls a long song name', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(await _hostMiniPlayer(_longTitle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Marquee), findsOneWidget);
    });

    testWidgets('keeps a short song name static', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(await _hostMiniPlayer(_shortTitle));
      await tester.pumpAndSettle();

      expect(find.byType(Marquee), findsNothing);
      expect(find.text(_shortTitle), findsOneWidget);
    });
  });
}
