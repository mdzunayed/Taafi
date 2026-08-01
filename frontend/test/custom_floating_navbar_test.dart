import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taafi/features/navigation/presentation/widgets/custom_floating_navbar.dart';

/// Regression tests for the shared floating capsule bar. These re-cover the
/// behaviours the deleted CustomCapsuleNavBar / FluidNavBar tests guarded,
/// plus the badge + narrow-viewport behaviour the doctor/nurse shells need:
///   1. In `Scaffold.bottomNavigationBar` (loose 0..screenHeight constraints)
///      the bar sizes to its intrinsic height — the `Align(heightFactor: 1)`
///      trap — instead of ballooning to full screen.
///   2. It survives a `currentIndex` past the visible items (the patient
///      Account screen is IndexedStack index 3 while the tray has 3 slots)
///      and renders no active circle.
///   3. Taps report the slot index (via Semantics — the bar is icon-only).
///   4. Badge counts render, clamp to `9+`, and hide at zero.
///   5. Five slots fit a 320-logical-width screen without overflow.
void main() {
  const items = [
    FloatingNavItem(
        icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
    FloatingNavItem(icon: Icons.add_circle_outline_rounded, label: 'New Request'),
    FloatingNavItem(icon: Icons.analytics_outlined, label: 'Activities'),
  ];

  Widget harness({
    required int currentIndex,
    required ValueChanged<int> onTap,
    List<FloatingNavItem> navItems = items,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: const Center(child: Text('BODY_CONTENT')),
        bottomNavigationBar: CustomFloatingNavBar(
          currentIndex: currentIndex,
          onTap: onTap,
          items: navItems,
        ),
      ),
    );
  }

  /// Every circle currently painted with the solid orange active fill.
  Finder activeCircles(WidgetTester tester) {
    return find.byWidgetPredicate((w) {
      if (w is! AnimatedContainer) return false;
      final deco = w.decoration;
      return deco is BoxDecoration &&
          deco.shape == BoxShape.circle &&
          deco.color == const Color(0xFFF36512);
    });
  }

  testWidgets('reports intrinsic height in the bottomNavigationBar slot',
      (tester) async {
    await tester.pumpWidget(harness(currentIndex: 0, onTap: (_) {}));

    final screenH =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final navSize = tester.getSize(find.byType(CustomFloatingNavBar));

    // Bar must be a slim strip, nowhere near full screen height.
    expect(navSize.height, lessThan(120),
        reason:
            'nav bar should be intrinsic height, got ${navSize.height} of $screenH');

    // The body content must still be visible (not squeezed to zero).
    expect(find.text('BODY_CONTENT'), findsOneWidget);
    final bodyRect = tester.getRect(find.text('BODY_CONTENT'));
    expect(bodyRect.center.dy, lessThan(screenH * 0.6),
        reason: 'body should occupy the upper area, above the bottom bar');
  });

  testWidgets('exactly one active circle for an in-range index',
      (tester) async {
    await tester.pumpWidget(harness(currentIndex: 1, onTap: (_) {}));
    await tester.pumpAndSettle();

    expect(activeCircles(tester), findsOneWidget);
  });

  testWidgets(
      'currentIndex past the visible items (Account open) renders no active '
      'circle and does not throw', (tester) async {
    // Index 3 = the patient Account destination, which has no tray slot.
    await tester.pumpWidget(harness(currentIndex: 3, onTap: (_) {}));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(activeCircles(tester), findsNothing);
  });

  testWidgets('tapping a slot reports its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(harness(currentIndex: 0, onTap: (i) => tapped = i));

    await tester.tap(find.bySemanticsLabel('Activities'));
    expect(tapped, 2);

    await tester.tap(find.bySemanticsLabel('New Request'));
    expect(tapped, 1);
  });

  testWidgets('badge renders, clamps above 9, and hides at zero',
      (tester) async {
    const badged = [
      FloatingNavItem(icon: Icons.home_outlined, label: 'Home', badgeCount: 12),
      FloatingNavItem(icon: Icons.history, label: 'History', badgeCount: 3),
      FloatingNavItem(icon: Icons.person, label: 'Profile'),
    ];
    await tester.pumpWidget(
        harness(currentIndex: 0, onTap: (_) {}, navItems: badged));
    await tester.pumpAndSettle();

    expect(find.text('9+'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // Only the two non-zero counts render bubbles — no stray text elsewhere.
    expect(find.text('0'), findsNothing);
  });

  testWidgets('five slots fit a 320-wide screen without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const fiveItems = [
      FloatingNavItem(icon: Icons.assignment_outlined, label: 'Appointments'),
      FloatingNavItem(icon: Icons.assignment_ind_outlined, label: 'EHR'),
      FloatingNavItem(icon: Icons.healing_outlined, label: 'Prescriber'),
      FloatingNavItem(icon: Icons.calendar_month_outlined, label: 'Schedule'),
      FloatingNavItem(icon: Icons.analytics_outlined, label: 'Earnings'),
    ];
    await tester.pumpWidget(
        harness(currentIndex: 0, onTap: (_) {}, navItems: fiveItems));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
