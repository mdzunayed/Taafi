import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/patient_home_repository.dart';
import '../../core/models/doctor_dashboard.dart';
import '../../core/models/doctor_stats.dart';
import '../admin/admin_providers.dart';
import '../auth/auth_provider.dart';
import 'services/location_tracking_service.dart';

/// Doctor heartbeat interval. 10 s — the spec calls for the assigned
/// visit to materialize "the moment the admin changes a request status
/// to matched/assigned", and 10 s is the fastest sensible cadence
/// without burning battery. Backed up by an explicit
/// `ref.invalidate(doctorDashboardProvider)` from the assign-team flow,
/// so a co-located doctor session sees the change in the same frame.
const _pollInterval = Duration(seconds: 10);

/// Single source of truth for the doctor dashboard. Implemented as an
/// [AutoDisposeAsyncNotifier] (spec compliance) — the screen sees a fast
/// loading shimmer on first paint, then `data` updates from the polling
/// timer with no UI jank.
///
/// The notifier owns its own poll timer so callers don't need to know
/// about it; tearing down the screen cancels the timer automatically via
/// `onDispose`.
class DoctorDashboardNotifier
    extends AutoDisposeAsyncNotifier<DoctorDashboard> {
  Timer? _poll;
  bool _polling = false;

  @override
  Future<DoctorDashboard> build() async {
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });
    final dio = ref.watch(dioClientProvider);
    // Diff-poll heartbeat. First paint shows the shimmer; subsequent
    // polls only write `state` when [_dashboardEqual] returns false.
    _poll ??= Timer.periodic(_pollInterval, (_) => _silentDiffPull());
    return dio.getDoctorDashboard();
  }

  /// Doctor-visible refresh — flips to loading so the shimmer reappears.
  /// Wired to pull-to-refresh and the error retry button.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getDoctorDashboard(),
    );
  }

  /// Background heartbeat — pulls `GET /doctor/dashboard`, compares to
  /// the current snapshot via [_dashboardEqual], and **only writes
  /// state when something user-visible has changed**. Identical
  /// payloads produce zero rebuilds, so the dashboard never flickers
  /// between polls and the doctor's scroll position survives.
  Future<void> _silentDiffPull() async {
    if (_polling) return; // overlap guard
    _polling = true;
    try {
      final fresh = await ref.read(dioClientProvider).getDoctorDashboard();
      debugPrint(
          '🩺 [DEBUG-DOCTOR]: Syncing active schedules. Items found: ${fresh.upcomingToday.length}');
      final current = state.valueOrNull;
      if (current == null || !_dashboardEqual(current, fresh)) {
        state = AsyncData(fresh);
      }
    } catch (e, _) {
      // Keep the last-good snapshot but surface poll failures during
      // backend bring-up instead of swallowing them silently.
      assert(() {
        debugPrint('[doctor] poll failed: $e');
        return true;
      }());
    } finally {
      _polling = false;
    }
  }

  /// Narrow equality. Compares the fields that actually re-render the
  /// dashboard (KPIs + pending-assignment id + Upcoming Today signature
  /// + availability) and ignores server-side jitter like `last_polled_at`
  /// or `updated_at` so identical-meaning payloads don't force rebuilds.
  bool _dashboardEqual(DoctorDashboard a, DoctorDashboard b) {
    if (a.todayEarnings != b.todayEarnings) return false;
    if (a.todayVisits != b.todayVisits) return false;
    if (a.weekEarnings != b.weekEarnings) return false;
    if (a.weekVisits != b.weekVisits) return false;
    if (a.rating != b.rating) return false;
    if (a.reviewCount != b.reviewCount) return false;
    if (a.unreadCount != b.unreadCount) return false;
    if (a.availability != b.availability) return false;
    if (a.pendingAssignment?.id != b.pendingAssignment?.id) return false;
    if (a.upcomingToday.length != b.upcomingToday.length) return false;
    for (var i = 0; i < a.upcomingToday.length; i++) {
      final x = a.upcomingToday[i];
      final y = b.upcomingToday[i];
      if (x.id != y.id) return false;
      if (x.startTime != y.startTime) return false;
    }
    return true;
  }
}

final doctorDashboardProvider =
    AsyncNotifierProvider.autoDispose<DoctorDashboardNotifier, DoctorDashboard>(
  DoctorDashboardNotifier.new,
);

/// Availability flag. Toggling it (a) optimistically updates the UI, (b)
/// hits the backend via [DioClient.setAvailability], and (c) starts/stops
/// the [LocationTrackingService] so coordinates flow only while ONLINE.
///
/// Rolls back on backend failure so the chip never lies to the doctor.
final doctorAvailabilityProvider =
    AsyncNotifierProvider.autoDispose<DoctorAvailabilityNotifier, bool>(
        DoctorAvailabilityNotifier.new);

class DoctorAvailabilityNotifier extends AutoDisposeAsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final dashboard = await ref.watch(doctorDashboardProvider.future);
    // If we restored a previously-online state, kick the tracker on next tick
    // so the doctor doesn't have to retoggle after a hot restart.
    if (dashboard.availability) {
      Future.microtask(() {
        ref.read(locationTrackingServiceProvider).start();
      });
    }
    return dashboard.availability;
  }

  Future<void> toggle() async {
    final current = state.valueOrNull ?? true;
    final next = !current;
    state = AsyncData(next);
    final tracker = ref.read(locationTrackingServiceProvider);
    try {
      await ref.read(dioClientProvider).setAvailability(next);
      if (next) {
        await tracker.start();
      } else {
        await tracker.stop();
      }
    } catch (e, st) {
      state = AsyncData(current);
      state = AsyncError(e, st);
    }
  }
}

/// Doctor taps "Accept" on an assigned visit. Backend flips the
/// `care_requests.status` from `assigned` → `enroute`. The cross-role
/// fan-out below makes that change visible in the patient's Under Review
/// card AND the admin's Live Monitor without anyone refreshing.
final acceptAssignmentProvider =
    FutureProvider.autoDispose.family<void, String>((ref, id) async {
  await ref.read(dioClientProvider).acceptAssignment(id);
  ref.invalidate(doctorDashboardProvider);
  // Admin Review Queue + Live Monitor reflect the status flip.
  ref.invalidate(adminRequestsProvider);
  // Patient's "Under Review" → "On the way" card.
  // ignore: unused_result
  await ref.read(patientHomeFeedProvider.notifier).refresh();
});

/// Doctor taps "Decline". Backend reverts the request to `approved` and
/// clears `assigned_doctor_id` so the admin can re-assign it.
final declineAssignmentProvider =
    FutureProvider.autoDispose.family<void, String>((ref, id) async {
  await ref.read(dioClientProvider).declineAssignment(id);
  ref.invalidate(doctorDashboardProvider);
  ref.invalidate(adminRequestsProvider);
  // ignore: unused_result
  await ref.read(patientHomeFeedProvider.notifier).refresh();
});

final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final initial = await connectivity.checkConnectivity();
  yield !initial.contains(ConnectivityResult.none);
  yield* connectivity.onConnectivityChanged
      .map((results) => !results.contains(ConnectivityResult.none));
});

/// Holds the appointment the doctor opened from the "Upcoming today" list.
/// The Active Service tab reads this so tapping a tile flips the segmented
/// control and renders that visit's details (address, patient, route).
///
/// Falls back to the pending assignment when null so the Active Service tab
/// always has something useful to render once the doctor has work.
final selectedActiveAppointmentProvider =
    StateProvider<UpcomingAppointment?>((_) => null);

// ─── Doctor stats (TODAY / WEEK / RATING tiles) ──────────────────────────────

/// Earnings + visit rollup polled on a 15 s heartbeat. Separate from
/// [doctorDashboardProvider] (which carries the upcoming list) so:
///   • The Active Service screen's "Complete Visit" handler can
///     invalidate JUST the stats and watch the money tile recompute
///     without re-fetching the dashboard's upcoming-visits list.
///   • The dashboard list's existing 10 s diff-poll doesn't get
///     short-circuited every time the money changes.
const _doctorStatsPollInterval = Duration(seconds: 15);

final doctorStatsProvider =
    AsyncNotifierProvider.autoDispose<DoctorStatsNotifier, DoctorStats>(
  DoctorStatsNotifier.new,
);

class DoctorStatsNotifier extends AutoDisposeAsyncNotifier<DoctorStats> {
  Timer? _poll;
  bool _polling = false;

  @override
  Future<DoctorStats> build() async {
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      throw StateError('Not signed in');
    }
    _poll ??=
        Timer.periodic(_doctorStatsPollInterval, (_) => _silentDiffPull());
    return ref.read(dioClientProvider).getDoctorStats(user.id);
  }

  Future<void> refresh() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getDoctorStats(user.id),
    );
  }

  /// Background diff-poll. Writes state only when the payload differs
  /// (`DoctorStats extends Equatable`), so steady-state idle minutes
  /// produce zero rebuilds and the dashboard stays jank-free.
  Future<void> _silentDiffPull() async {
    if (_polling) return;
    _polling = true;
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;
      final fresh = await ref.read(dioClientProvider).getDoctorStats(user.id);
      final current = state.valueOrNull;
      if (current == null || current != fresh) {
        state = AsyncData(fresh);
      }
    } catch (e) {
      assert(() {
        debugPrint('[doctor] stats poll failed: $e');
        return true;
      }());
    } finally {
      _polling = false;
    }
  }
}
