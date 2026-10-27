import 'package:flowingpod/core/models/track_source.dart';
import 'package:flutter/material.dart';

/// Small label telling which service a track comes from.
class TrackSourceBadge extends StatelessWidget {
  const TrackSourceBadge({super.key, required this.source});

  final TrackSource source;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (source) {
      TrackSource.bilibili => ('哔哩哔哩', const Color(0xFFFB7299)),
      TrackSource.netease => ('网易云音乐', const Color(0xFFE54545)),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }
}
