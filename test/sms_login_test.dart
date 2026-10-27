import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/api/bili_client.dart';
import 'package:flowingpod/data/repositories/auth_repository.dart';
import 'package:flowingpod/features/login/geetest_view.dart';
import 'package:flowingpod/features/login/login_page.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repository double that records phone-login calls instead of using the API.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(super.client);

  static const CaptchaChallenge challenge = CaptchaChallenge(
    token: 'token',
    gt: 'gt',
    challenge: 'challenge',
  );

  int captchaCalls = 0;
  int sendCalls = 0;
  int loginCalls = 0;
  String? lastTel;
  String? lastCode;
  String? lastCaptchaKey;
  String? lastChallenge;
  String? lastValidate;
  String? lastSeccode;
  BiliApiException? captchaError;
  BiliApiException? sendError;
  BiliApiException? loginError;

  @override
  Future<CaptchaChallenge> createCaptcha() async {
    captchaCalls++;
    final error = captchaError;
    if (error != null) throw error;
    return challenge;
  }

  @override
  Future<String> sendSmsCode({
    required String cid,
    required String tel,
    required CaptchaChallenge captcha,
    required String challenge,
    required String validate,
    required String seccode,
  }) async {
    sendCalls++;
    lastTel = tel;
    lastChallenge = challenge;
    lastValidate = validate;
    lastSeccode = seccode;
    final error = sendError;
    if (error != null) throw error;
    return 'captcha-key';
  }

  @override
  Future<void> loginWithSmsCode({
    required String cid,
    required String tel,
    required String code,
    required String captchaKey,
  }) async {
    loginCalls++;
    lastCode = code;
    lastCaptchaKey = captchaKey;
    final error = loginError;
    if (error != null) throw error;
  }

  // The QR flow is exercised elsewhere; failing fast keeps it timer-free here.
  @override
  Future<QrSession> createQrSession() async => throw const BiliApiException(
    code: -1,
    message: '测试环境不可用',
    path: '/qrcode/generate',
  );
}

/// Auth controller that records refreshes instead of calling the API.
class _FakeAuthController extends AuthController {
  int refreshCalls = 0;

  @override
  AuthState build() => const AuthState(initialized: true);

  @override
  Future<void> refresh() async => refreshCalls++;
}

/// Captures the callbacks the login page hands to the captcha widget.
class _CapturedCaptcha {
  CaptchaChallenge? challenge;
  GeetestCallbacks? callbacks;
}

class _Harness {
  _Harness(this.container, this.repository, this.auth);

  final ProviderContainer container;
  final _FakeAuthRepository repository;
  final _FakeAuthController auth;

  SmsLoginController get controller =>
      container.read(smsLoginProvider.notifier);
  SmsLoginViewState get state => container.read(smsLoginProvider);
}

Future<_Harness> _createHarness() async {
  SharedPreferences.setMockInitialValues({});
  final client = await BiliClient.create();
  final repository = _FakeAuthRepository(client);
  final auth = _FakeAuthController();
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(() => auth),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(container, repository, auth);
}

/// Stand-in for the WebView host: tests have no WebView platform.
Widget _stubCaptcha(
  _CapturedCaptcha captured,
  CaptchaChallenge challenge,
  GeetestCallbacks callbacks,
) {
  captured.challenge = challenge;
  captured.callbacks = callbacks;
  return const Text('captcha-stub');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmsLoginController', () {
    test('only accepts mainland numbers', () async {
      final harness = await _createHarness();
      final controller = harness.controller;

      controller.setTel('1380000');
      expect(harness.state.telValid, isFalse);
      expect(harness.state.canSendCode, isFalse);

      controller.setTel('13800000000');
      expect(harness.state.telValid, isTrue);
      expect(harness.state.canSendCode, isTrue);
    });

    test('shows the captcha and sends the code with its solution', () async {
      final harness = await _createHarness();
      final controller = harness.controller;
      controller.setTel('13800000000');

      expect(await controller.startCaptcha(), isTrue);
      expect(harness.repository.captchaCalls, 1);
      expect(harness.state.busy, isFalse);
      final captcha = harness.state.captcha;
      expect(captcha, isNotNull);
      // The captcha is on screen, so a second request cannot be started.
      expect(harness.state.canSendCode, isFalse);

      final sent = await controller.sendCode(
        captcha: captcha!,
        challenge: 'solved-challenge',
        validate: 'solved-validate',
        seccode: 'solved-validate|jordan',
      );

      expect(sent, isTrue);
      expect(harness.repository.sendCalls, 1);
      expect(harness.repository.lastTel, '13800000000');
      expect(harness.repository.lastChallenge, 'solved-challenge');
      expect(harness.repository.lastValidate, 'solved-validate');
      expect(harness.repository.lastSeccode, 'solved-validate|jordan');
      expect(harness.state.codeSent, isTrue);
      expect(harness.state.captcha, isNull);
      expect(harness.state.resendIn, SmsLoginController.resendDelay);
    });

    test('endCaptcha hides the captcha and reports an error', () async {
      final harness = await _createHarness();
      final controller = harness.controller;
      controller.setTel('13800000000');

      await controller.startCaptcha();
      expect(harness.state.captcha, isNotNull);

      controller.endCaptcha();
      expect(harness.state.captcha, isNull);
      expect(harness.state.message, isNull);
      expect(harness.state.canSendCode, isTrue);

      await controller.startCaptcha();
      controller.endCaptcha(error: '人机验证加载失败，请重试');
      expect(harness.state.captcha, isNull);
      expect(harness.state.message, '人机验证加载失败，请重试');
      expect(harness.state.busy, isFalse);
    });

    test('a captcha that cannot be requested leaves the form usable', () async {
      final harness = await _createHarness();
      final controller = harness.controller;
      controller.setTel('13800000000');
      harness.repository.captchaError = const BiliApiException(
        code: -1,
        message: '无法获取人机验证参数，请稍后重试',
      );

      expect(await controller.startCaptcha(), isFalse);
      expect(harness.state.captcha, isNull);
      expect(harness.state.busy, isFalse);
      expect(harness.state.message, '无法获取人机验证参数，请稍后重试');
      expect(harness.state.canSendCode, isTrue);
    });

    test('counts down and keeps the banner while it runs', () async {
      final harness = await _createHarness();
      final controller = harness.controller;
      controller.setTel('13800000000');
      await controller.startCaptcha();
      final captcha = harness.state.captcha;
      await controller.sendCode(
        captcha: captcha!,
        challenge: 'c',
        validate: 'v',
        seccode: 's',
      );

      expect(harness.state.canSendCode, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(harness.state.resendIn, SmsLoginController.resendDelay - 1);
      expect(harness.state.canSendCode, isFalse);

      // A failed login must stay visible while the countdown keeps ticking.
      harness.repository.loginError = const BiliApiException(
        code: 1006,
        message: '短信验证码错误，请重新输入',
      );
      controller.setCode('000000');
      await controller.submitCode();
      expect(harness.state.message, '短信验证码错误，请重新输入');

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(harness.state.message, '短信验证码错误，请重新输入');
    });

    test('reports the failure message coming from the repository', () async {
      final harness = await _createHarness();
      final controller = harness.controller;
      controller.setTel('13800000000');
      harness.repository.sendError = const BiliApiException(
        code: 1002,
        message: '手机号格式错误',
      );

      await controller.startCaptcha();
      final captcha = harness.state.captcha;
      final sent = await controller.sendCode(
        captcha: captcha!,
        challenge: 'c',
        validate: 'v',
        seccode: 's',
      );

      expect(sent, isFalse);
      expect(harness.state.message, '手机号格式错误');
      expect(harness.state.codeSent, isFalse);
    });

    test('requires a code to be requested before logging in', () async {
      final harness = await _createHarness();
      final controller = harness.controller;
      controller.setTel('13800000000');

      expect(await controller.submitCode(), isFalse);
      expect(harness.repository.loginCalls, 0);
      expect(harness.state.message, '请先获取短信验证码');
    });

    test('reset drops the previous attempt', () async {
      final harness = await _createHarness();
      final controller = harness.controller;
      controller.setTel('13800000000');
      await controller.startCaptcha();
      final captcha = harness.state.captcha;
      await controller.sendCode(
        captcha: captcha!,
        challenge: 'c',
        validate: 'v',
        seccode: 's',
      );
      controller.setCode('123456');

      controller.reset();

      expect(harness.state.tel, isEmpty);
      expect(harness.state.code, isEmpty);
      expect(harness.state.codeSent, isFalse);
      expect(harness.state.captcha, isNull);
      expect(harness.state.resendIn, 0);
      expect(harness.state.canSubmit, isFalse);
    });

    test('logs in with the received code and refreshes the account', () async {
      final harness = await _createHarness();
      final controller = harness.controller;
      controller.setTel('13800000000');
      await controller.startCaptcha();
      final captcha = harness.state.captcha;
      await controller.sendCode(
        captcha: captcha!,
        challenge: 'c',
        validate: 'v',
        seccode: 's',
      );
      controller.setCode('123456');

      expect(harness.state.canSubmit, isTrue);
      expect(await controller.submitCode(), isTrue);

      expect(harness.repository.lastCode, '123456');
      expect(harness.repository.lastCaptchaKey, 'captcha-key');
      expect(harness.auth.refreshCalls, 1);
      expect(harness.state.succeeded, isTrue);
    });
  });

  group('LoginPage', () {
    Future<void> pumpLogin(WidgetTester tester, _Harness harness) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(home: LoginPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens on phone verification', (tester) async {
      final harness = await _createHarness();
      await pumpLogin(tester, harness);

      expect(find.text('手机号登录'), findsOneWidget);
      expect(find.text('扫码登录'), findsOneWidget);
      expect(find.widgetWithText(TextField, '手机号'), findsOneWidget);
      expect(find.widgetWithText(TextField, '短信验证码'), findsOneWidget);
      expect(find.text('获取验证码'), findsOneWidget);

      // Nothing can be requested or submitted before a number is typed.
      final resend = find.widgetWithText(TextButton, '获取验证码');
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '登录'))
            .onPressed,
        isNull,
      );

      // The captcha is not shown until it is asked for.
      expect(find.byType(GeetestView), findsNothing);
    });
  });

  // The captcha itself needs a WebView, which has no platform implementation
  // under `flutter test`, so a stub is injected to exercise the page layout.
  group('LoginPage captcha host', () {
    Future<_CapturedCaptcha> pumpStubLogin(
      WidgetTester tester,
      _Harness harness,
    ) async {
      final captured = _CapturedCaptcha();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            home: LoginPage(
              captchaBuilder: (challenge, callbacks) =>
                  _stubCaptcha(captured, challenge, callbacks),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '手机号'),
        '13800000000',
      );
      await tester.pump();
      await tester.tap(find.text('获取验证码'));
      await tester.pumpAndSettle();
      return captured;
    }

    testWidgets('shows the captcha in the page instead of a new one', (
      tester,
    ) async {
      final harness = await _createHarness();
      final captured = await pumpStubLogin(tester, harness);

      expect(harness.repository.captchaCalls, 1);
      // Still the login page: its app bar is on screen, next to the captcha.
      expect(find.text('登录哔哩哔哩'), findsOneWidget);
      expect(find.text('请完成安全验证'), findsOneWidget);
      expect(find.text('captcha-stub'), findsOneWidget);
      expect(captured.challenge?.challenge, 'challenge');
      expect(captured.callbacks, isNotNull);

      // The form gives way to the captcha, and the tab bar steps aside so the
      // captcha gets the full height it needs.
      expect(find.widgetWithText(TextField, '手机号'), findsNothing);
      expect(find.widgetWithText(TextField, '短信验证码'), findsNothing);
      expect(find.text('扫码登录'), findsNothing);
    });

    testWidgets('取消 brings the form and the tabs back', (tester) async {
      final harness = await _createHarness();
      await pumpStubLogin(tester, harness);

      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(find.text('captcha-stub'), findsNothing);
      expect(find.widgetWithText(TextField, '手机号'), findsOneWidget);
      expect(find.text('手机号登录'), findsOneWidget);
      expect(find.text('扫码登录'), findsOneWidget);
      expect(harness.state.captcha, isNull);
      expect(harness.state.canSendCode, isTrue);
    });

    testWidgets('solving the captcha sends the code', (tester) async {
      final harness = await _createHarness();
      final captured = await pumpStubLogin(tester, harness);

      captured.callbacks!.onSolved(
        const GeetestResult(challenge: 'c', validate: 'v', seccode: 's'),
      );
      await tester.pumpAndSettle();

      expect(harness.repository.sendCalls, 1);
      expect(find.text('captcha-stub'), findsNothing);
      expect(find.textContaining('重新发送('), findsOneWidget);

      // Let the resend countdown run out so no timer outlives the test.
      await tester.pump(
        const Duration(seconds: SmsLoginController.resendDelay + 1),
      );
    });

    testWidgets('a captcha that cannot load is reported on the form', (
      tester,
    ) async {
      final harness = await _createHarness();
      final captured = await pumpStubLogin(tester, harness);

      captured.callbacks!.onFailed('人机验证加载失败，请重试');
      await tester.pumpAndSettle();

      expect(find.text('captcha-stub'), findsNothing);
      expect(find.widgetWithText(TextField, '手机号'), findsOneWidget);
      expect(find.text('人机验证加载失败，请重试'), findsOneWidget);
      expect(harness.state.canSendCode, isTrue);
    });

    testWidgets('logs in after a code has been verified', (tester) async {
      final harness = await _createHarness();
      final captured = await pumpStubLogin(tester, harness);

      captured.callbacks!.onSolved(
        const GeetestResult(challenge: 'c', validate: 'v', seccode: 's'),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '短信验证码'),
        '123456',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(harness.repository.lastCode, '123456');
      expect(harness.auth.refreshCalls, 1);
      expect(find.text('登录成功'), findsOneWidget);

      await tester.pump(
        const Duration(seconds: SmsLoginController.resendDelay + 1),
      );
    });
  });
}
