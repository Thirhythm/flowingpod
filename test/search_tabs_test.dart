import 'package:flowingpod/core/api/netease_client.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/track_source.dart';
import 'package:flowingpod/data/repositories/netease_repository.dart';
import 'package:flowingpod/features/search/search_page.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flowingpod/state/search_controller.dart' as search;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ResultSearch extends search.SearchController {
  _ResultSearch(super.source);

  @override
  search.SearchState build() => search.SearchState(
    source: source,
    keyword: 'taylor',
    results: const [
      MediaTrack(
        bvid: 'BV1',
        aid: 1,
        cid: 2,
        title: '结果歌曲',
        artist: 'UP主',
        cover: '',
      ),
    ],
  );
}

class _EmptySearch extends search.SearchController {
  _EmptySearch(super.source);

  @override
  search.SearchState build() => search.SearchState(source: source);
}

class _FakeNetease extends NeteaseRepository {
  _FakeNetease(super.client);

  @override
  Future<List<String>> suggest(String keyword) async => ['来自网易云'];
}

Widget _wrap(Widget home, {search.SearchController Function()? bili}) =>
    ProviderScope(
      overrides: [
        search
            .searchControllerProvider(TrackSource.bilibili)
            .overrideWith(bili ?? () => _EmptySearch(TrackSource.bilibili)),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  testWidgets('source tabs stay hidden until results are displayed', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const SearchPage()));
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('哔哩哔哩'), findsNothing);
    expect(find.text('网易云音乐'), findsNothing);
  });

  testWidgets('source tabs appear with search results', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SearchPage(),
        bili: () => _ResultSearch(TrackSource.bilibili),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.text('网易云音乐'), findsOneWidget);
    expect(find.text('结果歌曲'), findsOneWidget);
  });

  testWidgets('suggestions come from NetEase on both tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          neteaseRepositoryProvider.overrideWithValue(
            _FakeNetease(await NeteaseClient.create(prefs)),
          ),
        ],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('来自网易云'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
  });
}
