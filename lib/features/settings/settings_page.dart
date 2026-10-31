import 'package:flowingpod/core/models/app_theme_mode.dart';
import 'package:flowingpod/core/utils/storage_paths.dart';
import 'package:flowingpod/data/services/storage_bridge.dart';
import 'package:flowingpod/features/settings/about_page.dart';
import 'package:flowingpod/state/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App preferences, reachable from 我的.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoOpenPlayer = ref.watch(autoOpenPlayerProvider);
    final volumeLeveling = ref.watch(volumeLevelingProvider);
    final themeMode = ref.watch(themeModeProvider);
    final dynamicColor = ref.watch(dynamicColorProvider);
    final downloadDirectory = ref.watch(downloadDirectoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline_rounded),
            title: const Text('点击曲目后自动打开播放器'),
            value: autoOpenPlayer,
            onChanged: (value) =>
                ref.read(autoOpenPlayerProvider.notifier).setEnabled(value),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.graphic_eq_rounded),
            title: const Text('音量均衡'),
            subtitle: const Text('播放不同内容时保持响度一致'),
            value: volumeLeveling,
            onChanged: (value) =>
                ref.read(volumeLevelingProvider.notifier).setEnabled(value),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('下载路径'),
            subtitle: Text(
              downloadDirectory ?? StoragePaths.defaultMusicDirectory,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickDownloadDirectory(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('显示模式'),
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<AppThemeMode>(
                value: themeMode,
                borderRadius: BorderRadius.circular(12),
                onChanged: (mode) {
                  if (mode != null) {
                    ref.read(themeModeProvider.notifier).setMode(mode);
                  }
                },
                items: [
                  for (final mode in AppThemeMode.values)
                    DropdownMenuItem<AppThemeMode>(
                      value: mode,
                      child: Text(mode.label),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.palette_outlined),
            title: const Text('动态取色'),
            subtitle: const Text('跟随系统壁纸或强调色生成主题配色'),
            value: dynamicColor,
            onChanged: (value) =>
                ref.read(dynamicColorProvider.notifier).setEnabled(value),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('关于'),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
          ),
        ],
      ),
    );
  }
}

Future<void> _pickDownloadDirectory(BuildContext context, WidgetRef ref) async {
  final selected = await StorageBridge.pickDirectory();
  if (selected == null || selected.isEmpty) return;
  await ref.read(downloadDirectoryProvider.notifier).setDirectory(selected);
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('下载路径已更新')));
}
