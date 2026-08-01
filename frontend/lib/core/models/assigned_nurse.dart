import 'package:equatable/equatable.dart';

import 'assigned_doctor.dart' show AssignedDoctorExperience;

/// Read-only view of the nurse that an admin has assigned to a
/// patient's care request. Mirrors [AssignedDoctor] exactly — the only
/// reason for the parallel class is that `nursing_license` replaces
/// the BMDC field and the `is_verified_nurse` flag drives the verified
/// badge separately from the doctor one.
///
/// Every field is nullable / defaulted so a missing record on the
/// backend can't crash the patient app — the UI degrades gracefully
/// (initials in place of the avatar, blank specialty, etc.).
class AssignedNurse extends Equatable {
  final String id;
  final String fullName;
  final String? profilePicture;
  final String specialty;

  /// Nursing qualifications / degrees line (Provider `degrees`), e.g.
  /// "B.Sc in Nursing, Diploma in Orthopedics".
  final String? qualifications;
  final String? hospitalAffiliation;
  final String? nursingLicense;
  final String? bio;
  final int yearsExperience;
  final double rating;
  final int reviewCount;
  final String? phone;
  final String? email;
  final bool isVerifiedNurse;
  final double fee;
  final int serviceRadiusKm;
  final List<AssignedDoctorExperience> experience;

  const AssignedNurse({
    required this.id,
    required this.fullName,
    this.profilePicture,
    this.specialty = '',
    this.qualifications,
    this.hospitalAffiliation,
    this.nursingLicense,
    this.bio,
    this.yearsExperience = 0,
    this.rating = 0,
    this.reviewCount = 0,
    this.phone,
    this.email,
    this.isVerifiedNurse = false,
    this.fee = 0,
    this.serviceRadiusKm = 0,
    this.experience = const [],
  });

  /// Two-letter initials for the avatar fallback. Strips any "Nurse"
  /// or "Dr." prefix so initials reflect the actual name.
  String get initials {
    final cleaned = fullName
        .replaceAll(RegExp(r'^(Nurse|N\.|Sister|[Dd]r\.?)\s+'), '')
        .trim();
    if (cleaned.isEmpty) return 'NR';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final s = parts.first;
      return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  List<Object?> get props => [
        id,
        fullName,
        profilePicture,
        specialty,
        qualifications,
        hospitalAffiliation,
        nursingLicense,
        bio,
        yearsExperience,
        rating,
        reviewCount,
        phone,
        email,
        isVerifiedNurse,
        fee,
        serviceRadiusKm,
        experience,
      ];

  factory AssignedNurse.fromJson(Map<String, dynamic> json) {
    String? nonEmpty(dynamic v) {
      final s = v?.toString();
      if (s == null || s.trim().isEmpty) return null;
      return s;
    }

    final rawExperience = (json['experience'] as List?) ?? const [];
    return AssignedNurse(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      fullName: (json['full_name'] ?? json['fullName'] ?? '').toString(),
      profilePicture:
          nonEmpty(json['profile_picture'] ?? json['profilePicture']),
      specialty: (json['specialty'] ?? json['specialization'] ?? '').toString(),
      qualifications: nonEmpty(json['degrees'] ?? json['qualifications']),
      hospitalAffiliation:
          nonEmpty(json['hospital_affiliation'] ?? json['hospitalAffiliation']),
      nursingLicense:
          nonEmpty(json['nursing_license'] ?? json['nursingLicense']),
      bio: nonEmpty(json['bio']),
      yearsExperience: (json['years_experience'] as num?)?.toInt() ??
          (json['yearsExperience'] as num?)?.toInt() ??
          0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ??
          (json['reviewCount'] as num?)?.toInt() ??
          0,
      phone: nonEmpty(json['phone']),
      email: nonEmpty(json['email']),
      isVerifiedNurse: (json['is_verified_nurse'] as bool?) ??
          (json['isVerifiedNurse'] as bool?) ??
          ((json['verification_status'] ?? '').toString().toLowerCase() ==
              'verified'),
      fee: (json['fee'] as num?)?.toDouble() ?? 0,
      serviceRadiusKm: (json['service_radius_km'] as num?)?.toInt() ??
          (json['serviceRadiusKm'] as num?)?.toInt() ??
          0,
      experience: rawExperience
          .map((e) => AssignedDoctorExperience.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
    );
  }
}
