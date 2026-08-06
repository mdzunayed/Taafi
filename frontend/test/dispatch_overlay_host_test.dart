import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taafi/core/network/dispatch_overlay.dart';
import 'package:taafi/core/network/socket_manager.dart';
import 'package:taafi/features/auth/auth_provider.dart';

/// Exposes the state setter so a test can push a dispatch the way the socket
/// stream would.
class _TestDispatchAlerts extends DispatchAlertController {
  // ignore: use_super_parameters — the super ctor's parameter is a private
  // field formal (`this._ref`), which can't be forwarded from another library.
  _TestDispatchAlerts(Ref ref) : super(ref);

  void emit(DispatchAlert alert) => state = alert;
}

const _alert = DispatchAlert(
  appointmentId: '6a6f6cdfe88b4473d854bd7c',
  patientName: 'Md Zunayed',
  careType: 'Post-surgery care at Block C, banasree',
  role: 'doctor',
  deepLink: '/doctor',
);

void main() {
  late _TestDispatchAlerts alerts;

  /// Mirrors `main.dart`: the host is mounted from `MaterialApp.builder`, i.e.
  /// ABOVE the Navigator — the exact placement that left the banner without an
  /// Overlay ancestor.
  Future<void> pumpApp(WidgetTester tester, {VoidCallback? onBodyTap}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // No session in a widget test: keep the socket + notification hub
          // inert instead of reaching for storage or the network.
          currentUserProvider.overrideWithValue(null),
          socketManagerProvider.overrideWithValue(null),
          dispatchAlertProvider.overrideWith((ref) {
            alerts = _TestDispatchAlerts(ref);
            return alerts;
          }),
        ],
        child: MaterialApp(
          builder: (context, child) =>
              DispatchOverlayHost(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: onBodyTap ?? () {},
                child: const Text('Body button'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets the 12s auto-dismiss timer fire and the exit transition finish, so
  /// the test doesn't end with a pending timer.
  Future<void> drainAutoDismiss(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 13));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('incoming dispatch banner renders without an Overlay ancestor',
      (tester) async {
    await pumpApp(tester);

    alerts.emit(_alert);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Before the fix this threw "No Overlay widget found" while building the
    // dismiss button's Tooltip, and the card rendered as an ErrorWidget.
    expect(tester.takeException(), isNull);
    expect(find.text('Incoming dispatch'), findsOneWidget);
    expect(find.byTooltip('Dismiss'), findsOneWidget);

    await drainAutoDismiss(tester);
  });

  testWidgets('banner lays out on a narrow viewport without overflowing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpApp(tester);
    alerts.emit(_alert);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // A RenderFlex overflow surfaces as a FlutterError during paint.
    expect(tester.takeException(), isNull);
    expect(find.text('View'), findsOneWidget);

    await drainAutoDismiss(tester);
  });

  testWidgets('full-screen overlay layer does not swallow taps on the app',
      (tester) async {
    var bodyTaps = 0;
    await pumpApp(tester, onBodyTap: () => bodyTaps++);

    alerts.emit(_alert);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Body button'));
    await tester.pump();

    expect(bodyTaps, 1);

    await drainAutoDismiss(tester);
  });

  testWidgets('dismiss clears the banner', (tester) async {
    await pumpApp(tester);

    alerts.emit(_alert);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Incoming dispatch'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
