import 'dart:convert';

import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/play_mode.dart';
import 'package:flowingpod/core/models/player_state.dart';
import 'package:flowingpod/features/player/player_page.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _track = MediaTrack(
  bvid: 'BV1',
  aid: 1,
  cid: 2,
  title: '正在播放的歌曲',
  artist: 'UP主',
  cover: '',
  duration: Duration(minutes: 3),
);

/// Signed-out session so the cloud favourite status is never queried.
class _SignedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

/// Reports [_track] as the current queue entry without touching the audio
/// service.
class _FakePlayer extends PlayerController {
  @override
  PlayerState build() => const PlayerState(
    queue: [_track],
    currentIndex: 0,
    mode: PlayMode.listLoop,
    playing: true,
    duration: Duration(minutes: 3),
  );
}

Future<void> _pumpPlayer(
  WidgetTester tester, {
  List<MediaTrack> localFavorites = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    if (localFavorites.isNotEmpty)
      'local_favorites_v1': jsonEncode([
        for (final track in localFavorites) track.toJson(),
      ]),
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authControllerProvider.overrideWith(_SignedOutAuth.new),
        playerStateProvider.overrideWith(_FakePlayer.new),
        playbackPositionProvider.overrideWithValue(
          const AsyncValue.data(Duration(seconds: 30)),
        ),
      ],
      child: const MaterialApp(home: PlayerPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed-out player shows the local favourite as collected', (
    tester,
  ) async {
    await _pumpPlayer(tester, localFavorites: const [_track]);

    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
  });

  testWidgets('signed-out player leaves an unknown track uncollected', (
    tester,
  ) async {
    await _pumpPlayer(tester);

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
  });

  testWidgets('a matching part from another video does not mark it collected', (
    tester,
  ) async {
    await _pumpPlayer(
      tester,
      localFavorites: const [
        MediaTrack(
          bvid: 'BV1',
          aid: 1,
          cid: 2,
          title: '另一分P',
          artist: 'UP主',
          cover: '',
          page: 2,
        ),
      ],
    );

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
  });
}
