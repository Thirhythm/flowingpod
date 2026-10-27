import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/utils/formatters.dart';
import 'package:flowingpod/widgets/cover_image.dart';
import 'package:flowingpod/widgets/track_source_badge.dart';
import 'package:flutter/material.dart';

/// Row used by every list that shows playable content.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.subtitle,
    this.highlight = false,
    this.showCover = true,
    this.showSource = true,
    this.leading,
    this.maxLines = 2,
  });

  final MediaTrack track;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final String? subtitle;
  final bool highlight;
  final bool showCover;

  /// Whether the row names the service the track comes from. Lists that are
  /// already scoped to one service (search tabs, cloud playlists) turn it off.
  final bool showSource;
  final Widget? leading;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: highlight,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.35),
      leading:
          leading ??
          (showCover ? CoverImage(url: track.cover, size: 52) : null),
      title: Text(
        track.displayTitle,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
          color: highlight ? scheme.primary : null,
        ),
      ),
      subtitle: Row(
        children: [
          if (showSource) ...[
            TrackSourceBadge(source: track.source),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              subtitle ?? _defaultSubtitle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: trailing,
    );
  }

  String _defaultSubtitle() {
    final buffer = StringBuffer(track.artist);
    if (track.duration > Duration.zero) {
      buffer.write(' · ${Formatters.duration(track.duration)}');
    }
    if (track.playCount > 0) {
      buffer.write(' · ${Formatters.count(track.playCount)}播放');
    }
    return buffer.toString();
  }
}
