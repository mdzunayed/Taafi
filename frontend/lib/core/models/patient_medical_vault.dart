import 'package:equatable/equatable.dart';

/// Patient clinical reference surfaced inside the Active Care Console.
/// Maps to the `accounts.medical_vault` sub-doc returned by
/// `GET /doctor/patients/:accountId/vault`. Every field has a safe empty
/// default so the console's grid can render "Not recorded" states without
/// null juggling.
class PatientMedicalVault extends Equatable {
  final List<String> allergies;
  final List<String> chronicConditions;

  /// One of O+/O-/A+/A-/B+/B-/AB+/AB-/Unknown. Defaults to 'Unknown'.
  final String bloodType;
  final String emergencyNotes;

  /// When the vault was last edited. Null when never populated.
  final DateTime? updatedAt;

  const PatientMedicalVault({
    this.allergies = const [],
    this.chronicConditions = const [],
    this.bloodType = 'Unknown',
    this.emergencyNotes = '',
    this.updatedAt,
  });

  static const PatientMedicalVault empty = PatientMedicalVault();

  /// True when nothing clinical has ever been recorded — drives the
  /// console's "no vault on file" empty state.
  bool get isEmpty =>
      allergies.isEmpty &&
      chronicConditions.isEmpty &&
      (bloodType.isEmpty || bloodType == 'Unknown') &&
      emergencyNotes.trim().isEmpty;

  @override
  List<Object?> get props => [
        allergies,
        chronicConditions,
        bloodType,
        emergencyNotes,
        updatedAt,
      ];

  factory PatientMedicalVault.fromJson(Map<String, dynamic> json) {
    List<String> strList(dynamic v) => v is List
        ? v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const [];
    return PatientMedicalVault(
      allergies: strList(json['allergies']),
      chronicConditions: strList(json['chronic_conditions']),
      bloodType: (json['blood_type'] ?? 'Unknown').toString(),
      emergencyNotes: (json['emergency_notes'] ?? '').toString(),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
    );
  }
}
