import 'package:flowingpod/data/services/storage_bridge.dart';
import 'package:flutter/material.dart';

/// Ensures the app may write downloads to shared storage.
///
/// When access is missing an explanation is shown first; only after the user
/// agrees is the system permission prompt opened. Returns whether access was
/// granted.
Future<bool> ensureStoragePermission(BuildContext context) async {
  if (await StorageBridge.hasAccess()) return true;
  if (!context.mounted) return false;

  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('需要存储权限'),
      content: const Text(
        '下载音乐需要访问设备存储，以便将歌曲保存到 Music 文件夹。'
        'FlowingPod 仅使用该权限写入你下载的音乐文件。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('去授权'),
        ),
      ],
    ),
  );
  if (accepted != true) return false;

  final granted = await StorageBridge.requestAccess();
  if (!granted && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('未获得存储权限，无法下载音乐')),
    );
  }
  return granted;
}
