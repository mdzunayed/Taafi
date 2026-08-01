import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/patient_home_repository.dart';
import '../../../core/models/care_request_status.dart';
import '../../../core/models/doctor_patient.dart';
import '../../../core/models/patient_history_item.dart';
import '../../../core/models/patient_medical_vault.dart';
import '../../../core/models/prescription.dart';
import '../../admin/admin_providers.dart';
import '../../auth/auth_provider.dart';
import '../../doctor/doctor_providers.dart';

/// State + actions controller for the Doctor Operations Hub. Deliberately
/// thin: the cross-tab data already lives in `doctorDashboardProvider` /
/// `doctorStatsProvider`; this file adds only the surfaces unique to the
/// new hub (Patient Records + medical vault) and a single mutation entry
/// point that keeps the visit lifecycle's cross-role fan-out in one place.

// ─── Patient Records tab ────────────────────────────────────────────────────

/// Search query for the Patient Records list. Bound to the tab's search
/// field; `doctorPatientsProvider` re-fetches whenever it changes.
final doctorPatientsSearchProvider = StateProvider.autoDispose<String>((_) => '');

/// Patients this provider has treated, filtered by the live search query.
/// Reads the signed-in doctor's id from [currentUserProvider] so it works
/// for any session without the caller threading the id through.
final doctorPatientsProvider =
    FutureProvider.autoDispose<List<DoctorPatient>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  final search = ref.watch(doctorPatientsSearchProvider);
  return ref.read(dioClientProvider).getDoctorPatients(user.id, search: search);
});

// ─── Patient record detail / Active Care Console reads ───────────────────────

/// A patient's medical vault (allergies, chronic conditions, blood type,
/// emergency notes). Keyed by the patient's `accounts._id`.
final patientVaultProvider = FutureProvider.autoDispose
    .family<PatientMedicalVault, String>((ref, accountId) async {
  if (accountId.isEmpty) return PatientMedicalVault.empty;
  return ref.read(dioClientProvider).getPatientMedicalVault(accountId);
});

/// A patient's completed/cancelled case log. Reuses the existing
/// patient-centric history endpoint (filters by `account_id`), which a
/// treating doctor is allowed to read.
final patientCaseLogProvider = FutureProvider.autoDispose
    .family<List<PatientHistoryItem>, String>((ref, accountId) async {
  if (accountId.isEmpty) return const [];
  return ref.read(dioClientProvider).getPatientHistory(accountId);
});

/// Every prescription ever issued to a patient, newest-first.
final patientPrescriptionsProvider = FutureProvider.autoDispose
    .family<List<Prescription>, String>((ref, accountId) async {
  if (accountId.isEmpty) return const [];
  return ref.read(dioClientProvider).getPrescriptionsForPatient(accountId);
});

// ─── Visit lifecycle actions ────────────────────────────────────────────────

/// Single mutation surface for the visit state machine
/// (assigned → enroute → arrived → in_service → completed). Centralises
/// the cross-role fan-out so the Assignments card and the Active Care
/// Console never drift in which caches they refresh.
final doctorWorkflowProvider =
    Provider<DoctorWorkflowController>((ref) => DoctorWorkflowController(ref));

class DoctorWorkflowController {
  DoctorWorkflowController(this._ref);
  final Ref _ref;

  /// Push the visit to [nextStatus] and fan the change out to every role
  /// that renders it (doctor dashboard, admin monitor, patient feed).
  /// Returns the updated appointment document — the console reads the
  /// resulting status (a `completed` request may park in the payment-due
  /// state) to decide whether to offer cash collection.
  Future<Map<String, dynamic>> advance(
      String requestId, String nextStatus) async {
    final updated = await _ref
        .read(dioClientProvider)
        .updateVisitStatus(requestId, nextStatus);
    _fanOut(nextStatus);
    return updated;
  }

  /// Convenience for the console's "Complete Visit" footer. The backend
  /// emits `appointment_status_change` on completion, which locks the
  /// live chat room — no separate socket teardown needed here.
  Future<Map<String, dynamic>> completeVisit(String requestId) =>
      advance(requestId, CareRequestStatus.completed);

  void _fanOut(String status) {
    _ref.invalidate(doctorDashboardProvider);
    _ref.invalidate(adminRequestsProvider);
    // Completion unlocks new earnings — refresh the Performance tiles now
    // instead of waiting for the 15 s stats poll.
    if (status == CareRequestStatus.completed) {
      _ref.invalidate(doctorStatsProvider);
    }
    // Patient's Under Review / tracking card flips to the new status.
    // Best-effort cross-role refresh, matching the legacy dashboard flow.
    // ignore: unused_result
    _ref.read(patientHomeFeedProvider.notifier).refresh();
  }
}
