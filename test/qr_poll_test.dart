import 'package:flowingpod/core/api/bili_client.dart';
import 'package:flowingpod/data/repositories/auth_repository.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hands out a QR session and keeps answering "waiting", so the controller
/// keeps its two second poll timer running until it is disposed.
class _FakeQrRepository extends AuthRepository {
  _FakeQrRepository(super.client);

  int pollCalls = 0;

  @override
  Future<QrSession> createQrSession() async =>
      const QrSession(url: 'https://example.com/qr', key: 'key');

  @override
  Future<QrPollResult> pollQrSession(String key) async {
    pollCalls++;
    return const QrPollResult(QrLoginStatus.waiting);
  }
}

/// Stands in for the login page: it is the provider's only listener.
class _QrWatcher extends ConsumerWidget {
  const _QrWatcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(qrLoginProvider);
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('QR polling stops once the login page is gone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = await BiliClient.create();
    final repository = _FakeQrRepository(client);
    final overrides = [authRepositoryProvider.overrideWithValue(repository)];
    final showQr = ValueNotifier<bool>(true);
    addTearDown(showQr.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: ValueListenableBuilder<bool>(
          valueListenable: showQr,
          builder: (_, show, _) => MaterialApp(
            home: Scaffold(body: show ? const _QrWatcher() : const SizedBox()),
          ),
        ),
      ),
    );

    // The controller starts in a microtask and polls every two seconds.
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(repository.pollCalls, greaterThanOrEqualTo(1));

    // Leaving the page removes the only listener, so the auto-disposed provider
    // must cancel its timer instead of polling for the rest of the session.
    showQr.value = false;
    await tester.pump();
    await tester.pump();
    final callsAtClose = repository.pollCalls;

    await tester.pump(const Duration(seconds: 10));
    expect(repository.pollCalls, callsAtClose);
  });
}
