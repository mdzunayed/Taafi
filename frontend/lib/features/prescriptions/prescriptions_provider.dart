import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/prescription.dart';
import '../auth/auth_provider.dart';

/// `GET /api/prescriptions/my-active` — every active prescription for
/// the signed-in patient. Backs the medication timeline screen and
/// any future home-screen "today's doses" widget. autoDispose so the
/// list refreshes from the server every time the patient opens the
/// timeline.
class PatientPrescriptionsNotifier
    extends AutoDisposeAsyncNotifier<List<Prescription>> {
  @override
  Future<List<Prescription>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const [];
    return ref.read(dioClientProvider).getMyActivePrescriptions();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getMyActivePrescriptions(),
    );
  }

  /// Optimistic dose-toggle. Updates the local list first so the
  /// checkbox flips in the same frame, then writes through to the
  /// backend and reconciles against the canonical response. On
  /// failure we roll back so the UI doesn't lie.
  Future<bool> toggleDose({
    required String prescriptionId,
    required String itemId,
    required DoseSlot slot,
    required String dayKey,
    required bool taken,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      final refreshed = await ref.read(dioClientProvider).setDoseTaken(
            prescriptionId: prescriptionId,
            itemId: itemId,
            slot: slot,
            dayKey: dayKey,
            taken: taken,
          );
      state = AsyncData([
        for (final p in current)
          if (p.id == prescriptionId) refreshed else p,
      ]);
      return true;
    } catch (_) {
      // Keep the previous state on failure — caller surfaces a snack.
      return false;
    }
  }
}

final patientPrescriptionsProvider = AsyncNotifierProvider.autoDispose<
    PatientPrescriptionsNotifier,
    List<Prescription>>(PatientPrescriptionsNotifier.new);

/// Backs the "Medications" tab's prescription hub: the patient's FULL
/// script list (`GET /api/prescriptions/by-patient/:accountId`,
/// newest-first, each row enriched with the issuing doctor's public
/// profile block) — unlike the active-only timeline provider above,
/// completed courses stay visible with a Completed badge. Carries the
/// same optimistic dose-toggle write path so today's adherence chips
/// on active cards stay trackable.
class MedicationsHubNotifier
    extends AutoDisposeAsyncNotifier<List<Prescription>> {
  @override
  Future<List<Prescription>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const [];
    return ref.read(dioClientProvider).getPrescriptionsForPatient(user.id);
  }

  Future<void> refresh() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      state = const AsyncData(<Prescription>[]);
      return;
    }
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getPrescriptionsForPatient(user.id),
    );
  }

  /// Same write-through dose toggle as the timeline notifier, but the
  /// reconciled row keeps this list's `doctor` block: the PATCH
  /// response isn't doctor-enriched, so we graft the block we already
  /// hold back onto the refreshed prescription.
  Future<bool> toggleDose({
    required String prescriptionId,
    required String itemId,
    required DoseSlot slot,
    required String dayKey,
    required bool taken,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      final refreshed = await ref.read(dioClientProvider).setDoseTaken(
            prescriptionId: prescriptionId,
            itemId: itemId,
            slot: slot,
            dayKey: dayKey,
            taken: taken,
          );
      state = AsyncData([
        for (final p in current)
          if (p.id == prescriptionId)
            Prescription(
              id: refreshed.id,
              appointmentId: refreshed.appointmentId,
              patientAccountId: refreshed.patientAccountId,
              doctorAccountId: refreshed.doctorAccountId,
              doctorName: refreshed.doctorName,
              diagnosis: refreshed.diagnosis,
              issuedAt: refreshed.issuedAt,
              items: refreshed.items,
              doseLog: refreshed.doseLog,
              doctor: refreshed.doctor ?? p.doctor,
              doctorBmdc: refreshed.doctorBmdc.isNotEmpty
                  ? refreshed.doctorBmdc
                  : p.doctorBmdc,
              doctorSpecialization: refreshed.doctorSpecialization.isNotEmpty
                  ? refreshed.doctorSpecialization
                  : p.doctorSpecialization,
              doctorVerified: refreshed.doctorVerified || p.doctorVerified,
              symptoms:
                  refreshed.symptoms.isNotEmpty ? refreshed.symptoms : p.symptoms,
              releaseStatus: refreshed.releaseStatus,
              locked: refreshed.locked,
              unlockFeeAmount: refreshed.unlockFeeAmount,
              itemCount: refreshed.itemCount,
            )
          else
            p,
      ]);
      return true;
    } catch (_) {
      // Keep the previous state on failure — caller surfaces a snack.
      return false;
    }
  }
}

final medicationsHubProvider = AsyncNotifierProvider.autoDispose<
    MedicationsHubNotifier, List<Prescription>>(MedicationsHubNotifier.new);

/// `GET /api/prescriptions/by-patient/:accountId` — the patient's full
/// historical prescription vault (every script ever issued, newest-first),
/// distinct from the active-only timeline above.
final patientPrescriptionVaultProvider =
    FutureProvider.autoDispose<List<Prescription>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.read(dioClientProvider).getPrescriptionsForPatient(user.id);
});

/// `GET /api/prescriptions/:id` — a single prescription enriched with the
/// doctor's verified credentials + symptoms, for the vault detail card.
final prescriptionDetailProvider =
    FutureProvider.autoDispose.family<Prescription, String>((ref, id) async {
  return ref.read(dioClientProvider).getPrescriptionById(id);
});

// NOTE: there is no per-prescription payment anymore. A locked script is
// paid for by settling the BOOKING's outstanding balance
// (`runBalancePayment` in booking_flow_pages.dart) — the backend flips
// the script to PAID as part of that settlement.
