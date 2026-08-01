import 'package:equatable/equatable.dart';

/// One row in the Doctor Operations Hub's "Patient Records" tab. Maps to
/// a deduped entry returned by `GET /doctor/:doctorId/patients` — each
/// patient the provider has treated, collapsed from their completed
/// `care_requests` with a visit count + last-seen timestamp.
class DoctorPatient extends Equatable {
  /// `accounts._id` of the patient — the key used to open their record
  /// detail (case logs + past prescriptions + medical vault).
  final String patientAccountId;
  final String name;
  final String phone;
  final String locationText;

  /// `care_type` of the most recent completed visit.
  final String lastCareType;

  /// Timestamp of the most recent completed visit. Null only when the
  /// backend couldn't resolve one (defensive — should always be set).
  final DateTime? lastVisitAt;

  /// Total completed visits this provider has delivered to the patient.
  final int visitCount;

  const DoctorPatient({
    required this.patientAccountId,
    required this.name,
    required this.phone,
    required this.locationText,
    required this.lastCareType,
    required this.lastVisitAt,
    required this.visitCount,
  });

  @override
  List<Object?> get props => [
        patientAccountId,
        name,
        phone,
        locationText,
        lastCareType,
        lastVisitAt,
        visitCount,
      ];

  factory DoctorPatient.fromJson(Map<String, dynamic> json) {
    return DoctorPatient(
      patientAccountId: (json['patient_account_id'] ?? '').toString(),
      name: (json['patient_name'] ?? '').toString(),
      phone: (json['patient_phone'] ?? '').toString(),
      locationText: (json['location_text'] ?? '').toString(),
      lastCareType: (json['last_care_type'] ?? '').toString(),
      lastVisitAt: DateTime.tryParse((json['last_visit_at'] ?? '').toString()),
      visitCount: (json['visit_count'] as num?)?.toInt() ?? 0,
    );
  }
}
