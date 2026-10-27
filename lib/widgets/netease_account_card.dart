import 'package:flowingpod/features/login/netease_login_page.dart';
import 'package:flowingpod/state/netease_auth_controller.dart';
import 'package:flowingpod/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// NetEase Cloud Music account card on 我的.
class NeteaseAccountCard extends ConsumerWidget {
  const NeteaseAccountCard({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 8),
  });

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(neteaseAuthProvider);

    if (!auth.initialized) {
      return Padding(padding: margin, child: const LinearProgressIndicator());
    }
    final user = auth.user;
    return Card(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: user == null
            ? _LoggedOut(onLogin: () => _openLogin(context, ref))
            : _LoggedIn(
                name: user.nickname,
                avatarUrl: user.avatarUrl,
                isVip: user.isVip,
                onLogout: () => _confirmLogout(context, ref),
              ),
      ),
    );
  }

  static void _openLogin(BuildContext context, WidgetRef ref) {
    ref.read(neteaseSmsProvider.notifier).reset();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const NeteaseLoginPage()));
  }

  static Future<void> _confirmLogout(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = ref.read(neteaseAuthProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出网易云账号'),
        content: const Text('要退出网易云音乐账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await controller.logout();
    }
  }
}

class _LoggedOut extends StatelessWidget {
  const _LoggedOut({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const UserAvatar(size: 56),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('网易云音乐', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '登录后可同步歌单与喜欢的音乐',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      FilledButton(onPressed: onLogin, child: const Text('登录')),
    ],
  );
}

class _LoggedIn extends StatelessWidget {
  const _LoggedIn({
    required this.name,
    required this.avatarUrl,
    required this.isVip,
    required this.onLogout,
  });

  final String name;
  final String avatarUrl;
  final bool isVip;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        UserAvatar(url: avatarUrl, size: 60),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isVip) ...[
                const SizedBox(height: 6),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE54545).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      '黑胶VIP',
                      style: TextStyle(fontSize: 11, color: Color(0xFFE54545)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        OutlinedButton(onPressed: onLogout, child: const Text('退出登录')),
      ],
    );
  }
}
