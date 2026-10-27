import 'package:flowingpod/features/library/history_view.dart';
import 'package:flowingpod/features/library/playlists_tab.dart';
import 'package:flutter/material.dart';

/// Library tab of the app shell: playlists and the play history.
///
/// The shell already docks a mini player below this page, so the tab body
/// renders none of its own.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        bottom: const TabBar(
          tabs: [
            Tab(text: '歌单'),
            Tab(text: '播放历史'),
          ],
        ),
      ),
      body: const TabBarView(children: [PlaylistsTab(), HistoryView()]),
    ),
  );
}
