import 'package:flowingpod/widgets/mini_player.dart';
import 'package:flutter/material.dart';

/// Page scaffold that keeps the global mini player docked at the bottom, the
/// same way the app shell does.
///
/// Pages pushed on top of the shell would otherwise cover the player bar. The
/// bar is placed inside the body (not stacked on top of it), so the page
/// content is laid out above it and never obscured.
class PlayerScaffold extends StatelessWidget {
  const PlayerScaffold({
    super.key,
    this.title,
    this.actions,
    this.bottom,
    required this.body,
  });

  final Widget? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: title, actions: actions, bottom: bottom),
    body: Column(
      children: [
        Expanded(child: body),
        const MiniPlayer(),
      ],
    ),
  );
}
