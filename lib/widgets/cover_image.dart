import 'dart:math' as math;

import 'package:flowingpod/core/utils/image_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Cover image with a graceful placeholder.
///
/// Square by default ([size]); pass [width] / [height] for artwork rendered in
/// a non-square box, such as wide folder covers.
///
/// The requested resolution follows the rendered size so list thumbnails do not
/// download full sized artwork.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.url,
    this.size = 56,
    this.radius = 8,
    this.width,
    this.height,
  });

  final String url;

  /// Side length used when neither [width] nor [height] is given.
  final double size;

  /// Optional box dimensions overriding the square [size].
  final double? width;
  final double? height;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final boxWidth = width ?? size;
    final boxHeight = height ?? size;
    // Keep the downloaded artwork at the displayed ratio, otherwise a wide
    // cover would come back cropped square.
    final longSide = math.max(boxWidth, boxHeight);
    final scale = _requestedWidth(longSide) / longSide;
    final requestWidth = math.max(1, (boxWidth * scale).round());
    final requestHeight = math.max(1, (boxHeight * scale).round());
    final resolved = ImageUrl.resolve(
      url,
      width: requestWidth,
      height: requestHeight,
    );
    // Decode the bitmap at the rendered resolution instead of the downloaded
    // one, so list thumbnails stay tiny inside the image cache.
    final decodeWidth = (boxWidth * MediaQuery.devicePixelRatioOf(context))
        .ceil();

    Widget fallback() => ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note_rounded,
        size: math.min(boxWidth, boxHeight) * 0.42,
        color: scheme.onSurfaceVariant,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: boxWidth,
        height: boxHeight,
        child: resolved == null
            ? fallback()
            : CachedNetworkImage(
                imageUrl: resolved,
                fit: BoxFit.cover,
                memCacheWidth: decodeWidth,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, _) => fallback(),
                errorWidget: (_, _, _) => fallback(),
              ),
      ),
    );
  }

  int _requestedWidth(double boxSize) {
    if (boxSize <= 80) return ImageUrl.thumbnailWidth;
    if (boxSize <= 280) return 544;
    return 1024;
  }
}
