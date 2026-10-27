import 'package:flowingpod/core/models/bili_user.dart';
import 'package:flowingpod/core/utils/formatters.dart';
import 'package:flowingpod/features/login/login_page.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Account summary used by the profile page.
class AccountCard extends ConsumerWidget {
  const AccountCard({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 4),
  });

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    if (!auth.initialized) {
      return Padding(
        padding: margin,
        child: const LinearProgressIndicator(),
      );
    }
    final user = auth.user;
    return Card(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: user == null
            ? _LoggedOut(onLogin: () => _openLogin(context, ref))
            : _LoggedIn(
                user: user,
                onLogout: () => _confirmLogout(context, ref),
              ),
      ),
    );
  }

  /// Opens the login page, starting a fresh phone-login attempt.
  static void _openLogin(BuildContext context, WidgetRef ref) {
    ref.read(smsLoginProvider.notifier).reset();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
  }

  /// Asks for confirmation, then drops the session.
  ///
  /// The controller is read before the dialog is awaited so the callback never
  /// touches `ref` across an async gap.
  static Future<void> _confirmLogout(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = ref.read(authControllerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('要退出账号吗？'),
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
            Text('未登录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '登录后可同步歌单与观看历史',
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
  const _LoggedIn({required this.user, required this.onLogout});

  final BiliUser user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        UserAvatar(url: user.face, size: 60),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _Tag(text: 'LV${user.level}'),
                  if (user.isVip) const _Tag(text: '大会员'),
                  _Tag(text: '硬币 ${user.coins.toStringAsFixed(0)}'),
                ],
              ),
              if (user.follower != null) ...[
                const SizedBox(height: 6),
                Text(
                  '粉丝 ${Formatters.count(user.follower!)} · '
                  '关注 ${Formatters.count(user.following ?? 0)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        // Sits in the same slot as the login button of the signed-out card.
        OutlinedButton(
          onPressed: onLogout,
          child: const Text('退出登录'),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
