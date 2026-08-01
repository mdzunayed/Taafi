import 'package:equatable/equatable.dart';

import '../utils/age.dart';

/// A saved family member / dependent the patient can book care for
/// (`GET /api/dependents`).
class Dependent extends Equatable {
  final String id;
  final String fullName;
  final String dateOfBirth;
  final String gender;
  final String relationshipTag;
  final String bloodGroup;
  final List<String> knownMedicalConditions;
  final List<String> allergies;
  final String criticalAllergiesMedicalHistory;

  const Dependent({
    required this.id,
    required this.fullName,
    this.dateOfBirth = '',
    this.gender = 'unspecified',
    this.relationshipTag = 'other',
    this.bloodGroup = 'unknown',
    this.knownMedicalConditions = const [],
    this.allergies = const [],
    this.criticalAllergiesMedicalHistory = '',
  });

  /// Capitalised relationship for display ('Parent', 'Father', 'Child', …).
  String get relationshipLabel {
    if (relationshipTag.isEmpty) return 'Other';
    return relationshipTag[0].toUpperCase() + relationshipTag.substring(1);
  }

  /// Whole years from [dateOfBirth], or null when unknown.
  int? get age => ageFromDob(dateOfBirth);

  static List<String> _stringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => (e ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  factory Dependent.fromJson(Map<String, dynamic> json) {
    return Dependent(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      fullName: (json['full_name'] ?? '').toString(),
      dateOfBirth: (json['date_of_birth'] ?? '').toString(),
      gender: (json['gender'] ?? 'unspecified').toString(),
      relationshipTag: (json['relationship_tag'] ?? 'other').toString(),
      bloodGroup: (json['blood_group'] ?? 'unknown').toString(),
      knownMedicalConditions: _stringList(json['known_medical_conditions']),
      allergies: _stringList(json['allergies']),
      criticalAllergiesMedicalHistory:
          (json['critical_allergies_medical_history'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        fullName,
        dateOfBirth,
        gender,
        relationshipTag,
        bloodGroup,
        knownMedicalConditions,
        allergies,
        criticalAllergiesMedicalHistory,
      ];
}
