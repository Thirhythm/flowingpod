import 'package:flowingpod/features/login/geetest_view.dart';
import 'package:flowingpod/features/login/qr_login_view.dart';
import 'package:flowingpod/features/login/sms_login_view.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Login entry point.
///
/// Phone verification is the default; scanning a QR code remains available for
/// accounts that cannot receive SMS codes.
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key, this.captchaBuilder = buildGeetestView});

  /// Builds the captcha widget; overridable so widget tests can run without a
  /// WebView platform.
  final CaptchaBuilder captchaBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The captcha needs every pixel it can get, so the tab bar steps aside
    // while it is being solved.
    final verifying = ref.watch(
      smsLoginProvider.select((state) => state.captcha != null),
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('登录哔哩哔哩'),
          bottom: verifying
              ? null
              : const TabBar(
                  tabs: [
                    Tab(text: '手机号登录'),
                    Tab(text: '扫码登录'),
                  ],
                ),
        ),
        body: TabBarView(
          children: [
            SmsLoginView(captchaBuilder: captchaBuilder),
            const QrLoginView(),
          ],
        ),
      ),
    );
  }
}