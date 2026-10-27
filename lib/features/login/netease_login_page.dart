import 'package:flowingpod/state/netease_auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// NetEase Cloud Music login: phone verification or QR code.
class NeteaseLoginPage extends StatelessWidget {
  const NeteaseLoginPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('登录网易云音乐'),
        bottom: const TabBar(
          tabs: [
            Tab(text: '扫码登录（推荐）'),
            Tab(text: '手机号登录'),
          ],
        ),
      ),
      body: const TabBarView(children: [_QrLoginView(), _PhoneLoginView()]),
    ),
  );
}

class _QrLoginView extends ConsumerStatefulWidget {
  const _QrLoginView();

  @override
  ConsumerState<_QrLoginView> createState() => _QrLoginViewState();
}

class _QrLoginViewState extends ConsumerState<_QrLoginView> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(neteaseQrProvider.notifier).start());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(neteaseQrProvider);

    ref.listen(neteaseQrProvider, (previous, next) {
      if (next.status == NeteaseQrViewStatus.success) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('登录成功')));
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
            if (state.status == NeteaseQrViewStatus.expired ||
                state.status == NeteaseQrViewStatus.failed)
              FilledButton.icon(
                onPressed: () => ref.read(neteaseQrProvider.notifier).start(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('刷新二维码'),
              ),
          ],
        ),
      ),
    );
  }

  String _statusText(NeteaseQrViewState state) => switch (state.status) {
    NeteaseQrViewStatus.loading => '正在获取二维码…',
    NeteaseQrViewStatus.waiting => '请使用网易云音乐 App 扫描二维码',
    NeteaseQrViewStatus.scanned => '扫描成功，请在手机上确认登录',
    NeteaseQrViewStatus.expired => '二维码已过期，请点击刷新',
    NeteaseQrViewStatus.success => '登录成功',
    NeteaseQrViewStatus.failed => state.message ?? '登录失败，请重试',
  };
}

class _QrArea extends StatelessWidget {
  const _QrArea({required this.state});

  final NeteaseQrViewState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = state.qrContent;

    if (state.status == NeteaseQrViewStatus.success) {
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

class _PhoneLoginView extends ConsumerStatefulWidget {
  const _PhoneLoginView();

  @override
  ConsumerState<_PhoneLoginView> createState() => _PhoneLoginViewState();
}

class _PhoneLoginViewState extends ConsumerState<_PhoneLoginView> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final state = ref.read(neteaseSmsProvider);
    _phoneController.text = state.phone;
    _codeController.text = state.code;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(neteaseSmsProvider);
    final controller = ref.read(neteaseSmsProvider.notifier);
    final theme = Theme.of(context);

    ref.listen(neteaseSmsProvider, (previous, next) {
      if (next.succeeded && !(previous?.succeeded ?? false)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('登录成功')));
        Navigator.of(context).maybePop();
      }
    });

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 11,
              onChanged: controller.setPhone,
              decoration: const InputDecoration(
                labelText: '手机号',
                prefixText: '+86 ',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              onChanged: controller.setCode,
              decoration: InputDecoration(
                labelText: '短信验证码',
                counterText: '',
                border: const OutlineInputBorder(),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton(
                    onPressed: state.canSendCode ? controller.sendCode : null,
                    child: Text(
                      state.resendIn > 0 ? '重新发送(${state.resendIn}s)' : '获取验证码',
                    ),
                  ),
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 0),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: state.canSubmit ? controller.submit : null,
              child: state.busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录'),
            ),
            if (state.message != null) ...[
              const SizedBox(height: 16),
              Text(
                state.message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
