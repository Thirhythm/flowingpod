import 'package:flowingpod/core/models/bili_user.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/widgets/account_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Signed-in controller that records logout calls instead of touching the API.
class _FakeAuthController extends AuthController {
  _FakeAuthController({this.name = '测试用户', this.signedIn = true});

  final String name;
  final bool signedIn;
  int logoutCalls = 0;

  @override
  AuthState build() => AuthState(
    initialized: true,
    user: signedIn ? BiliUser(mid: 42, name: name, level: 6, coins: 12) : null,
  );

  @override
  Future<void> logout() async => logoutCalls++;
}

Future<void> _pumpCard(WidgetTester tester, _FakeAuthController fake) async {
  await tester.pumpWidget(
    ProviderScope(
      // A fresh key forces a new container, so repeated pumps in one test pick
      // up the newly supplied controller.
      key: UniqueKey(),
      overrides: [authControllerProvider.overrideWith(() => fake)],
      child: const MaterialApp(home: Scaffold(body: AccountCard())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the logout button in the login button slot', (
    tester,
  ) async {
    final fake = _FakeAuthController();
    await _pumpCard(tester, fake);

    expect(find.text('测试用户'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '退出登录'), findsOneWidget);
    // The signed-out call to action must be gone.
    expect(find.widgetWithText(FilledButton, '登录'), findsNothing);
  });

  testWidgets('logout button is placed exactly where the login button is', (
    tester,
  ) async {
    await _pumpCard(tester, _FakeAuthController(signedIn: false));
    final loginRect = tester.getRect(find.widgetWithText(FilledButton, '登录'));

    await _pumpCard(tester, _FakeAuthController());
    final logoutRect = tester.getRect(
      find.widgetWithText(OutlinedButton, '退出登录'),
    );

    // Right aligned in the same row, so the trailing edge must line up.
    expect(logoutRect.right, moreOrLessEquals(loginRect.right, epsilon: 0.5));
  });

  testWidgets('cancelling the confirmation keeps the session', (tester) async {
    final fake = _FakeAuthController();
    await _pumpCard(tester, fake);

    await tester.tap(find.widgetWithText(OutlinedButton, '退出登录'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('要退出账号吗？'), findsOneWidget);
    expect(fake.logoutCalls, 0);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(fake.logoutCalls, 0);
    expect(find.text('测试用户'), findsOneWidget);
  });

  testWidgets('confirming the dialog logs out', (tester) async {
    final fake = _FakeAuthController();
    await _pumpCard(tester, fake);

    await tester.tap(find.widgetWithText(OutlinedButton, '退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(fake.logoutCalls, 1);
  });

  testWidgets('lays out without overflow on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // A long name plus the extra trailing button is the tightest case.
    final fake = _FakeAuthController(name: '一个非常非常长的哔哩哔哩用户名');
    await _pumpCard(tester, fake);

    expect(find.widgetWithText(OutlinedButton, '退出登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
