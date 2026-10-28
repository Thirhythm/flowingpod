import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/track_source.dart';
import 'package:flowingpod/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MediaTrack _track({
  required TrackSource source,
  String artist = 'UP主',
  bool vip = false,
}) => MediaTrack(
  source: source,
  bvid: 'BV1',
  aid: 1,
  cid: 1,
  songId: source == TrackSource.netease ? 1 : 0,
  title: '曲目',
  artist: artist,
  cover: '',
  vip: vip,
);

Widget _host(MediaTrack track, {bool showSource = true}) => MaterialApp(
  home: Scaffold(
    body: TrackTile(track: track, showSource: showSource),
  ),
);

void main() {
  testWidgets('names the source of a Bilibili track', (tester) async {
    await tester.pumpWidget(_host(_track(source: TrackSource.bilibili)));

    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.text('网易云音乐'), findsNothing);
  });

  testWidgets('names the source of a NetEase track', (tester) async {
    await tester.pumpWidget(_host(_track(source: TrackSource.netease)));

    expect(find.text('网易云音乐'), findsOneWidget);
    expect(find.text('哔哩哔哩'), findsNothing);
  });

  testWidgets('hides the source when the list is already scoped', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_track(source: TrackSource.bilibili), showSource: false),
    );

    expect(find.text('哔哩哔哩'), findsNothing);
  });

  testWidgets('marks a NetEase VIP track', (tester) async {
    await tester.pumpWidget(
      _host(_track(source: TrackSource.netease, vip: true)),
    );

    expect(find.text('VIP'), findsOneWidget);
  });

  testWidgets('shows no VIP badge for a free track', (tester) async {
    await tester.pumpWidget(_host(_track(source: TrackSource.netease)));

    expect(find.text('VIP'), findsNothing);
  });

  testWidgets('long artist names ellipsise instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_track(source: TrackSource.netease, artist: '很长的歌手名' * 20)),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('很长的歌手名'), findsOneWidget);
  });
}
