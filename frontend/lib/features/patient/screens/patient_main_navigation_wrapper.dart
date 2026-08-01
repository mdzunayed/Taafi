import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/presentation/widgets/custom_floating_navbar.dart';
import '../navigation/patient_nav_provider.dart';
import '../widgets/app_open_ad_interstitial.dart';
import 'new_request_tab.dart';
import 'patient_account_screen.dart';
import 'patient_activities_screen.dart';
import 'patient_home_screen.dart';

/// Root navigation shell for the patient app. The router mounts this
/// widget at `/patient/:name`; it owns the [Scaffold], the
/// [IndexedStack] body, and the [BottomNavigationBar].
///
/// Critical layout rules baked in:
///
/// 1. `IndexedStack` is the `body` — every tab destination is mounted
///    once, so jumping between Home and Activities preserves scroll
///    state and avoids re-fetching the API.
/// 2. The [BottomNavigationBar] is wired into the Scaffold's real
///    `bottomNavigationBar` slot (NOT inside the body), so the
///    framework anchors it at the absolute bottom edge of the
///    viewport — no floating, no centring inside the body column.
/// 3. The bar itself is wrapped in `SafeArea → Center → maxWidth: 600`
///    so on desktop / web the bar stays a sensible pill width while
///    its background colour still extends edge-to-edge. Mobile
///    sizes are unaffected (the Center collapses around the bar).
///
/// State lives in [patientNavProvider] (a `Notifier<int>`) so deep
/// link helpers across the app — the orange "Start new request"
/// banner, notification cards, the tracking screen's back button —
/// can flip destinations atomically without touching this widget.
class PatientMainNavigationWrapper extends ConsumerWidget {
  const PatientMainNavigationWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(patientNavProvider);
    final canvas = Theme.of(context).scaffoldBackgroundColor;

    // The interstitial sits ABOVE the whole Scaffold (nav bar included) so
    // an active app-open ad intercepts the first frame after launch; once
    // its countdown ends it latches itself off for the rest of the session.
    return Stack(
      children: [
        _buildShell(context, ref, currentIndex, canvas),
        const AppOpenAdInterstitial(),
      ],
    );
  }

  Widget _buildShell(
    BuildContext context,
    WidgetRef ref,
    int currentIndex,
    Color canvas,
  ) {
    return Scaffold(
      backgroundColor: canvas,
      // 1. Maintain screen state and render the actual complete sub-screens.
      body: IndexedStack(
        index: currentIndex,
        children: const [
          PatientHomeScreen(),       // Index 0: Restored complete dashboard view
          NewRequestTab(),           // Index 1: Intake workflow view
          PatientActivitiesScreen(), // Index 2: Consolidated Activities (tabs)
          PatientAccountScreen(),    // Index 3: Profile / account settings
        ],
      ),
      // 2. The floating capsule tray sits in the real `bottomNavigationBar`
      //    slot (not the body), so it anchors to the absolute bottom edge and
      //    every tab's own layout — including the New Request screen's bottom
      //    submit bar — stays intact. SafeArea, side margins and the wide-
      //    viewport width cap all live inside [CustomFloatingNavBar].
      // A canvas backdrop fills the whole bottom region (the band around the
      // floating pill + the bottom safe-area inset) so the tray meets the
      // body seamlessly in both themes — no mismatched Scaffold line showing
      // through. Uses the same theme canvas as the scaffold above.
      //
      // Only the three primary destinations live in the tray. The Account
      // destination is still mounted in the [IndexedStack] (index 3) and is
      // reached from the Home header avatar via `ref.goToAccount()` — so its
      // lifecycle is identical, it just no longer occupies a bottom-nav slot.
      // The bar renders with no active circle while the account screen is
      // showing.
      bottomNavigationBar: ColoredBox(
        color: canvas,
        child: CustomFloatingNavBar(
          currentIndex: currentIndex,
          onTap: (index) =>
              ref.read(patientNavProvider.notifier).changeTab(index),
          items: const [
            FloatingNavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Home',
            ),
            FloatingNavItem(
              icon: Icons.add_circle_outline_rounded,
              activeIcon: Icons.add_circle_rounded,
              label: 'New Request',
            ),
            FloatingNavItem(
              icon: Icons.analytics_outlined,
              activeIcon: Icons.analytics_rounded,
              label: 'Activities',
            ),
          ],
        ),
      ),
    );
  }
}
