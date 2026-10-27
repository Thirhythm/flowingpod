import 'package:flowingpod/features/home/home_page.dart';
import 'package:flowingpod/features/library/library_page.dart';
import 'package:flowingpod/features/profile/profile_page.dart';
import 'package:flowingpod/features/search/search_page.dart';
import 'package:flowingpod/widgets/mini_player.dart';
import 'package:flutter/material.dart';

/// Root navigation: a tab bar at the bottom and the persistent mini player
/// directly above it.
///
/// The mini player is part of the page body, so tab content is laid out in the
/// remaining space and can never be hidden behind it.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const List<Widget> _pages = [
    HomePage(),
    SearchPage(),
    LibraryPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // The Scaffold hands its body a MediaQuery that already has the
          // bottom padding and the keyboard inset taken out, because it
          // reserves that space itself for the navigation bar. Rebuilding the
          // MediaQuery here — this context sits above the Scaffold — would put
          // the keyboard inset back, and each page would then subtract it a
          // second time and leave a blank band the height of the keyboard
          // above the keyboard.
          Expanded(
            child: IndexedStack(index: _index, children: _pages),
          ),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search_rounded),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: '媒体库',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
