import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/dio_client.dart';
import '../../core/models/admin_chart_data.dart';
import '../../core/models/admin_models.dart';
import '../../core/models/admin_patient_detail.dart';
import '../../core/models/doctor_profile.dart';
import '../../core/models/prescription.dart';
import '../../core/models/provider_cash_ledger.dart';
import '../../core/models/provider_update_otp_dispatch.dart';
import '../../core/models/provider_wallet.dart';
import '../../core/models/user.dart';
import '../auth/auth_provider.dart';

// ─── KPI Dashboard ───────────────────────────────────────────────────────────

/// Admin Overview KPI cards (Active Services / Pending Approvals /
/// Emergency Alerts / Daily Revenue) refresh on a 15 s heartbeat. The
/// metric tiles need to react to services completing in the real world
/// without a manual refresh, but they don't need second-by-second
/// granularity — 15 s is a clean balance: roughly 4 polls/min/admin tab
/// against MongoDB's indexed `status` + `created_at` queries.
const _adminStatsPollInterval = Duration(seconds: 15);

/// Drop-in replacement for the prior `FutureProvider<AdminKpi>`. Same
/// public name (`adminKpiProvider`) so the existing Overview tab and the
/// header badge that read `kpi.activeServices` keep working without
/// touching their call sites.
final adminKpiProvider =
    AsyncNotifierProvider<AdminKpiNotifier, AdminKpi>(AdminKpiNotifier.new);

class AdminKpiNotifier extends AsyncNotifier<AdminKpi> {
  Timer? _poll;
  bool _polling = false;

  @override
  Future<AdminKpi> build() async {
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });
    _poll ??=
        Timer.periodic(_adminStatsPollInterval, (_) => _silentDiffPull());
    return ref.read(dioClientProvider).getAdminKpi();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getAdminKpi(),
    );
  }

  /// Background diff-poll. Compares the new payload against the cached
  /// one via `Equatable` (`AdminKpi extends Equatable`) and only writes
  /// state when the numbers actually changed. Identical payloads = zero
  /// rebuilds = the KPI cards don't pulse their scale-in animation on
  /// every tick.
  Future<void> _silentDiffPull() async {
    if (_polling) return;
    _polling = true;
    try {
      final fresh = await ref.read(dioClientProvider).getAdminKpi();
      final current = state.valueOrNull;
      if (current == null || current != fresh) {
        state = AsyncData(fresh);
      }
    } catch (e) {
      assert(() {
        debugPrint('[admin] kpi poll failed: $e');
        return true;
      }());
    } finally {
      _polling = false;
    }
  }
}

// ─── Prescription release approvals ─────────────────────────────────────────

/// The Rx Approvals queue: PAID prescriptions awaiting the explicit
/// admin decision that unlocks (or rejects) them for the patient.
/// Same 15 s diff-poll heartbeat as the KPI cards so a fresh unlock
/// payment surfaces without a manual refresh.
final adminPrescriptionQueueProvider = AsyncNotifierProvider<
    AdminPrescriptionQueueNotifier,
    List<Prescription>>(AdminPrescriptionQueueNotifier.new);

class AdminPrescriptionQueueNotifier
    extends AsyncNotifier<List<Prescription>> {
  Timer? _poll;
  bool _polling = false;

  @override
  Future<List<Prescription>> build() async {
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });
    _poll ??=
        Timer.periodic(_adminStatsPollInterval, (_) => _silentDiffPull());
    return ref.read(dioClientProvider).adminGetPrescriptionReviewQueue();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).adminGetPrescriptionReviewQueue(),
    );
  }

  Future<void> _silentDiffPull() async {
    if (_polling) return;
    _polling = true;
    try {
      final fresh =
          await ref.read(dioClientProvider).adminGetPrescriptionReviewQueue();
      final current = state.valueOrNull;
      if (current == null || !listEquals(current, fresh)) {
        state = AsyncData(fresh);
      }
    } catch (e) {
      assert(() {
        debugPrint('[admin] rx approval poll failed: $e');
        return true;
      }());
    } finally {
      _polling = false;
    }
  }

  /// Optimistically removes the decided row, then writes through.
  /// Rolls back and rethrows on failure so the tab can surface a snack
  /// — same contract as [AdminRequestsNotifier.bulkUpdateStatus].
  Future<void> decide(
    String prescriptionId, {
    required bool approve,
    String? reason,
  }) async {
    final previous = state.valueOrNull;
    if (previous == null) return;
    state = AsyncData([
      for (final p in previous)
        if (p.id != prescriptionId) p,
    ]);
    try {
      await ref.read(dioClientProvider).adminSetPrescriptionApproval(
            prescriptionId,
            approve: approve,
            reason: reason,
          );
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}

/// Decided-history feeds for the tab's Approved / Rejected filter chips.
/// Plain autoDispose fetches — history doesn't need the poll heartbeat.
final adminPrescriptionHistoryProvider = FutureProvider.autoDispose
    .family<List<Prescription>, String>((ref, status) async {
  return ref
      .read(dioClientProvider)
      .adminGetPrescriptionReviewQueue(status: status);
});

/// Live operations telemetry for the four Overview metric cards, sourced
/// from the dedicated `$facet` endpoint `GET /api/admin/dashboard-telemetry`
/// (Phase 1). Polls on the same 15 s heartbeat as [adminKpiProvider] but is
/// kept as a separate provider so the cards + the "Live activity" connection
/// pulse can key off this specific feed's health without entangling the
/// legacy KPI surface. Same [AdminKpi] shape.
final dashboardTelemetryProvider =
    AsyncNotifierProvider<DashboardTelemetryNotifier, AdminKpi>(
        DashboardTelemetryNotifier.new);

class DashboardTelemetryNotifier extends AsyncNotifier<AdminKpi> {
  Timer? _poll;
  bool _polling = false;

  @override
  Future<AdminKpi> build() async {
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });
    _poll ??=
        Timer.periodic(_adminStatsPollInterval, (_) => _silentDiffPull());
    return ref.read(dioClientProvider).getDashboardTelemetry();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getDashboardTelemetry(),
    );
  }

  /// Background diff-poll — writes state only when the numbers change so
  /// the cards don't replay their scale-in animation every tick.
  Future<void> _silentDiffPull() async {
    if (_polling) return;
    _polling = true;
    try {
      final fresh = await ref.read(dioClientProvider).getDashboardTelemetry();
      final current = state.valueOrNull;
      if (current == null || current != fresh) {
        state = AsyncData(fresh);
      }
    } catch (e) {
      assert(() {
        debugPrint('[admin] telemetry poll failed: $e');
        return true;
      }());
    } finally {
      _polling = false;
    }
  }
}

// ─── Activity Feed ───────────────────────────────────────────────────────────

final activityFeedProvider = FutureProvider<List<ActivityEvent>>((ref) async {
  final dio = ref.watch(dioClientProvider);
  return dio.getActivityFeed();
});

// ─── Request Filter ──────────────────────────────────────────────────────────

final requestFilterProvider = StateProvider<RequestFilter>(
  (ref) => const RequestFilter(),
);

// ─── All Admin Requests ──────────────────────────────────────────────────────

/// Background heartbeat interval. 10 s matches the doctor dashboard's
/// cadence — fast enough that an idle admin sees patient submissions
/// within roughly one cycle, slow enough to keep the backend load to
/// about 6 polls/min per signed-in admin tab.
const _adminQueuePollInterval = Duration(seconds: 10);

/// `AsyncNotifierProvider` — `build()` is the single load path, so
/// `ref.invalidate(adminRequestsProvider)` cleanly re-runs it and every
/// consumer (`filteredRequestsProvider`, `requestCountsProvider`,
/// `distinctAreasProvider`, Overview, Review Queue) reacts.
///
/// Non-`autoDispose`: the polling timer + cached snapshot survive tab
/// switches so the admin doesn't see a fresh loading shimmer every time
/// they bounce between Live Monitor and Review Queue.
final adminRequestsProvider =
    AsyncNotifierProvider<AdminRequestsNotifier, List<AdminCareRequest>>(
  AdminRequestsNotifier.new,
);

class AdminRequestsNotifier extends AsyncNotifier<List<AdminCareRequest>> {
  Timer? _poll;
  bool _polling = false;

  @override
  Future<List<AdminCareRequest>> build() async {
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });
    // Diff-poll heartbeat. Starts after `build()` resolves so the very
    // first paint shows the shimmer once and never again unless a
    // consumer explicitly calls `fetchRequests()` (pull-to-refresh
    // or retry).
    _poll ??= Timer.periodic(
      _adminQueuePollInterval,
      (_) => _silentDiffPull(),
    );
    return ref.read(dioClientProvider).getAdminCareRequests();
  }

  /// Patient-visible refresh — flips to loading so the table shows a
  /// shimmer while the network call is in flight. Wired to the pull-to-
  /// refresh path and the error-state retry button.
  Future<void> fetchRequests() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getAdminCareRequests(),
    );
  }

  /// Background heartbeat — pulls a fresh `GET /admin/requests`, parses,
  /// and **only writes state if the new list materially differs from
  /// the current one** (see [_listsEqual]). Identical payloads produce
  /// zero rebuilds, so the admin's scroll position, selection, and any
  /// in-flight sheet stay intact across polls.
  ///
  /// Failures are intentionally swallowed: the admin already has the
  /// last-good snapshot and the next tick retries. Surfacing every poll
  /// blip would explode the UI with transient error banners.
  Future<void> _silentDiffPull() async {
    if (_polling) return; // overlap guard if the backend is slow
    _polling = true;
    try {
      final fresh =
          await ref.read(dioClientProvider).getAdminCareRequests();
      debugPrint(
          '📡 [DEBUG-ADMIN]: Fetching latest collections from MongoDB. Found ${fresh.length} items.');
      final current = state.valueOrNull;
      if (current == null || !_listsEqual(current, fresh)) {
        state = AsyncData(fresh);
      }
      // else: identical payload → zero rebuilds
    } catch (e, _) {
      // Keep the last-good snapshot, but surface the failure during
      // backend bring-up — a bare `catch (_) {}` is exactly what hid the
      // earlier patient→admin disconnect.
      assert(() {
        debugPrint('[admin] poll failed: $e');
        return true;
      }());
    } finally {
      _polling = false;
    }
  }

  /// Narrow equality on id + the fields that actually drive UI. Skips
  /// `createdAt` / `updatedAt` because Mongo bumps `updated_at` on
  /// every backend touch (e.g. an admin viewing the row server-side)
  /// and we don't want that to force a full table rebuild every 12 s.
  bool _listsEqual(List<AdminCareRequest> a, List<AdminCareRequest> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.status != y.status ||
          x.urgencyLevel != y.urgencyLevel ||
          x.assignedDoctorId != y.assignedDoctorId ||
          x.assignedHelperId != y.assignedHelperId ||
          x.adjustedPrice != y.adjustedPrice) {
        return false;
      }
    }
    return true;
  }

  /// Optimistic bulk status flip. Writes locally first so the admin
  /// sees the change instantly, then fires the backend mutation, then
  /// triggers a silent diff-pull to reconcile any server-derived fields
  /// (e.g. `adjusted_price`, `updated_at`). Rolls back on failure so
  /// the queue never lies to the admin.
  Future<void> bulkUpdateStatus(Set<String> ids, String newStatus) async {
    final previous = state.valueOrNull;
    if (previous == null) return;

    state = AsyncData(
      previous.map((r) {
        if (ids.contains(r.id)) return r.copyWith(status: newStatus);
        return r;
      }).toList(growable: false),
    );

    try {
      await ref
          .read(dioClientProvider)
          .bulkUpdateRequestStatus(ids.toList(), newStatus);
      // Reconcile asynchronously — don't await; the optimistic state
      // is already correct for everything UI-visible.
      unawaited(_silentDiffPull());
    } catch (_) {
      // Roll back to the pre-mutation snapshot so the table doesn't
      // show a flip that never persisted server-side, then rethrow so
      // the caller surfaces a SnackBar. Flipping this shared provider
      // to AsyncError would unmount the whole requests table over one
      // failed action.
      state = AsyncData(previous);
      rethrow;
    }
  }

  /// Optimistic administrative cancellation. Same pattern as
  /// [bulkUpdateStatus] but routes through the dedicated cancel endpoint,
  /// which also releases the assigned provider/team and notifies everyone.
  Future<void> cancelBooking(String id, {String? reason}) async {
    final previous = state.valueOrNull;
    if (previous == null) return;

    state = AsyncData(
      previous
          .map((r) => r.id == id ? r.copyWith(status: 'cancelled') : r)
          .toList(growable: false),
    );

    try {
      await ref.read(dioClientProvider).adminCancelBooking(id, reason: reason);
      unawaited(_silentDiffPull());
    } catch (_) {
      // Same rollback-and-rethrow contract as [bulkUpdateStatus].
      state = AsyncData(previous);
      rethrow;
    }
  }

  void updateRequest(AdminCareRequest updated) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.map((r) => r.id == updated.id ? updated : r).toList(),
    );
  }
}

// ─── Filtered Requests ───────────────────────────────────────────────────────

final filteredRequestsProvider = Provider<List<AdminCareRequest>>((ref) {
  final requestsAsync = ref.watch(adminRequestsProvider);
  final filter = ref.watch(requestFilterProvider);

  return requestsAsync.maybeWhen(
    data: (requests) {
      var filtered = List<AdminCareRequest>.from(requests);

      // Status filter
      if (filter.statusFilter != null) {
        filtered =
            filtered.where((r) => r.status == filter.statusFilter).toList();
      }

      // Service type filter
      if (filter.serviceTypeFilter != null) {
        filtered = filtered
            .where((r) => r.serviceType == filter.serviceTypeFilter)
            .toList();
      }

      // Area filter
      if (filter.areaFilter != null) {
        filtered =
            filtered.where((r) => r.area == filter.areaFilter).toList();
      }

      // Urgency filter (Overview hot-toggle + Review Queue "Urgent" chip)
      if (filter.urgencyOnly) {
        filtered = filtered.where((r) => r.isUrgent).toList();
      }

      // Multi-select urgency filter (More Filters sheet). Empty = no narrow.
      if (filter.urgencyLevels.isNotEmpty) {
        filtered = filtered
            .where((r) => filter.urgencyLevels.contains(r.urgencyLevel))
            .toList();
      }

      // Search query
      if (filter.searchQuery.isNotEmpty) {
        final q = filter.searchQuery.toLowerCase();
        filtered = filtered.where((r) {
          return r.id.toLowerCase().contains(q) ||
              r.patientName.toLowerCase().contains(q) ||
              r.location.toLowerCase().contains(q) ||
              r.area.toLowerCase().contains(q) ||
              r.serviceName.toLowerCase().contains(q);
        }).toList();
      }

      return filtered;
    },
    orElse: () => [],
  );
});

// ─── Filter Counts ───────────────────────────────────────────────────────────

final requestCountsProvider = Provider<Map<String, int>>((ref) {
  final requestsAsync = ref.watch(adminRequestsProvider);

  return requestsAsync.maybeWhen(
    data: (requests) {
      return {
        'all': requests.length,
        'pending': requests.where((r) => r.status == 'pending').length,
        'urgent': requests.where((r) => r.isUrgent).length,
        'approved': requests.where((r) => r.status == 'approved').length,
        'rejected': requests.where((r) => r.status == 'rejected').length,
      };
    },
    orElse: () => {
      'all': 0,
      'pending': 0,
      'urgent': 0,
      'approved': 0,
      'rejected': 0,
    },
  );
});

// ─── Selected Request (for triage / assignment) ──────────────────────────────

final selectedRequestProvider = StateProvider<AdminCareRequest?>((ref) => null);

// ─── Bulk Selection ──────────────────────────────────────────────────────────

final selectedRequestIdsProvider = StateProvider<Set<String>>((ref) => {});

// ─── Available Doctors ───────────────────────────────────────────────────────

final availableDoctorsProvider =
    FutureProvider.family<List<AvailableDoctor>, String>(
        (ref, requestId) async {
  final dio = ref.watch(dioClientProvider);
  return dio.getAvailableDoctors(requestId);
});

// ─── Available Nurses ────────────────────────────────────────────────────────

final availableNursesProvider =
    FutureProvider.family<List<AvailableNurse>, String>(
        (ref, requestId) async {
  final dio = ref.watch(dioClientProvider);
  return dio.getAvailableNurses(requestId);
});

// ─── Team Pool (combined doctors + nurses payload) ───────────────────────────

/// Single roundtrip for the Assign Team dual-list screen. The
/// underlying `availableDoctorsProvider` / `availableNursesProvider`
/// stay for any feature that only needs one role.
final teamPoolProvider =
    FutureProvider.family<TeamPool, String>((ref, requestId) async {
  final dio = ref.watch(dioClientProvider);
  return dio.getTeamPool(requestId);
});

// ─── Available Helpers ───────────────────────────────────────────────────────

final availableHelpersProvider =
    FutureProvider.family<List<AvailableHelper>, String>(
        (ref, requestId) async {
  final dio = ref.watch(dioClientProvider);
  return dio.getAvailableHelpers(requestId);
});

// ─── Doctor / Nurse / Helper Selection ───────────────────────────────────────

final assignedDoctorIdProvider = StateProvider<String?>((ref) => null);
final assignedNurseIdProvider = StateProvider<String?>((ref) => null);
final assignedHelperIdProvider = StateProvider<String?>((ref) => null);

// ─── Assign Team Flow ────────────────────────────────────────────────────────

final assignTeamStateProvider =
    StateNotifierProvider<AssignTeamNotifier, AssignTeamState>((ref) {
  final dio = ref.watch(dioClientProvider);
  return AssignTeamNotifier(dio);
});

class AssignTeamNotifier extends StateNotifier<AssignTeamState> {
  final DioClient _dio;

  AssignTeamNotifier(this._dio) : super(const AssignTeamState());

  Future<bool> assignTeam({
    required String requestId,
    String? doctorId,
    String? doctorName,
    String? nurseId,
    String? nurseName,
    String? helperId,
    String? helperName,
    double? finalPrice,
  }) async {
    try {
      // Stage 1 — Validate. At least one of doctor / nurse must be
      // selected for the team to dispatch; the backend now accepts
      // either or both, so an admin can send a nurse-only visit.
      state = const AssignTeamState(stage: AssignTeamStage.validating);
      final docOk = (doctorId ?? '').trim().isNotEmpty;
      final nurseOk = (nurseId ?? '').trim().isNotEmpty;
      if (!docOk && !nurseOk) {
        throw ArgumentError(
          'Select at least one doctor or nurse to dispatch.',
        );
      }
      await Future.delayed(const Duration(milliseconds: 600));

      // Stage 2 — Lock
      state = const AssignTeamState(stage: AssignTeamStage.locking);
      await Future.delayed(const Duration(milliseconds: 500));

      // Stage 3 — Assign (snake_case wire fields handled by DioClient).
      state = const AssignTeamState(stage: AssignTeamStage.assigning);
      await _dio.assignTeam(
        requestId,
        docOk ? doctorId : null,
        doctorName: doctorName,
        nurseId: nurseOk ? nurseId : null,
        nurseName: nurseName,
        helperId: helperId,
        helperName: helperName,
        finalPrice: finalPrice,
      );

      // Stage 4 — Notify
      state = const AssignTeamState(stage: AssignTeamStage.notifying);
      await Future.delayed(const Duration(milliseconds: 400));

      // Done
      state = const AssignTeamState(stage: AssignTeamStage.done);
      return true;
    } catch (e) {
      state = AssignTeamState(
        stage: AssignTeamStage.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  void reset() {
    state = const AssignTeamState();
  }
}

// ─── Doctor Search Query ─────────────────────────────────────────────────────

final doctorSearchQueryProvider = StateProvider<String>((ref) => '');
final helperSearchQueryProvider = StateProvider<String>((ref) => '');

// ─── Live Services (Live Monitor tab) ────────────────────────────────────────

/// Snapshot of services currently in flight (onTheWay / arrived / inService).
/// The Live Monitor tab invalidates this on a 30s timer; consumers also call
/// `ref.invalidate(liveServicesProvider)` for manual refresh.
final liveServicesProvider =
    FutureProvider.autoDispose<List<LiveServiceUpdate>>((ref) async {
  final dio = ref.watch(dioClientProvider);
  return dio.getLiveServices();
});

// ─── Chart data ──────────────────────────────────────────────────────────────

/// 7-day approved/declined rollup for the Overview BarChart. Refreshed
/// on the same 15 s cadence as [adminKpiProvider] — the chart and the
/// KPI cards animate in step, so a service that just completed flips
/// the "Daily revenue" tile AND the rightmost bar at once.
const _adminChartPollInterval = Duration(seconds: 15);

final adminChartDataProvider =
    AsyncNotifierProvider<AdminChartDataNotifier, AdminChartData>(
  AdminChartDataNotifier.new,
);

class AdminChartDataNotifier extends AsyncNotifier<AdminChartData> {
  Timer? _poll;
  bool _polling = false;

  @override
  Future<AdminChartData> build() async {
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });
    _poll ??=
        Timer.periodic(_adminChartPollInterval, (_) => _silentDiffPull());
    return ref.read(dioClientProvider).getAdminChartData();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getAdminChartData(),
    );
  }

  Future<void> _silentDiffPull() async {
    if (_polling) return;
    _polling = true;
    try {
      final fresh = await ref.read(dioClientProvider).getAdminChartData();
      final current = state.valueOrNull;
      if (current == null || current != fresh) state = AsyncData(fresh);
    } catch (e) {
      assert(() {
        debugPrint('[admin] chart poll failed: $e');
        return true;
      }());
    } finally {
      _polling = false;
    }
  }
}

// ─── Sidebar list providers (Patients / Providers / Billing) ────────────────

/// `GET /admin/patients` — newest-first. Autodispose so the table
/// re-fetches on every visit (admin opens these screens occasionally;
/// no need to keep them warm).
final adminPatientsProvider =
    FutureProvider.autoDispose<List<User>>((ref) async {
  return ref.read(dioClientProvider).getAdminPatients();
});

/// `GET /admin/providers` — newest-first.
final adminProvidersListProvider =
    FutureProvider.autoDispose<List<DoctorProfile>>((ref) async {
  return ref.read(dioClientProvider).getAdminProviders();
});

/// `GET /api/admin/patients/:id` — a single patient's clinical drill-down
/// (account + medical vault + care-request history) for the Patients
/// directory detail panel. Keyed by patient account id.
final adminPatientDetailProvider = FutureProvider.autoDispose
    .family<AdminPatientDetail, String>((ref, patientId) async {
  return ref.read(dioClientProvider).getAdminPatientDetail(patientId);
});

/// Active date-range filter for the Billing ledger. `null` = all time.
/// The Billing tab's "Date to Date" picker writes here, and
/// [adminBillingProvider] re-fetches the scoped window server-side.
final billingRangeProvider = StateProvider<DateTimeRange?>((_) => null);

/// `GET /admin/billing` — completed care_requests with `final_price`,
/// scoped to [billingRangeProvider] when a range is set.
final adminBillingProvider =
    FutureProvider.autoDispose<List<AdminCareRequest>>((ref) async {
  final range = ref.watch(billingRangeProvider);
  return ref.read(dioClientProvider).getAdminBilling(
        startDate: range?.start,
        endDate: range?.end,
      );
});

// ---------------------------------------------------------------------------
// 2-Step OTP gate for admin edits to a provider profile
// ---------------------------------------------------------------------------

/// Immutable status object backing the verification dialog. Threaded
/// through a dedicated `StateNotifier` so the dialog rebuilds on its
/// own without leaking dispatch state into the table widget.
@immutable
class ProviderEditState {
  /// True while either the OTP request OR the verified-update PATCH
  /// is in flight. Drives the loading barrier on the providers table
  /// AND the spinner on the dialog's primary button.
  final bool isLoading;

  /// Server response from stage 1 (`request-update-otp`). Non-null
  /// indicates the verification dialog should be shown. The
  /// [ProviderUpdateOtpDispatch.devOtp] field is only populated in
  /// the non-strict dev build and is shown inline so QA can verify
  /// without watching the server console.
  final ProviderUpdateOtpDispatch? dispatch;

  /// Most recent error message — surfaced through a SnackBar by the
  /// widget layer. Cleared on every retry.
  final String? errorMessage;

  const ProviderEditState({
    this.isLoading = false,
    this.dispatch,
    this.errorMessage,
  });

  ProviderEditState copyWith({
    bool? isLoading,
    ProviderUpdateOtpDispatch? dispatch,
    bool clearDispatch = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProviderEditState(
      isLoading: isLoading ?? this.isLoading,
      dispatch: clearDispatch ? null : (dispatch ?? this.dispatch),
      errorMessage:
          clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Drives the 2-step OTP edit flow. `requestOtp` fires the dispatch
/// endpoint; `commitUpdate` consumes the typed code + field map and
/// re-fetches the providers list on success.
class ProviderEditController extends StateNotifier<ProviderEditState> {
  ProviderEditController(this._ref) : super(const ProviderEditState());

  final Ref _ref;

  /// Stage 1 — ask the server to issue an OTP. On success the
  /// dispatch payload lands in state so the widget layer can show
  /// the verification dialog. On failure the error message is
  /// pushed into state for the SnackBar to render.
  Future<bool> requestOtp(String providerId) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearDispatch: true,
    );
    try {
      final dispatch =
          await _ref.read(dioClientProvider).requestProviderUpdateOtp(providerId);
      state = state.copyWith(isLoading: false, dispatch: dispatch);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Stage 2 — submit the OTP + the edited fields. Refreshes the
  /// providers list on success so the admin sees the new values
  /// land. Returns `true` only on a clean 200; verification failures
  /// surface as `false` + an error in state.
  Future<bool> commitUpdate({
    required String providerId,
    required String otp,
    required Map<String, dynamic> updates,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _ref.read(dioClientProvider).commitProviderUpdate(
            providerId: providerId,
            otp: otp,
            updates: updates,
          );
      state = const ProviderEditState();
      _ref.invalidate(adminProvidersListProvider);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Dismisses the dialog without sending anything — wipes the
  /// dispatch payload so the widget hides the verification UI.
  /// The server-side OTP latch keeps ticking until its 5-minute
  /// expiry (or is overwritten by a fresh request).
  void cancel() {
    state = const ProviderEditState();
  }
}

/// One controller per session — kept warm so the admin can re-open
/// the dialog without re-fetching its surface state.
final providerEditControllerProvider =
    StateNotifierProvider<ProviderEditController, ProviderEditState>(
  (ref) => ProviderEditController(ref),
);

/// Distinct areas across the current request list — populates the Area
/// dropdown in the More Filters sheet. Always returns a sorted, unique list.
final distinctAreasProvider = Provider<List<String>>((ref) {
  final requestsAsync = ref.watch(adminRequestsProvider);
  return requestsAsync.maybeWhen(
    data: (requests) {
      final areas = <String>{};
      for (final r in requests) {
        if (r.area.trim().isNotEmpty) areas.add(r.area);
      }
      final list = areas.toList()..sort();
      return list;
    },
    orElse: () => const <String>[],
  );
});

// ─── Provider cash clearance (Finance & Ledger) ─────────────────────────────

/// The Cash Clearance terminal's data source: every doctor/nurse holding
/// un-remitted physical cash plus the field-wide rollups. Same 15 s diff-poll
/// heartbeat as the other admin notifiers so a fresh cash collection surfaces
/// without a manual refresh. `CashInHandSummary extends Equatable`, so an
/// identical poll payload produces zero rebuilds.
final cashInHandProvider =
    AsyncNotifierProvider<CashInHandNotifier, CashInHandSummary>(
  CashInHandNotifier.new,
);

class CashInHandNotifier extends AsyncNotifier<CashInHandSummary> {
  Timer? _poll;
  bool _polling = false;

  @override
  Future<CashInHandSummary> build() async {
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });
    _poll ??=
        Timer.periodic(_adminStatsPollInterval, (_) => _silentDiffPull());
    return ref.read(dioClientProvider).getCashInHand();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getCashInHand(),
    );
  }

  Future<void> _silentDiffPull() async {
    if (_polling) return;
    _polling = true;
    try {
      final fresh = await ref.read(dioClientProvider).getCashInHand();
      final current = state.valueOrNull;
      if (current == null || current != fresh) {
        state = AsyncData(fresh);
      }
    } catch (e) {
      assert(() {
        debugPrint('[admin] cash-in-hand poll failed: $e');
        return true;
      }());
    } finally {
      _polling = false;
    }
  }

  /// Settle (zero) a provider's cash ledger. Optimistically drops the row and
  /// re-derives the rollups so the terminal reacts instantly, then confirms
  /// against the server. On failure the state is reloaded so the row returns.
  /// Returns the receipt for the handover confirmation dialog; rethrows the
  /// server error (e.g. a 409 stale-ledger race) for the modal to surface.
  Future<CashSettlementResult> settleProviderCash({
    required String providerId,
    required double amountCollected,
    String? adminNotes,
  }) async {
    final previous = state.valueOrNull;
    // Optimistic removal.
    if (previous != null) {
      final remaining = previous.providers
          .where((p) => p.accountId != providerId)
          .toList();
      state = AsyncData(CashInHandSummary(
        providers: remaining,
        totalCashInField:
            remaining.fold<double>(0, (s, p) => s + p.cashInHand),
        collectedToday: previous.collectedToday + amountCollected,
        outstandingProvidersCount: remaining.length,
      ));
    }
    try {
      final result = await ref.read(dioClientProvider).settleProviderCash(
            providerId: providerId,
            amountCollected: amountCollected,
            adminNotes: adminNotes,
          );
      // Reconcile against the server (picks up any collection that landed
      // mid-settlement on OTHER providers).
      unawaited(_silentDiffPull());
      return result;
    } catch (e) {
      // Restore the pre-optimistic view so the row comes back.
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}

// ─── Provider payout queue (Finance & Ledger) ───────────────────────────────

/// The withdrawal-approval queue: every PENDING payout request plus the
/// pending count/total the console's summary cards and the sidebar badge
/// render. Same 15 s diff-poll heartbeat as the other admin notifiers, so a
/// request filed from a provider's phone surfaces without a manual refresh.
/// `PayoutQueue extends Equatable`, so an identical poll payload produces
/// zero rebuilds.
final payoutRequestsProvider =
    AsyncNotifierProvider<PayoutRequestsNotifier, PayoutQueue>(
  PayoutRequestsNotifier.new,
);

class PayoutRequestsNotifier extends AsyncNotifier<PayoutQueue> {
  Timer? _poll;
  bool _polling = false;

  @override
  Future<PayoutQueue> build() async {
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });
    _poll ??=
        Timer.periodic(_adminStatsPollInterval, (_) => _silentDiffPull());
    return ref.read(dioClientProvider).getPayoutRequests();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getPayoutRequests(),
    );
  }

  Future<void> _silentDiffPull() async {
    if (_polling) return;
    _polling = true;
    try {
      final fresh = await ref.read(dioClientProvider).getPayoutRequests();
      final current = state.valueOrNull;
      if (current == null || current != fresh) {
        state = AsyncData(fresh);
      }
    } catch (e) {
      assert(() {
        debugPrint('[admin] payout-queue poll failed: $e');
        return true;
      }());
    } finally {
      _polling = false;
    }
  }

  /// Approve a payout, marking it paid against a bank/MFS reference.
  /// Optimistically drops the row so the table reacts instantly, then
  /// reconciles. Rethrows the server error (e.g. a 409 when someone else
  /// already actioned it) for the modal to surface.
  Future<void> approve({
    required String payoutId,
    required String referenceId,
  }) =>
      _resolve(
        payoutId,
        () => ref.read(dioClientProvider).approvePayout(
              payoutId: payoutId,
              referenceId: referenceId,
            ),
      );

  /// Reject a payout, returning the held funds to the provider's balance.
  Future<void> reject({
    required String payoutId,
    required String reason,
  }) =>
      _resolve(
        payoutId,
        () => ref.read(dioClientProvider).rejectPayout(
              payoutId: payoutId,
              reason: reason,
            ),
      );

  /// Shared optimistic-remove-then-confirm path for both terminal actions —
  /// they differ only in which endpoint they call.
  Future<void> _resolve(
    String payoutId,
    Future<PayoutRequestModel> Function() action,
  ) async {
    final previous = state.valueOrNull;
    if (previous != null) {
      final remaining =
          previous.items.where((p) => p.id != payoutId).toList();
      final removed = previous.items.where((p) => p.id == payoutId);
      final removedAmount =
          removed.fold<num>(0, (s, p) => s + (p.isPending ? p.amount : 0));
      state = AsyncData(PayoutQueue(
        items: remaining,
        pendingCount: removed.any((p) => p.isPending)
            ? (previous.pendingCount - 1).clamp(0, 1 << 30)
            : previous.pendingCount,
        pendingTotal: previous.pendingTotal - removedAmount,
      ));
    }
    try {
      await action();
      unawaited(_silentDiffPull());
    } catch (e) {
      // Restore the pre-optimistic view so the row comes back.
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}
