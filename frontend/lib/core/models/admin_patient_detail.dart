import 'admin_models.dart';
import 'patient_medical_vault.dart';
import 'snake_case_json.dart';
import 'user.dart';

/// Admin drill-down for a single patient — their account, clinical vault, and
/// full care-request history. Returned by `GET /api/admin/patients/:id`.
class AdminPatientDetail {
  final User patient;
  final PatientMedicalVault vault;
  final List<AdminCareRequest> careRequests;

  const AdminPatientDetail({
    required this.patient,
    required this.vault,
    required this.careRequests,
  });

  factory AdminPatientDetail.fromJson(Map<String, dynamic> json) {
    final rawPatient = (json['patient'] is Map)
        ? Map<String, dynamic>.from(json['patient'] as Map)
        : const <String, dynamic>{};
    final vaultRaw = (rawPatient['medical_vault'] is Map)
        ? Map<String, dynamic>.from(rawPatient['medical_vault'] as Map)
        : const <String, dynamic>{};

    final requests = <AdminCareRequest>[];
    final rawList = json['careRequests'];
    if (rawList is List) {
      for (final e in rawList) {
        if (e is Map) {
          try {
            requests.add(
              adminCareRequestFromMongo(Map<String, dynamic>.from(e)),
            );
          } catch (_) {
            // Skip an unparseable row rather than failing the whole drawer.
          }
        }
      }
    }

    return AdminPatientDetail(
      patient: User.fromJson(rawPatient),
      vault: PatientMedicalVault.fromJson(vaultRaw),
      careRequests: requests,
    );
  }
}
