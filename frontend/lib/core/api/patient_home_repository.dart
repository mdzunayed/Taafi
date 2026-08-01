import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../models/patient_active_request.dart';
import '../models/patient_home_feed.dart';
import '../models/patient_notification.dart';
import '../network/socket_manager.dart';
import 'dio_client.dart';

/// Cadence at which the patient pulls `GET /patient/home` so the Tracking
/// timeline advances without manual refresh after the doctor's PATCH
/// /doctor/visits/:id/status. Matches the doctor dashboard's 10 s
/// heartbeat — the two roles converge on a status change within roughly
/// a single poll window.
const _patientPollInterval = Duration(seconds: 10);

class PatientHomeRepository {
  final DioClient _dio;

  PatientHomeRepository(this._dio);

  Future<PatientHomeFeed> fetchFeed() => _dio.getPatientHomeFeed();

  Future<List<PatientNotification>> fetchNotifications() =>
      _dio.getPatientNotifications();

  Future<void> markRead(String id) => _dio.markPatientNotificationRead(id);

  Future<void> markAllRead() => _dio.markAllPatientNotificationsRead();

  Future<void> cancelRequest(String requestId, {String? reason}) =>
      _dio.cancelPatientRequest(requestId, reason: reason);
}

class PatientHomeFeedController extends AsyncNotifier<PatientHomeFeed> {
  late final PatientHomeRepository _repo =
      ref.read(patientHomeRepositoryProvider);
  Timer? _poll;
  bool _polling = false;

  @override
  Future<PatientHomeFeed> build() async {
    // Scope this controller to the signed-in account. Watching the user id
    // makes Riverpod re-run build() — replacing the previous account's cached
    // feed — whenever the session changes, so a logout → login of a different
    // user on the same device can never surface the prior user's Ongoing Care
    // card. Mirrors the per-user discipline of notificationProvider.
    final userId = ref.watch(currentUserProvider.select((u) => u?.id));

    // Tear down any prior build's heartbeat before this build starts one, so
    // an account switch (build re-run) never leaks a stale polling timer.
    _poll?.cancel();
    _poll = null;
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });

    // Signed out / mid-transition: never fetch or poll, and never show a
    // stale card — hand back the empty placeholder feed.
    if (userId == null || userId.isEmpty) {
      return PatientHomeFeed.empty();
    }

    // Live milestone pushes. When an admin advances the booking (or edits the
    // appointment time) the backend emits `booking:status_updated` to this
    // patient's room — pull immediately so the ONGOING CARE card's step bar
    // and time pill move at once instead of waiting out the 10 s poll.
    final socket = ref.watch(socketManagerProvider);
    final milestoneSub = socket?.onBookingStatusUpdated.listen((_) {
      _silentDiffPull();
    });
    ref.onDispose(() => milestoneSub?.cancel());

    // Heartbeat — pulls `GET /patient/home` every 10 s and only writes
    // state when the active request's status / id / provider has actually
    // changed. This is the fallback that keeps the timeline advancing when
    // the socket is down, and it also covers provider-side status flips.
    _poll = Timer.periodic(_patientPollInterval, (_) => _silentDiffPull());
    return _repo.fetchFeed();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchFeed);
  }

  /// Background diff-poll. Mirrors the doctor / admin notifier pattern —
  /// we keep the last-good snapshot on transient failures (so the
  /// timeline doesn't blank between polls when the network blips) but
  /// surface the error via `debugPrint` so backend bring-up bugs aren't
  /// silently swallowed.
  Future<void> _silentDiffPull() async {
    if (_polling) return;
    _polling = true;
    try {
      final fresh = await _repo.fetchFeed();
      final current = state.valueOrNull;
      if (current == null || !_feedEqual(current, fresh)) {
        state = AsyncData(fresh);
      }
    } catch (e) {
      assert(() {
        debugPrint('[patient] poll failed: $e');
        return true;
      }());
    } finally {
      _polling = false;
    }
  }

  /// Narrow equality. Compares the bits that drive the Tracking + Under
  /// Review UIs — the active request's id and status, the assigned
  /// provider name, and the unread notification badge — and ignores
  /// server-side jitter so identical-meaning payloads don't force a
  /// rebuild between polls.
  bool _feedEqual(PatientHomeFeed a, PatientHomeFeed b) {
    if (a.unreadNotificationCount != b.unreadNotificationCount) return false;
    final ar = a.activeRequest;
    final br = b.activeRequest;
    if (ar == null && br == null) return true;
    if (ar == null || br == null) return false;
    if (ar.id != br.id) return false;
    if (ar.status != br.status) return false;
    // The two-phase booking states (awaiting_deposit,
    // deposit_paid_admin_reviewing, amount_assigned_awaiting_final_payment)
    // all collapse into the coarse `pendingReview` enum, so also diff the
    // raw wire status + priced amount — otherwise "admin set the invoice"
    // wouldn't wake the Under Review tab between polls.
    if (ar.rawStatus != br.rawStatus) return false;
    if (ar.finalServiceFee != br.finalServiceFee) return false;
    if (ar.providerName != br.providerName) return false;
    // Milestone tracker fields. An admin can reschedule the appointment or
    // rename the provider WITHOUT moving the lifecycle status — none of the
    // checks above would notice, and the ONGOING CARE card's time pill would
    // sit on a stale time until the next status change.
    if (ar.milestone != br.milestone) return false;
    if (ar.milestoneLabel != br.milestoneLabel) return false;
    if (ar.scheduledTime != br.scheduledTime) return false;
    if (ar.assignedProviderName != br.assignedProviderName) return false;
    return true;
  }

  void decrementUnread() {
    final current = state.valueOrNull;
    if (current == null || current.unreadNotificationCount == 0) return;
    state = AsyncValue.data(
      current.copyWith(
        unreadNotificationCount: current.unreadNotificationCount - 1,
      ),
    );
  }

  void clearUnread() {
    final current = state.valueOrNull;
    if (current == null || current.unreadNotificationCount == 0) return;
    state = AsyncValue.data(current.copyWith(unreadNotificationCount: 0));
  }

  /// Cancels the active request optimistically. The active card disappears
  /// instantly; on backend failure we roll the feed back to its previous
  /// snapshot and rethrow so the UI can surface the error.
  Future<void> cancelActiveRequest({String? reason}) async {
    final current = state.valueOrNull;
    final active = current?.activeRequest;
    if (current == null || active == null) {
      throw StateError('No active request to cancel.');
    }

    final optimistic = current.copyWith(clearActiveRequest: true);
    state = AsyncValue.data(optimistic);

    try {
      await _repo.cancelRequest(active.id, reason: reason);
      // Also refresh notifications so the "Request cancelled" entry appears
      // without the patient having to pull-to-refresh the bell.
      // ignore: unused_result
      await ref.read(patientNotificationsProvider.notifier).refresh();
    } catch (e) {
      state = AsyncValue.data(current);
      rethrow;
    }
  }
}

class PatientNotificationsController
    extends AsyncNotifier<List<PatientNotification>> {
  late final PatientHomeRepository _repo =
      ref.read(patientHomeRepositoryProvider);

  @override
  Future<List<PatientNotification>> build() {
    // Same per-user scoping as the feed controller — the bell list/badge must
    // belong to the currently signed-in account, never a prior session's.
    final userId = ref.watch(currentUserProvider.select((u) => u?.id));
    if (userId == null || userId.isEmpty) {
      return Future.value(const <PatientNotification>[]);
    }
    return _repo.fetchNotifications();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchNotifications);
  }

  Future<void> markRead(String id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final idx = current.indexWhere((n) => n.id == id);
    if (idx == -1 || current[idx].read) return;

    final updated = [...current];
    updated[idx] = current[idx].copyWith(read: true);
    state = AsyncValue.data(updated);
    ref.read(patientHomeFeedProvider.notifier).decrementUnread();

    try {
      await _repo.markRead(id);
    } catch (_) {
      final rollback = [...updated];
      rollback[idx] = current[idx];
      state = AsyncValue.data(rollback);
      rethrow;
    }
  }

  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    if (current == null || current.every((n) => n.read)) return;

    final updated = current.map((n) => n.read ? n : n.copyWith(read: true)).toList();
    state = AsyncValue.data(updated);
    ref.read(patientHomeFeedProvider.notifier).clearUnread();

    try {
      await _repo.markAllRead();
    } catch (_) {
      state = AsyncValue.data(current);
      rethrow;
    }
  }
}

final patientHomeRepositoryProvider = Provider<PatientHomeRepository>((ref) {
  return PatientHomeRepository(ref.watch(dioClientProvider));
});

final patientHomeFeedProvider =
    AsyncNotifierProvider<PatientHomeFeedController, PatientHomeFeed>(
  PatientHomeFeedController.new,
);

final patientNotificationsProvider = AsyncNotifierProvider<
    PatientNotificationsController, List<PatientNotification>>(
  PatientNotificationsController.new,
);

final patientActiveRequestProvider = Provider<PatientActiveRequest?>((ref) {
  return ref.watch(patientHomeFeedProvider).valueOrNull?.activeRequest;
});

final patientUnreadCountProvider = Provider<int>((ref) {
  return ref.watch(patientHomeFeedProvider).valueOrNull?.unreadNotificationCount ?? 0;
});
