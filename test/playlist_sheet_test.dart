import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/play_mode.dart';
import 'package:flowingpod/core/models/player_state.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/widgets/playlist_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MediaTrack _track(int index) => MediaTrack(
  bvid: 'BV$index',
  aid: index,
  cid: index,
  title: '曲目 $index',
  artist: 'UP主',
  cover: '',
);

/// Reports a fixed queue, so the sheet can be exercised without the player.
class _FakePlayer extends PlayerController {
  _FakePlayer({required this.trackCount, required this.currentIndex});

  final int trackCount;
  final int currentIndex;

  @override
  PlayerState build() => PlayerState(
    queue: [for (var index = 0; index < trackCount; index++) _track(index)],
    currentIndex: currentIndex,
    mode: PlayMode.listLoop,
  );
}

Widget _host({required int trackCount, required int currentIndex}) =>
    ProviderScope(
      overrides: [
        playerStateProvider.overrideWith(
          () => _FakePlayer(trackCount: trackCount, currentIndex: currentIndex),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: PlaylistSheet())),
    );

Rect _row(WidgetTester tester, int index) => tester.getRect(
  find.ancestor(of: find.text('曲目 $index'), matching: find.byType(ListTile)),
);

void main() {
  testWidgets('opens with the current track in the second row', (tester) async {
    await tester.pumpWidget(_host(trackCount: 20, currentIndex: 8));
    await tester.pumpAndSettle();

    final list = tester.getRect(find.byType(ListView));
    final current = _row(tester, 8);

    // One row of context is kept above the current track.
    expect(
      current.top - list.top,
      moreOrLessEquals(current.height, epsilon: 0.5),
      reason: '当前曲目应停在第二项的位置',
    );
    expect(_row(tester, 7).bottom, lessThanOrEqualTo(current.top + 0.5));
    expect(current.bottom, lessThanOrEqualTo(list.bottom + 0.5));
  });

  testWidgets('leaves a queue that already fits where it is', (tester) async {
    await tester.pumpWidget(_host(trackCount: 2, currentIndex: 1));
    await tester.pumpAndSettle();

    final list = tester.getRect(find.byType(ListView));

    // Everything fits, so the list cannot scroll and stays at the top.
    expect(_row(tester, 0).top, moreOrLessEquals(list.top, epsilon: 0.5));
  });

  testWidgets('keeps the current track visible when it is the first row', (
    tester,
  ) async {
    await tester.pumpWidget(_host(trackCount: 20, currentIndex: 0));
    await tester.pumpAndSettle();

    final list = tester.getRect(find.byType(ListView));
    expect(_row(tester, 0).top, moreOrLessEquals(list.top, epsilon: 0.5));
  });

  testWidgets('paints the selected row inside the list viewport', (
    tester,
  ) async {
    await tester.pumpWidget(_host(trackCount: 20, currentIndex: 8));
    await tester.pumpAndSettle();

    final rowElement = tester.element(
      find.ancestor(of: find.text('曲目 8'), matching: find.byType(ListTile)),
    );
    final listElement = tester.element(find.byType(ListView));

    // A tile paints its background on the nearest Material. It has to be one
    // that lives inside the list, otherwise the viewport does not clip the
    // highlight and it bleeds over the sheet header while scrolling.
    Element? material;
    rowElement.visitAncestorElements((ancestor) {
      if (ancestor.widget is Material) {
        material = ancestor;
        return false;
      }
      return true;
    });
    expect(material, isNotNull, reason: 'ListTile 需要一个 Material 祖先');

    var insideList = identical(material, listElement);
    material!.visitAncestorElements((ancestor) {
      if (identical(ancestor, listElement)) {
        insideList = true;
        return false;
      }
      return true;
    });
    expect(insideList, isTrue, reason: '选中行的高亮应由列表内的 Material 绘制，才会被滚动区域裁剪');
  });
}
