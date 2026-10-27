import 'package:flowingpod/data/repositories/auth_repository.dart';
import 'package:flowingpod/features/login/geetest_view.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phone verification form: number → geetest → SMS code → login.
///
/// The captcha is hosted inline, in the place of the form, so the login page
/// stays on screen while the user is verifying.
class SmsLoginView extends ConsumerStatefulWidget {
  const SmsLoginView({super.key, this.captchaBuilder = buildGeetestView});

  /// Builds the captcha widget; overridable so widget tests can run without a
  /// WebView platform.
  final CaptchaBuilder captchaBuilder;

  @override
  ConsumerState<SmsLoginView> createState() => _SmsLoginViewState();
}

class _SmsLoginViewState extends ConsumerState<SmsLoginView> {
  final TextEditingController _telController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The form state outlives this widget, so restore what was typed before.
    final state = ref.read(smsLoginProvider);
    _telController.text = state.tel;
    _codeController.text = state.code;
  }

  @override
  void dispose() {
    _telController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _requestCode() {
    // The captcha needs the whole area, so the keyboard has to go first.
    FocusScope.of(context).unfocus();
    ref.read(smsLoginProvider.notifier).startCaptcha();
  }

  /// Reaction to a solved, dismissed or failed captcha.
  GeetestCallbacks _captchaCallbacks(CaptchaChallenge captcha) {
    final controller = ref.read(smsLoginProvider.notifier);
    return GeetestCallbacks(
      onSolved: (result) => controller.sendCode(
        captcha: captcha,
        challenge: result.challenge,
        validate: result.validate,
        seccode: result.seccode,
      ),
      onClosed: controller.endCaptcha,
      onFailed: (message) => controller.endCaptcha(error: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smsLoginProvider);
    final controller = ref.read(smsLoginProvider.notifier);

    ref.listen(smsLoginProvider, (previous, next) {
      if (next.succeeded && !(previous?.succeeded ?? false)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('登录成功')));
        Navigator.of(context).maybePop();
      }
    });

    final captcha = state.captcha;
    if (captcha != null) {
      return _CaptchaArea(
        onCancel: controller.endCaptcha,
        child: widget.captchaBuilder(captcha, _captchaCallbacks(captcha)),
      );
    }
    return _Form(
      state: state,
      telController: _telController,
      codeController: _codeController,
      onTelChanged: controller.setTel,
      onCodeChanged: controller.setCode,
      onRequestCode: _requestCode,
      onSubmit: controller.submitCode,
    );
  }
}

/// Full-area host for the captcha widget.
///
/// The geetest panel needs roughly 400 logical pixels of height at phone widths
/// before its confirm button is pushed out of view, so the header is kept as
/// short as possible.
class _CaptchaArea extends StatelessWidget {
  const _CaptchaArea({required this.child, required this.onCancel});

  final Widget child;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '请完成安全验证',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
      Expanded(child: child),
    ],
  );
}

class _Form extends StatelessWidget {
  const _Form({
    required this.state,
    required this.telController,
    required this.codeController,
    required this.onTelChanged,
    required this.onCodeChanged,
    required this.onRequestCode,
    required this.onSubmit,
  });

  final SmsLoginViewState state;
  final TextEditingController telController;
  final TextEditingController codeController;
  final ValueChanged<String> onTelChanged;
  final ValueChanged<String> onCodeChanged;
  final VoidCallback onRequestCode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: telController,
              keyboardType: TextInputType.phone,
              maxLength: 11,
              onChanged: onTelChanged,
              decoration: const InputDecoration(
                labelText: '手机号',
                prefixText: '+$smsDialCode ',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              onChanged: onCodeChanged,
              decoration: InputDecoration(
                labelText: '短信验证码',
                counterText: '',
                border: const OutlineInputBorder(),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton(
                    onPressed: state.canSendCode ? onRequestCode : null,
                    child: Text(
                      state.resendIn > 0
                          ? '重新发送(${state.resendIn}s)'
                          : '获取验证码',
                    ),
                  ),
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 0),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: state.canSubmit ? onSubmit : null,
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
            const SizedBox(height: 16),
            Text(
              '未注册的手机号验证后将自动创建账号',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
