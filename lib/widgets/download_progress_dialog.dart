import 'package:flowingpod/data/services/download_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Modal progress dialog shown while a track is being saved.
class DownloadProgressDialog extends StatelessWidget {
  const DownloadProgressDialog({
    super.key,
    required this.title,
    required this.progress,
  });

  final String title;
  final ValueListenable<DownloadProgress?> progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在下载'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<DownloadProgress?>(
              valueListenable: progress,
              builder: (context, value, _) {
                return LinearProgressIndicator(value: value?.fraction);
              },
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<DownloadProgress?>(
              valueListenable: progress,
              builder: (context, value, _) {
                final text = value == null
                    ? '正在准备下载…'
                    : value.total > 0
                    ? '${_megabytes(value.received)} / ${_megabytes(value.total)}'
                    : '已下载 ${_megabytes(value.received)}';
                return Text(
                  text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
