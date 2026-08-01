import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Re-exports `nurseDashboardProvider` (the shared Dispatches feed) so the
// incoming-dispatch derivation below can ride the exact same cache the
// Dispatches tab renders from — one source of truth, no drift.
import '../../../provider/providers/nurse_workflow_provider.dart';

/// Canonical tab indices for the Nurse Operations shell. Kept as named
/// constants so cross-tab shortcuts (e.g. the Profile screen jumping to
/// Earnings) never hard-code a magic number that silently rots if the tab
/// order is ever reshuffled.
class NurseTab {
  NurseTab._();

  /// Tab 0 — incoming/active field dispatches + the on-duty toggle.
  static const int dispatches = 0;

  /// Tab 1 — completed home-care procedure logs.
  static const int history = 1;

  /// Tab 2 — earnings, bonuses and the withdraw module.
  static const int earnings = 2;

  /// Tab 3 — professional profile & account console.
  static const int profile = 3;

  /// Total destination count — used to clamp/validate selections.
  static const int count = 4;
}

/// The single source of truth for which Nurse Operations tab is on screen.
///
/// Lifting the selected index into Riverpod (instead of `setState` inside the
/// shell) is what lets *any* descendant — most importantly the Profile
/// console's "Go on duty" / "Open earnings" shortcuts — drive navigation
/// without an `InheritedWidget`/callback chain threaded through the tree.
final nurseNavProvider =
    StateNotifierProvider<NurseNavController, int>((ref) => NurseNavController());

/// Holds + mutates the active tab index. Every switch fires a light haptic so
/// tab changes feel tactile and intentional, matching the rest of the nurse
/// workspace's "responsive to touch" brief.
class NurseNavController extends StateNotifier<int> {
  NurseNavController() : super(NurseTab.dispatches);

  /// Move to [index]. No-ops on an out-of-range value or a re-tap of the
  /// current tab (so we never buzz the device for a no-change tap).
  void select(int index) {
    if (index < 0 || index >= NurseTab.count || index == state) return;
    HapticFeedback.lightImpact();
    state = index;
  }

  /// Shortcut → Dispatches Dashboard (used by the Profile "Duty/Status" row
  /// and the active-job flash banner).
  void openDispatches() => select(NurseTab.dispatches);

  /// Shortcut → Earnings & Compensation Ledger (Profile "Earnings" row).
  void openEarnings() => select(NurseTab.earnings);

  /// Shortcut → Profile & Account Console.
  void openProfile() => select(NurseTab.profile);
}

/// Number of dispatches currently *awaiting the nurse's acceptance*.
///
/// Derived from the same dashboard cache the Dispatches tab renders, so the
/// nav badge and the active-job flash banner can never disagree with what's
/// actually on the board. Counts both freshly-assigned visits and a live
/// `pendingAssignment` offer. Returns `0` while loading or on error.
final nurseIncomingCountProvider = Provider.autoDispose<int>((ref) {
  final async = ref.watch(nurseDashboardProvider);
  return async.maybeWhen(
    data: (dashboard) {
      var n =
          dashboard.upcomingToday.where((a) => a.awaitingAcceptance).length;
      if (dashboard.pendingAssignment != null) n += 1;
      return n;
    },
    orElse: () => 0,
  );
});
