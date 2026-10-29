import 'package:flowingpod/state/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// QR code login against the Bilibili web passport.
class QrLoginView extends ConsumerStatefulWidget {
  const QrLoginView({super.key});

  @override
  ConsumerState<QrLoginView> createState() => _QrLoginViewState();
}

class _QrLoginViewState extends ConsumerState<QrLoginView> {
  TabController? _tabs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = DefaultTabController.maybeOf(context);
    if (!identical(tabs, _tabs)) {
      _tabs?.removeListener(_syncActive);
      _tabs = tabs;
      _tabs?.addListener(_syncActive);
      _syncActive();
    }
  }

  /// The QR tab is the second one on the login page.
  void _syncActive() {
    if (!mounted) return;
    ref
        .read(qrLoginProvider.notifier)
        .setActive(_tabs == null || _tabs!.index == 1);
  }

  @override
  void dispose() {
    _tabs?.removeListener(_syncActive);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(qrLoginProvider);

    ref.listen(qrLoginProvider, (previous, next) {
      if (next.status == QrStatus.success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('登录成功')));
        Navigator.of(context).maybePop();
      }
    });

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _QrArea(state: state),
            const SizedBox(height: 24),
            Text(
              _statusText(state),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (state.status == QrStatus.expired ||
                state.status == QrStatus.failed)
              FilledButton.icon(
                onPressed: () => ref.read(qrLoginProvider.notifier).start(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('刷新二维码'),
              ),
          ],
        ),
      ),
    );
  }

  String _statusText(QrLoginViewState state) => switch (state.status) {
    QrStatus.loading => '正在获取二维码…',
    QrStatus.waiting => '请使用哔哩哔哩客户端扫描二维码',
    QrStatus.scanned => '扫描成功，请在手机上确认登录',
    QrStatus.expired => '二维码已过期，请点击刷新',
    QrStatus.success => '登录成功',
    QrStatus.failed => state.message ?? '登录失败，请重试',
  };
}

class _QrArea extends StatelessWidget {
  const _QrArea({required this.state});

  final QrLoginViewState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = state.qrContent;

    if (state.status == QrStatus.success) {
      return Icon(Icons.check_circle_rounded, size: 180, color: scheme.primary);
    }
    if (content == null) {
      return const SizedBox(
        width: 220,
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: QrImageView(
          data: content,
          size: 200,
          backgroundColor: Colors.white,
        ),
      ),
    );
  }
}
