import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/appointment.dart';
import '../../../features/chat/models/message_model.dart';
import '../../auth/auth_provider.dart';

/// AsyncNotifier backing the History sub-tab. Loads every past
/// appointment (completed + cancelled) for the signed-in patient via
/// `GET /api/appointments/patient/history`, sorted newest first.
///
/// Exposes `refresh()` so the tab's pull-to-refresh + the post-feedback
/// optimistic update can both re-pull the list from the same surface.
class PatientHistoryNotifier extends AutoDisposeAsyncNotifier<List<Appointment>> {
  @override
  Future<List<Appointment>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const [];
    return ref
        .read(dioClientProvider)
        .getPatientAppointmentHistory(accountId: user.id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(currentUserProvider);
      if (user == null) return const <Appointment>[];
      return ref
          .read(dioClientProvider)
          .getPatientAppointmentHistory(accountId: user.id);
    });
  }

  /// Optimistic local update used after a successful feedback submission
  /// — the patient sees the rated card immediately while the next
  /// background refresh confirms server state.
  void replace(Appointment fresh) {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = [
      for (final a in current)
        if (a.id == fresh.id) fresh else a,
    ];
    state = AsyncData(updated);
  }
}

final patientHistoryProvider = AsyncNotifierProvider.autoDispose<
    PatientHistoryNotifier, List<Appointment>>(PatientHistoryNotifier.new);

/// Pulls the archived chat transcript for a single past appointment.
/// Keyed by the appointment id so the History tab can pre-load (or
/// the archived chat screen can fetch on demand) without re-issuing
/// the same call. AutoDispose so the cache evicts once the user
/// leaves the screen — chat logs are large enough that retaining
/// them globally would bloat the in-memory footprint.
final archivedChatProvider = FutureProvider.autoDispose
    .family<List<MessageModel>, String>((ref, appointmentId) async {
  if (appointmentId.isEmpty) return const [];
  final raw = await ref
      .read(dioClientProvider)
      .getAppointmentMessages(appointmentId);
  final out = <MessageModel>[];
  for (final m in raw) {
    try {
      out.add(MessageModel.fromJson(m));
    } catch (_) {
      // Skip a malformed row, keep the rest of the transcript.
    }
  }
  return out;
});
